defmodule StorytellerWeb.PhoenixLoggerFilterTest do
  use ExUnit.Case, async: true

  test "Phoenix filters OAuth, CSRF, and credential parameters from logs" do
    params = %{
      "_csrf_token" => "csrf-value",
      "code" => "authorization-code",
      "state" => "oauth-state",
      "client_secret" => "client-secret",
      "password" => "account-password",
      "authorization" => "bearer-value",
      "access_token" => "access-value",
      "refresh_token" => "refresh-value",
      "api_key" => "api-key-value",
      "api-key" => "dashed-api-key-value",
      "oauth" => %{"client_secret" => "nested-client-secret", "label" => "plan"},
      "page" => "2"
    }

    filtered = Phoenix.Logger.filter_values(params)

    for key <- [
          "_csrf_token",
          "code",
          "state",
          "client_secret",
          "password",
          "authorization",
          "access_token",
          "refresh_token",
          "api_key",
          "api-key"
        ] do
      assert filtered[key] == "[FILTERED]"
    end

    assert filtered["oauth"]["client_secret"] == "[FILTERED]"
    assert filtered["oauth"]["label"] == "plan"
    assert filtered["page"] == "2"
    refute inspect(filtered) =~ "csrf-value"
    refute inspect(filtered) =~ "authorization-code"
    refute inspect(filtered) =~ "client-secret"
    refute inspect(filtered) =~ "access-value"
    refute inspect(filtered) =~ "dashed-api-key-value"
  end
end
