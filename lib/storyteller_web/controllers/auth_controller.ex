defmodule StorytellerWeb.AuthController do
  use StorytellerWeb, :controller

  alias Storyteller.Auth.OAuth

  def connect(conn, _params) do
    render(conn, :connect, status: OAuth.status())
  end

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
          put_flash(conn, :info, "Connected to the ChatGPT account #{email}.")

        {:ok, _account} ->
          put_flash(conn, :info, "Connected to your ChatGPT account.")

        {:error, :access_denied} ->
          put_flash(
            conn,
            :error,
            "ChatGPT sign-in was cancelled. Your current connection is unchanged."
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
          put_flash(conn, :info, "Disconnected. Local ChatGPT credentials were cleared.")

        {:error, :revocation_unconfirmed} ->
          put_flash(
            conn,
            :error,
            "Local credentials were cleared, but ChatGPT did not confirm revocation. You can also disconnect Storyteller in ChatGPT Settings."
          )

        {:error, _reason} ->
          put_flash(
            conn,
            :error,
            "Local credentials could not be cleared. Please retry disconnecting."
          )
      end

    redirect(conn, to: ~p"/auth/connect")
  end

  defp auth_message(:identity_provider_unavailable),
    do: "ChatGPT sign-in is temporarily unavailable. Your current connection is unchanged."

  defp auth_message(:access_denied), do: "ChatGPT sign-in was cancelled."

  defp auth_message(:account_ineligible),
    do:
      "This ChatGPT account did not grant plan usage access. Your current connection is unchanged."

  defp auth_message(:invalid_id_token),
    do: "ChatGPT identity could not be verified. Your current connection is unchanged."

  defp auth_message(:invalid_authorization_response),
    do: "The sign-in response was incomplete or expired. Please start again."

  defp auth_message(:client_id_mismatch),
    do:
      "The sign-in response did not match the saved ChatGPT registration. Your current connection is unchanged."

  defp auth_message(_reason),
    do: "ChatGPT sign-in could not be completed. Your current connection is unchanged."
end
