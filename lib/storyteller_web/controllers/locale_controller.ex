defmodule StorytellerWeb.LocaleController do
  use StorytellerWeb, :controller

  alias Storyteller.Settings

  def update(conn, %{"locale" => locale}) do
    case Settings.set_ui_locale(locale) do
      {:ok, _preference} ->
        Elixir.Gettext.put_locale(StorytellerWeb.Gettext, locale)

        conn
        |> put_session(:ui_locale, locale)
        |> put_flash(:info, gettext("Interface language updated."))
        |> redirect(to: return_path(conn))

      {:error, _reason} ->
        conn
        |> put_flash(:error, gettext("Choose English, Spanish, or French."))
        |> redirect(to: return_path(conn))
    end
  end

  def update(conn, _params) do
    conn
    |> put_flash(:error, gettext("Choose English, Spanish, or French."))
    |> redirect(to: return_path(conn))
  end

  defp return_path(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{host: host, path: path, query: query} <- URI.parse(referer),
         true <- host in [nil, conn.host],
         true <- is_binary(path) and String.starts_with?(path, "/"),
         false <- String.starts_with?(path, "//") do
      if query, do: path <> "?" <> query, else: path
    else
      _ -> "/"
    end
  end
end
