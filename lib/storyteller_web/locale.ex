defmodule StorytellerWeb.Locale do
  @moduledoc "Loads the persisted interface locale for HTTP and LiveView rendering."

  @behaviour Plug

  import Plug.Conn

  alias Storyteller.Settings

  def init(opts), do: opts

  def call(conn, _opts) do
    locale = Settings.ui_locale()
    Elixir.Gettext.put_locale(StorytellerWeb.Gettext, locale)

    conn
    |> assign(:ui_locale, locale)
    |> put_session(:ui_locale, locale)
  end

  def on_mount(:default, _params, session, socket) do
    locale =
      case session["ui_locale"] do
        locale when locale in ["en", "es", "fr"] -> locale
        _ -> Settings.ui_locale()
      end

    Elixir.Gettext.put_locale(StorytellerWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :ui_locale, locale)}
  end
end
