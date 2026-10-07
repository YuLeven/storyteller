defmodule StorytellerWeb.AuthControllerTest do
  use StorytellerWeb.ConnCase, async: false

  alias Storyteller.Auth.{Credentials, TokenStore}
  alias Storyteller.Settings
  alias StorytellerWeb.{AuthController, Router}

  test "connection page states the local MIT and plan-usage prerequisites", %{conn: conn} do
    html = conn |> get("/auth/connect") |> html_response(200)

    assert html =~ "Connection status"
    assert html =~ "MIT license"
    assert html =~ "eligible open-source, locally hosted apps"
    assert html =~ "does not use an API key or API credits"

    assert html =~
             "When ChatGPT reports a plan usage limit, Storyteller pauses game-master requests across all sessions. Check ChatGPT Usage settings, then resume from a session when you believe requests are available and retry the saved turn."

    refute html =~ "Storyteller pauses play"
    assert html =~ "Continue with ChatGPT"
    assert html =~ "After reviewing access in ChatGPT, you’ll return here."
    assert html =~ "start testing in Amber Orchard."
  end

  test "connection handoff guidance is translated for Spanish and French", %{conn: conn} do
    for {locale, translation} <- [
          {"es", "Después de revisar el acceso en ChatGPT, volverás aquí."},
          {"fr", "Après avoir examiné l’accès dans ChatGPT, vous reviendrez ici."}
        ] do
      assert {:ok, _preference} = Settings.set_ui_locale(locale)
      assert conn |> recycle() |> get("/auth/connect") |> html_response(200) =~ translation
    end
  end

  test "automatic model summary is localized and follows the account list order", %{conn: conn} do
    put_test_credentials()

    on_exit(fn ->
      _ = TokenStore.sign_out(fn _credentials -> :ok end)
    end)

    for {locale, expected, reasoning_note} <- [
          {
            "en",
            "Automatic (first model in account list: Fixture Model (fixture-model))",
            "Storyteller requests low reasoning effort for supported models to help turns resolve faster."
          },
          {
            "es",
            "Automático (primer modelo de la lista de la cuenta: Fixture Model (fixture-model))",
            "Storyteller solicita un nivel bajo de razonamiento en los modelos compatibles para resolver los turnos más rápido."
          },
          {
            "fr",
            "Automatique (premier modèle de la liste du compte : Fixture Model (fixture-model))",
            "Storyteller demande un niveau de raisonnement faible pour les modèles compatibles afin d’accélérer les tours."
          }
        ] do
      assert {:ok, _preference} = Settings.set_ui_locale(locale)
      html = conn |> recycle() |> get("/auth/connect") |> html_response(200)
      assert model_summary_text(html) == expected
      assert html =~ reasoning_note
    end
  end

  test "connected account page links to ChatGPT usage settings", %{conn: conn} do
    put_test_credentials()

    on_exit(fn ->
      _ = TokenStore.sign_out(fn _credentials -> :ok end)
    end)

    html = conn |> get("/auth/connect") |> html_response(200)

    assert html =~ "ChatGPT plan usage is connected."
    assert html =~ "https://chatgpt.com/settings/usage"
    assert html =~ "Manage usage"
    assert html =~ "Reconnect ChatGPT"
    assert html =~ "action=\"/auth/authorize\""
    assert html =~ "Game master model"

    assert model_summary_text(html) ==
             "Automatic (first model in account list: Fixture Model (fixture-model))"

    assert html =~
             "Choose which available account model resolves new turns. Automatic uses the first model returned by the account catalog."

    assert html =~
             "Storyteller requests low reasoning effort for supported models to help turns resolve faster."

    assert html =~ "value=\"automatic\" selected"
  end

  test "preferred model can be saved from the connected catalog and reset to automatic", %{
    conn: conn
  } do
    put_test_credentials()

    on_exit(fn ->
      _ = TokenStore.sign_out(fn _credentials -> :ok end)
    end)

    assert conn |> post("/auth/model", model: "fixture-model") |> redirected_to() ==
             "/auth/connect"

    assert Settings.preferred_gm_model() == "fixture-model"

    conn = recycle(conn)
    html = conn |> get("/auth/connect") |> html_response(200)
    assert html =~ "value=\"fixture-model\" selected"
    assert model_summary_text(html) == "Fixture Model (fixture-model)"

    conn = recycle(conn)

    assert conn |> post("/auth/model", model: "not-listed") |> redirected_to() ==
             "/auth/connect"

    assert Settings.preferred_gm_model() == "fixture-model"

    assert {:ok, _preference} = Settings.set_preferred_gm_model("removed-model")
    assert {:ok, _preference} = Settings.set_ui_locale("en")
    conn = recycle(conn)
    html = conn |> get("/auth/connect") |> html_response(200)
    assert model_summary_text(html) == "Saved model no longer listed: removed-model"

    assert html =~
             "Your saved model is no longer listed. Choose another model or return to Automatic."

    for {locale, expected} <- [
          {"es", "El modelo guardado ya no aparece en la lista: removed-model"},
          {"fr", "Le modèle enregistré n'est plus répertorié : removed-model"}
        ] do
      assert {:ok, _preference} = Settings.set_ui_locale(locale)
      html = conn |> recycle() |> get("/auth/connect") |> html_response(200)
      assert model_summary_text(html) == expected
    end

    conn = recycle(conn)

    assert conn |> post("/auth/model", model: "automatic") |> redirected_to() ==
             "/auth/connect"

    assert is_nil(Settings.preferred_gm_model())
  end

  test "OAuth routes use the required loopback callback path and browser post endpoints" do
    routes = Router.__routes__()

    assert has_route?(routes, :get, "/auth/connect", :connect)
    assert has_route?(routes, :post, "/auth/authorize", :authorize)
    assert has_route?(routes, :post, "/auth/model", :update_model)
    assert has_route?(routes, :get, "/auth/callback", :callback)
    assert has_route?(routes, :post, "/auth/disconnect", :disconnect)
  end

  test "an incomplete callback is safely returned to connection status", %{conn: conn} do
    conn = conn |> get("/auth/callback")

    assert redirected_to(conn) == "/auth/connect"
  end

  defp has_route?(routes, verb, path, action) do
    Enum.any?(routes, fn route ->
      route.verb == verb and route.path == path and route.plug == AuthController and
        route.plug_opts == action
    end)
  end

  defp model_summary_text(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("#gm-model-setting [data-model-selection-summary]")
    |> Floki.text()
    |> String.trim()
  end

  defp put_test_credentials do
    credentials = %Credentials{
      client_id: "test-client",
      subject: "test-account",
      email: "player@example.test",
      host_id: TokenStore.host_id(),
      access_token: "test-access-token",
      refresh_token: "test-refresh-token",
      expires_at: System.system_time(:second) + 3_600,
      scopes: ["openid", "chatgpt.tokens.use.direct"]
    }

    assert :ok = TokenStore.put_credentials(credentials)
  end
end
