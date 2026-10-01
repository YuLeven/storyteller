defmodule StorytellerWeb.AuthController do
  use StorytellerWeb, :controller

  alias Storyteller.Auth.OAuth
  alias Storyteller.Settings

  def connect(conn, _params) do
    status = OAuth.status()
    preferred_model = Settings.preferred_gm_model()

    {models, catalog_available?} =
      if status.connected? do
        case model_catalog() do
          {:ok, models} -> {models, true}
          {:error, _reason} -> {[], false}
        end
      else
        {[], false}
      end

    render(conn, :connect,
      status: status,
      models: models,
      catalog_available?: catalog_available?,
      preferred_model: preferred_model,
      model_summary: model_summary(preferred_model, models, catalog_available?)
    )
  end

  def update_model(conn, %{"model" => "automatic"}) do
    case Settings.set_preferred_gm_model(nil) do
      {:ok, _preference} ->
        conn
        |> put_flash(:info, gettext("GM model preference reset to automatic."))
        |> redirect(to: ~p"/auth/connect")

      {:error, _changeset} ->
        model_update_error(conn)
    end
  end

  def update_model(conn, %{"model" => model_slug}) when is_binary(model_slug) do
    status = OAuth.status()

    result =
      if status.connected? do
        with {:ok, models} <- model_catalog(),
             true <- Enum.any?(models, &(&1.slug == model_slug)) do
          Settings.set_preferred_gm_model(model_slug)
        else
          _ -> {:error, :model_unavailable}
        end
      else
        {:error, :account_disconnected}
      end

    case result do
      {:ok, _preference} ->
        conn
        |> put_flash(:info, gettext("GM model preference updated."))
        |> redirect(to: ~p"/auth/connect")

      {:error, _reason} ->
        conn
        |> put_flash(
          :error,
          gettext("Choose a model from the connected account's available models.")
        )
        |> redirect(to: ~p"/auth/connect")
    end
  end

  def update_model(conn, _params), do: model_update_error(conn)

  def authorize(conn, _params) do
    case OAuth.start_authorization() do
      {:ok, url} ->
        redirect(conn, external: url)

      {:error, reason} ->
        conn
        |> put_flash(:error, auth_message(reason))
        |> redirect(to: ~p"/auth/connect")
    end
  end

  def callback(conn, params) do
    conn =
      case OAuth.callback(params) do
        {:ok, %{email: email}} when is_binary(email) ->
          put_flash(
            conn,
            :info,
            gettext("Connected to the ChatGPT account %{email}.", email: email)
          )

        {:ok, _account} ->
          put_flash(conn, :info, gettext("Connected to your ChatGPT account."))

        {:error, :access_denied} ->
          put_flash(
            conn,
            :error,
            gettext("ChatGPT sign-in was cancelled. Your current connection is unchanged.")
          )

        {:error, reason} ->
          put_flash(conn, :error, auth_message(reason))
      end

    redirect(conn, to: ~p"/auth/connect")
  end

  def disconnect(conn, _params) do
    conn =
      case OAuth.disconnect() do
        {:ok, :revoked} ->
          put_flash(conn, :info, gettext("Disconnected. Local ChatGPT credentials were cleared."))

        {:error, :revocation_unconfirmed} ->
          put_flash(
            conn,
            :error,
            gettext(
              "Local credentials were cleared, but ChatGPT did not confirm revocation. You can also disconnect Storyteller in ChatGPT Settings."
            )
          )

        {:error, _reason} ->
          put_flash(
            conn,
            :error,
            gettext("Local credentials could not be cleared. Please retry disconnecting.")
          )
      end

    redirect(conn, to: ~p"/auth/connect")
  end

  defp model_update_error(conn) do
    conn
    |> put_flash(:error, gettext("The GM model preference could not be saved. Please retry."))
    |> redirect(to: ~p"/auth/connect")
  end

  defp model_catalog do
    provider = Application.get_env(:storyteller, :gm_model_catalog, Storyteller.GM.OpenAI)

    case provider.models() do
      {:ok, models} when is_list(models) ->
        models =
          Enum.filter(models, fn
            %{slug: slug, display_name: display_name} ->
              is_binary(slug) and slug != "" and is_binary(display_name) and display_name != ""

            _ ->
              false
          end)

        if models == [], do: {:error, :model_unavailable}, else: {:ok, models}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :invalid_response}
    end
  rescue
    _error -> {:error, :provider_error}
  end

  defp model_summary(nil, [first_model | _models], true) do
    gettext(
      "Automatic (first model in account list: %{model})",
      model: model_label(first_model)
    )
  end

  defp model_summary(nil, _models, _catalog_available?), do: gettext("Automatic")

  defp model_summary(model_slug, models, catalog_available?) do
    case Enum.find(models, &(&1.slug == model_slug)) do
      model when is_map(model) ->
        model_label(model)

      nil when catalog_available? ->
        gettext("Saved model no longer listed: %{model}", model: model_slug)

      nil ->
        model_slug
    end
  end

  defp model_label(%{display_name: display_name, slug: slug}),
    do: "#{display_name} (#{slug})"

  defp auth_message(:identity_provider_unavailable),
    do:
      gettext("ChatGPT sign-in is temporarily unavailable. Your current connection is unchanged.")

  defp auth_message(:access_denied), do: gettext("ChatGPT sign-in was cancelled.")

  defp auth_message(:account_ineligible),
    do:
      gettext(
        "This ChatGPT account did not grant plan usage access. Your current connection is unchanged."
      )

  defp auth_message(:invalid_id_token),
    do: gettext("ChatGPT identity could not be verified. Your current connection is unchanged.")

  defp auth_message(:invalid_authorization_response),
    do: gettext("The sign-in response was incomplete or expired. Please start again.")

  defp auth_message(:client_id_mismatch),
    do:
      gettext(
        "The sign-in response did not match the saved ChatGPT registration. Your current connection is unchanged."
      )

  defp auth_message(_reason),
    do: gettext("ChatGPT sign-in could not be completed. Your current connection is unchanged.")
end
