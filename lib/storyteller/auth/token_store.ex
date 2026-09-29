defmodule Storyteller.Auth.TokenStore do
  @moduledoc "Serialized access to protected local ChatGPT plan credentials."

  use GenServer

  import Bitwise

  alias Storyteller.Auth.Credentials

  @attempt_ttl_seconds 600
  @refresh_skew_seconds 90
  @schema_version 1

  def start_link(opts) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @impl true
  def init(opts) do
    path = Keyword.fetch!(opts, :path)

    case read_state(path) do
      {:ok, host_id, credentials} ->
        {:ok, %{path: path, host_id: host_id, credentials: credentials, attempts: %{}}}

      :missing ->
        state = %{
          path: path,
          host_id: "urn:uuid:" <> Ecto.UUID.generate(),
          credentials: nil,
          attempts: %{}
        }

        case persist(state) do
          :ok -> {:ok, state}
          {:error, _} -> {:stop, :credential_store_unavailable}
        end

      {:error, _} ->
        {:stop, :credential_store_unreadable}
    end
  end

  def host_id(server \\ __MODULE__), do: GenServer.call(server, :host_id)
  def credentials(server \\ __MODULE__), do: GenServer.call(server, :credentials)
  def registration(server \\ __MODULE__), do: GenServer.call(server, :registration)

  def remember_attempt(attempt, server \\ __MODULE__) when is_map(attempt) do
    GenServer.call(server, {:remember_attempt, attempt})
  end

  def consume_attempt(state_value, server \\ __MODULE__) when is_binary(state_value) do
    GenServer.call(server, {:consume_attempt, state_value})
  end

  def put_credentials(%Credentials{} = credentials, server \\ __MODULE__) do
    GenServer.call(server, {:put_credentials, credentials})
  end

  def access_token(refresh_fun, server \\ __MODULE__) when is_function(refresh_fun, 1) do
    GenServer.call(server, {:access_token, refresh_fun}, 60_000)
  end

  def sign_out(revoke_fun, server \\ __MODULE__) when is_function(revoke_fun, 1) do
    GenServer.call(server, {:sign_out, revoke_fun}, 90_000)
  end

  @impl true
  def handle_call(:host_id, _from, state), do: {:reply, state.host_id, state}

  def handle_call(:credentials, _from, state) do
    {:reply, state.credentials, expire_attempts(state)}
  end

  def handle_call(:registration, _from, state) do
    registration =
      case state.credentials do
        %Credentials{} = credentials ->
          Map.take(credentials, [:client_id, :subject, :email, :host_id])

        nil ->
          nil
      end

    {:reply, registration, expire_attempts(state)}
  end

  def handle_call({:remember_attempt, attempt}, _from, state) do
    state = expire_attempts(state)
    state_value = Map.fetch!(attempt, :state)
    expires_at = System.monotonic_time(:second) + @attempt_ttl_seconds
    attempt = Map.put(attempt, :expires_at_monotonic, expires_at)
    {:reply, :ok, put_in(state.attempts[state_value], attempt)}
  end

  def handle_call({:consume_attempt, state_value}, _from, state) do
    state = expire_attempts(state)

    case Map.pop(state.attempts, state_value) do
      {nil, _attempts} ->
        {:reply, {:error, :invalid_or_expired_state}, state}

      {attempt, attempts} ->
        {:reply, {:ok, Map.delete(attempt, :expires_at_monotonic)}, %{state | attempts: attempts}}
    end
  end

  def handle_call({:put_credentials, %Credentials{host_id: host_id} = credentials}, _from, state) do
    cond do
      host_id != state.host_id ->
        {:reply, {:error, :host_mismatch}, state}

      not same_registration?(state.credentials, credentials) ->
        {:reply, {:error, :account_mismatch}, state}

      true ->
        persist_credentials(credentials, state)
    end
  end

  def handle_call({:access_token, _refresh_fun}, _from, %{credentials: nil} = state) do
    {:reply, {:error, :not_authenticated}, expire_attempts(state)}
  end

  def handle_call({:access_token, refresh_fun}, _from, state) do
    credentials = state.credentials

    cond do
      not Credentials.plan_usage_enabled?(credentials) ->
        {:reply, {:error, :plan_usage_not_authorized}, expire_attempts(state)}

      is_integer(credentials.expires_at) and
          credentials.expires_at > now() + @refresh_skew_seconds ->
        {:reply, {:ok, credentials.access_token}, expire_attempts(state)}

      not is_binary(credentials.refresh_token) ->
        {:reply, {:error, :reauth_required}, expire_attempts(state)}

      true ->
        refresh_credentials(refresh_fun, state)
    end
  end

  def handle_call({:sign_out, revoke_fun}, _from, state) do
    credentials = state.credentials
    remote_result = if credentials, do: safely_revoke(revoke_fun, credentials), else: :ok
    sanitized = if credentials, do: Credentials.clear_tokens(credentials), else: nil

    state = %{state | credentials: sanitized, attempts: %{}}

    case persist(state) do
      :ok ->
        reply =
          if remote_result == :ok, do: {:ok, :revoked}, else: {:error, :revocation_unconfirmed}

        {:reply, reply, state}

      {:error, _} ->
        _ = File.rm(state.path)

        reply =
          if remote_result == :ok,
            do: {:error, :credential_store_unavailable},
            else: {:error, :revocation_unconfirmed}

        {:reply, reply, state}
    end
  end

  defp refresh_credentials(refresh_fun, state) do
    case safely_refresh(refresh_fun, state.credentials) do
      {:ok, %Credentials{host_id: host_id} = updated}
      when host_id == state.host_id and
             updated.client_id == state.credentials.client_id and
             updated.subject == state.credentials.subject ->
        updated_state = %{state | credentials: updated}

        case persist(updated_state) do
          :ok ->
            {:reply, {:ok, updated.access_token}, updated_state}

          {:error, _} ->
            {:reply, {:error, :credential_store_unavailable}, updated_state}
        end

      {:error, {:terminal_refresh, _code}} ->
        sanitized = Credentials.clear_tokens(state.credentials)
        state = %{state | credentials: sanitized}

        case persist(state) do
          :ok ->
            {:reply, {:error, :reauth_required}, state}

          {:error, _} ->
            _ = File.rm(state.path)
            {:reply, {:error, :reauth_required}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, expire_attempts(state)}

      _ ->
        {:reply, {:error, :invalid_refresh_response}, expire_attempts(state)}
    end
  end

  defp persist_credentials(credentials, state) do
    updated = %{state | credentials: credentials}

    case persist(updated) do
      :ok -> {:reply, :ok, updated}
      {:error, _} -> {:reply, {:error, :credential_store_unavailable}, state}
    end
  end

  defp safely_refresh(fun, credentials) do
    case fun.(credentials) do
      {:ok, %Credentials{} = updated} -> {:ok, updated}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_refresh_response}
    end
  rescue
    _ -> {:error, :temporary_auth_error}
  catch
    _, _ -> {:error, :temporary_auth_error}
  end

  defp safely_revoke(fun, credentials) do
    case fun.(credentials) do
      :ok -> :ok
      {:ok, _} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp expire_attempts(state) do
    now = System.monotonic_time(:second)

    attempts =
      Map.reject(state.attempts, fn {_key, attempt} -> attempt.expires_at_monotonic <= now end)

    %{state | attempts: attempts}
  end

  defp read_state(path) do
    case File.lstat(path) do
      {:ok, %{type: :regular}} ->
        with :ok <- secure_existing_store(path),
             {:ok, content} <- File.read(path),
             {:ok, %{"version" => @schema_version, "host_id" => host_id} = data} <-
               Jason.decode(content),
             true <- valid_host_id?(host_id),
             {:ok, credentials} <- read_credentials(data["credentials"], host_id) do
          {:ok, host_id, credentials}
        else
          _ -> {:error, :invalid_credential_file}
        end

      {:error, :enoent} ->
        :missing

      {:ok, _other_type} ->
        {:error, :invalid_credential_file}

      {:error, _} ->
        {:error, :credential_file_unreadable}
    end
  rescue
    _ -> {:error, :invalid_credential_file}
  end

  defp read_credentials(nil, _host_id), do: {:ok, nil}

  defp read_credentials(map, host_id) when is_map(map) do
    with {:ok, credentials} <- Credentials.from_persisted(map),
         true <- credentials.host_id == host_id do
      {:ok, credentials}
    else
      _ -> {:error, :invalid_credential_record}
    end
  end

  defp read_credentials(_, _host_id), do: {:error, :invalid_credential_record}

  defp persist(state) do
    directory = Path.dirname(state.path)
    temporary_path = state.path <> "." <> Ecto.UUID.generate() <> ".tmp"

    data = %{
      "version" => @schema_version,
      "host_id" => state.host_id,
      "credentials" =>
        case state.credentials do
          %Credentials{} = credentials -> Credentials.persisted_fields(credentials)
          nil -> nil
        end
    }

    try do
      with :ok <- File.mkdir_p(directory),
           :ok <- secure_directory(directory),
           :ok <- File.write(temporary_path, Jason.encode!(data), [:binary, :sync]),
           :ok <- File.chmod(temporary_path, 0o600),
           :ok <- File.rename(temporary_path, state.path),
           :ok <- File.chmod(state.path, 0o600) do
        :ok
      else
        {:error, _} -> {:error, :credential_store_unavailable}
      end
    rescue
      _ -> {:error, :credential_store_unavailable}
    after
      _ = File.rm(temporary_path)
    end
  end

  defp secure_existing_store(path) do
    directory = Path.dirname(path)

    with :ok <- secure_directory(directory),
         {:ok, file_stat} <- File.lstat(path),
         true <- file_stat.type == :regular,
         :ok <- File.chmod(path, 0o600),
         {:ok, secured_file_stat} <- File.stat(path),
         true <- band(secured_file_stat.mode, 0o777) == 0o600 do
      :ok
    else
      _ -> {:error, :credential_store_permissions}
    end
  end

  defp secure_directory(directory) do
    with {:ok, directory_stat} <- File.lstat(directory),
         true <- directory_stat.type == :directory,
         :ok <- File.chmod(directory, 0o700),
         {:ok, secured_directory_stat} <- File.stat(directory),
         true <- band(secured_directory_stat.mode, 0o777) == 0o700 do
      :ok
    else
      _ -> {:error, :credential_store_permissions}
    end
  end

  defp valid_host_id?("urn:uuid:" <> uuid), do: match?({:ok, _}, Ecto.UUID.cast(uuid))
  defp valid_host_id?(_), do: false

  defp now, do: System.system_time(:second)

  defp same_registration?(nil, _credentials), do: true

  defp same_registration?(%Credentials{} = current, %Credentials{} = replacement) do
    current.client_id == replacement.client_id and current.subject == replacement.subject
  end
end
