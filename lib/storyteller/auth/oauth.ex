defmodule Storyteller.Auth.OAuth do
  @moduledoc """
  Sign in with ChatGPT's public open-source OAuth flow and local token lifecycle.

  OAuth attempts remain pending in the local token-store process until their
  state is consumed. A newly authorized identity replaces the active credentials
  only after the token response, ID token, scopes, and account binding validate.
  """

  alias Storyteller.Auth.{Credentials, HTTP, OIDC, TokenStore}

  @dynamic_client_id "dynamic_agent_client"
  @resource "https://api.openai.com/v1"
  @scopes "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
  @max_access_token_seconds 86_400

  @doc "Starts a browser authorization attempt and returns its complete URL."
  def start_authorization(opts \\ []) do
    store = store(opts)
    http = http(opts)
    oidc = oidc(opts)

    with {:ok, metadata} <- provider_metadata(oidc, http),
         callback_uri <- callback_uri(opts),
         :ok <- validate_callback_uri(callback_uri),
         host_id when is_binary(host_id) <- TokenStore.host_id(store),
         registration <- TokenStore.registration(store),
         credentials <- TokenStore.credentials(store),
         attempt <- new_attempt(registration, callback_uri, host_id),
         url <- authorization_url(metadata, attempt, registration, credentials, opts),
         :ok <- TokenStore.remember_attempt(attempt, store) do
      {:ok, url}
    else
      {:error, _} = error -> error
      _ -> {:error, :authorization_unavailable}
    end
  rescue
    _ -> {:error, :authorization_unavailable}
  end

  @doc "Completes a loopback callback after consuming its one-use state."
  def callback(params, opts \\ [])

  def callback(params, opts) when is_map(params) do
    store = store(opts)
    http = http(opts)
    oidc = oidc(opts)

    with state when is_binary(state) and state != "" <- params["state"],
         {:ok, attempt} <- TokenStore.consume_attempt(state, store),
         :ok <- callback_error(params),
         code when is_binary(code) and code != "" <- params["code"],
         {:ok, client_id} <- callback_client_id(params, attempt),
         {:ok, token_response} <-
           exchange_code(metadata(oidc, http), code, client_id, attempt, http),
         {:ok, credentials} <-
           validated_credentials(token_response, attempt, client_id, oidc, http),
         :ok <- TokenStore.put_credentials(credentials, store) do
      {:ok, %{email: credentials.email}}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_authorization_response}
    end
  rescue
    _ -> {:error, :invalid_authorization_response}
  end

  def callback(_params, _opts), do: {:error, :invalid_authorization_response}

  @doc "Returns account status without exposing credentials or tokens."
  def status(opts \\ []) do
    registration = TokenStore.registration(store(opts))
    credentials = TokenStore.credentials(store(opts))

    connected? =
      case credentials do
        %Credentials{} -> Credentials.plan_usage_enabled?(credentials)
        _ -> false
      end

    %{
      connected?: connected?,
      plan_usage_enabled?: connected?,
      account_email: (credentials && credentials.email) || (registration && registration.email),
      registered?: not is_nil(registration)
    }
  rescue
    _ ->
      %{connected?: false, plan_usage_enabled?: false, account_email: nil, registered?: false}
  end

  @doc "Returns an access token, refreshing and persisting its rotation serially."
  def access_token(opts \\ []) do
    TokenStore.access_token(
      fn credentials -> refresh_credentials(credentials, http(opts), oidc(opts)) end,
      store(opts)
    )
  end

  @doc "Revokes the renewable session where possible and always clears local tokens."
  def disconnect(opts \\ []) do
    TokenStore.sign_out(
      fn credentials -> revoke(credentials, http(opts), oidc(opts)) end,
      store(opts)
    )
  end

  defp new_attempt(registration, callback_uri, host_id) do
    verifier = random_url_token(32)

    %{
      state: random_url_token(32),
      nonce: random_url_token(32),
      verifier: verifier,
      challenge: :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false),
      callback_uri: callback_uri,
      host_id: host_id,
      client_id: if(registration, do: registration.client_id, else: @dynamic_client_id),
      expected_subject: registration && registration.subject,
      registration?: not is_nil(registration)
    }
  end

  defp authorization_url(metadata, attempt, registration, credentials, opts) do
    params = [
      {"client_id", attempt.client_id},
      {"response_type", "code"},
      {"redirect_uri", attempt.callback_uri},
      {"scope", @scopes},
      {"resource", @resource},
      {"state", attempt.state},
      {"nonce", attempt.nonce},
      {"code_challenge_method", "S256"},
      {"code_challenge", attempt.challenge},
      {"ext_agent_host_id", attempt.host_id}
    ]

    params =
      if attempt.registration? do
        params
        |> maybe_add("id_token_hint", credentials && credentials.id_token)
        |> maybe_add("login_hint", registration && registration.email)
      else
        params
        |> Kernel.++([{"agent_name_hint", app_name(opts)}])
      end

    metadata["authorization_endpoint"] <> "?" <> URI.encode_query(params)
  end

  defp exchange_code({:ok, metadata}, code, client_id, attempt, http) do
    form = [
      grant_type: "authorization_code",
      client_id: client_id,
      code: code,
      code_verifier: attempt.verifier,
      redirect_uri: attempt.callback_uri,
      resource: @resource
    ]

    case HTTP.request(
           :post,
           metadata["token_endpoint"],
           [form: form, headers: [{"accept", "application/json"}]],
           http
         ) do
      {:ok, response} ->
        if response_status(response) == 200 do
          case HTTP.decode_json(response_body(response)) do
            {:ok, token_response} -> {:ok, token_response}
            _ -> {:error, :identity_provider_unavailable}
          end
        else
          {:error, token_endpoint_error(response_status(response), response_body(response))}
        end

      _ ->
        {:error, :identity_provider_unavailable}
    end
  end

  defp exchange_code(_, _code, _client_id, _attempt, _http),
    do: {:error, :identity_provider_unavailable}

  defp validated_credentials(token_response, attempt, client_id, oidc, http) do
    with access_token when is_binary(access_token) and access_token != "" <-
           token_response["access_token"],
         refresh_token when is_binary(refresh_token) and refresh_token != "" <-
           token_response["refresh_token"],
         id_token when is_binary(id_token) and id_token != "" <- token_response["id_token"],
         token_type when is_binary(token_type) <- token_response["token_type"],
         true <- String.downcase(token_type) == "bearer",
         expires_in
         when is_integer(expires_in) and expires_in > 0 and
                expires_in <= @max_access_token_seconds <- token_response["expires_in"],
         {:ok, scopes} <- granted_scopes(token_response),
         true <- "chatgpt.tokens.use.direct" in scopes and "offline_access" in scopes,
         {:ok, claims} <- verify_id_token(oidc, id_token, client_id, attempt.nonce, http),
         :ok <- account_matches?(claims["sub"], attempt.expected_subject),
         email <- claims["email"],
         true <- is_nil(email) or is_binary(email) do
      {:ok,
       %Credentials{
         client_id: client_id,
         subject: claims["sub"],
         email: email,
         host_id: attempt.host_id,
         id_token: id_token,
         access_token: access_token,
         refresh_token: refresh_token,
         expires_at: System.system_time(:second) + expires_in,
         scopes: scopes
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, :account_ineligible}
    end
  end

  defp refresh_credentials(credentials, http, oidc) do
    with {:ok, metadata} <- provider_metadata(oidc, http),
         {:ok, response} <-
           HTTP.request(
             :post,
             metadata["token_endpoint"],
             [
               form: [
                 grant_type: "refresh_token",
                 client_id: credentials.client_id,
                 refresh_token: credentials.refresh_token,
                 resource: @resource
               ],
               headers: [{"accept", "application/json"}]
             ],
             http
           ) do
      case response_status(response) do
        200 ->
          with {:ok, body} <- HTTP.decode_json(response_body(response)),
               {:ok, updated} <- refreshed_credentials(body, credentials) do
            {:ok, updated}
          else
            _ -> {:error, :temporary_auth_error}
          end

        status ->
          refresh_endpoint_error(status, response_body(response))
      end
    else
      {:error, {:terminal_refresh, _} = reason} -> {:error, reason}
      {:error, _} -> {:error, :temporary_auth_error}
      _ -> {:error, :temporary_auth_error}
    end
  rescue
    _ -> {:error, :temporary_auth_error}
  end

  defp refreshed_credentials(body, current) do
    access_token = body["access_token"]
    refresh_token = body["refresh_token"] || current.refresh_token
    expires_in = body["expires_in"]

    with true <- is_binary(access_token) and access_token != "",
         true <- is_binary(refresh_token) and refresh_token != "",
         true <-
           is_integer(expires_in) and expires_in > 0 and
             expires_in <= @max_access_token_seconds,
         {:ok, scopes} <- optional_granted_scopes(body, current.scopes),
         true <- "chatgpt.tokens.use.direct" in scopes do
      {:ok,
       %{
         current
         | access_token: access_token,
           refresh_token: refresh_token,
           expires_at: System.system_time(:second) + expires_in,
           scopes: scopes
       }}
    else
      _ -> {:error, :invalid_refresh_response}
    end
  end

  defp revoke(%Credentials{refresh_token: refresh_token} = credentials, http, oidc)
       when is_binary(refresh_token) and refresh_token != "" do
    with {:ok, metadata} <- provider_metadata(oidc, http),
         endpoint when is_binary(endpoint) <- metadata["revocation_endpoint"] do
      revoke_with_retry(endpoint, credentials, http, 2)
    else
      _ -> :error
    end
  end

  defp revoke(_credentials, _http, _oidc), do: :ok

  defp revoke_with_retry(endpoint, credentials, http, attempts_left) do
    result =
      case HTTP.request(
             :post,
             endpoint,
             [
               form: [
                 token: credentials.refresh_token,
                 token_type_hint: "refresh_token",
                 client_id: credentials.client_id
               ],
               headers: [{"accept", "application/json"}]
             ],
             http
           ) do
        {:ok, response} ->
          case response_status(response) do
            200 -> :ok
            status when is_integer(status) and status >= 500 -> :retry
            _ -> :error
          end

        {:error, reason} when reason in [:network_error, :timeout] ->
          :retry

        _ ->
          :error
      end

    case {result, attempts_left} do
      {:retry, remaining} when remaining > 0 ->
        Process.sleep(200)
        revoke_with_retry(endpoint, credentials, http, remaining - 1)

      {:retry, _} ->
        :error

      other ->
        other
    end
  end

  defp callback_client_id(params, %{client_id: @dynamic_client_id}) do
    case params["client_id"] do
      value when is_binary(value) and value != "" and value != @dynamic_client_id -> {:ok, value}
      _ -> {:error, :invalid_client_id}
    end
  end

  defp callback_client_id(params, %{client_id: expected}) do
    case params["client_id"] do
      nil -> {:ok, expected}
      ^expected -> {:ok, expected}
      _ -> {:error, :client_id_mismatch}
    end
  end

  defp callback_error(%{"error" => "access_denied"}), do: {:error, :access_denied}

  defp callback_error(%{"error" => error}) when is_binary(error),
    do: {:error, :authorization_failed}

  defp callback_error(_), do: :ok

  defp verify_id_token(oidc, token, client_id, nonce, http) do
    apply(oidc, :verify_id_token, [token, %{client_id: client_id, nonce: nonce}, http])
  rescue
    _ -> {:error, :invalid_id_token}
  end

  defp account_matches?(_subject, nil), do: :ok

  defp account_matches?(subject, expected) when is_binary(subject) and subject == expected,
    do: :ok

  defp account_matches?(_subject, _expected), do: {:error, :account_mismatch}

  defp provider_metadata(oidc, http) do
    case apply(oidc, :metadata, [http]) do
      {:ok, metadata} when is_map(metadata) -> {:ok, metadata}
      _ -> {:error, :identity_provider_unavailable}
    end
  rescue
    _ -> {:error, :identity_provider_unavailable}
  end

  defp metadata(oidc, http), do: provider_metadata(oidc, http)

  defp granted_scopes(body) do
    scopes = body["scopes"]
    scope = body["scope"]

    case {scopes, scope} do
      {values, nil} when is_list(values) ->
        validate_scope_list(values)

      {nil, value} when is_binary(value) ->
        {:ok, String.split(value, ~r/\s+/, trim: true)}

      {values, value} when is_list(values) and is_binary(value) ->
        with {:ok, values} <- validate_scope_list(values),
             {:ok, parsed} <- {:ok, String.split(value, ~r/\s+/, trim: true)},
             true <- MapSet.new(values) == MapSet.new(parsed) do
          {:ok, values}
        else
          _ -> {:error, :invalid_scope}
        end

      _ ->
        {:error, :invalid_scope}
    end
  end

  defp optional_granted_scopes(body, existing) do
    if is_nil(body["scopes"]) and is_nil(body["scope"]) do
      {:ok, existing}
    else
      granted_scopes(body)
    end
  end

  defp validate_scope_list(values) do
    if Enum.all?(values, &(is_binary(&1) and &1 != "")),
      do: {:ok, Enum.uniq(values)},
      else: {:error, :invalid_scope}
  end

  defp token_endpoint_error(status, _body) when status in [400, 401],
    do: :authorization_failed

  defp token_endpoint_error(_, _body), do: :identity_provider_unavailable

  defp refresh_endpoint_error(status, body) when status in [400, 401, 403] do
    case HTTP.decode_json(body) do
      {:ok, %{"error" => error}} when error in ["invalid_grant", "invalid_token"] ->
        {:error, {:terminal_refresh, :invalid_grant}}

      _ when status in [401, 403] ->
        {:error, {:terminal_refresh, :unauthorized}}

      _ ->
        {:error, :temporary_auth_error}
    end
  end

  defp refresh_endpoint_error(_, _body), do: {:error, :temporary_auth_error}

  defp callback_uri(opts) do
    Keyword.get(config(), :callback_uri, "http://127.0.0.1:4000/auth/callback")
    |> then(fn configured -> Keyword.get(opts, :callback_uri, configured) end)
  end

  defp validate_callback_uri(uri) do
    case URI.parse(uri) do
      %URI{
        scheme: "http",
        host: "127.0.0.1",
        port: 4000,
        path: "/auth/callback",
        userinfo: nil,
        query: nil,
        fragment: nil
      } ->
        :ok

      _ ->
        {:error, :invalid_callback_uri}
    end
  end

  defp app_name(opts),
    do: Keyword.get(opts, :app_name, Keyword.get(config(), :app_name, "Storyteller"))

  defp http(opts), do: Keyword.get(opts, :http, Keyword.get(config(), :http))
  defp oidc(opts), do: Keyword.get(opts, :oidc, OIDC)
  defp store(opts), do: Keyword.get(opts, :store, TokenStore)
  defp config, do: Application.get_env(:storyteller, __MODULE__, [])

  defp random_url_token(bytes),
    do: :crypto.strong_rand_bytes(bytes) |> Base.url_encode64(padding: false)

  defp maybe_add(params, _key, nil), do: params

  defp maybe_add(params, key, value) when is_binary(value) and value != "",
    do: params ++ [{key, value}]

  defp maybe_add(params, _key, _value), do: params

  defp response_status(%{status: status}) when is_integer(status), do: status
  defp response_status(%{"status" => status}) when is_integer(status), do: status
  defp response_status(_), do: nil

  defp response_body(%{body: body}), do: body
  defp response_body(%{"body" => body}), do: body
  defp response_body(_), do: nil
end
