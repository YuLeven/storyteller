defmodule Storyteller.Auth.OAuthTest do
  use ExUnit.Case, async: true

  alias Storyteller.Auth.{Credentials, OAuth, TokenStore}

  setup do
    directory = Path.join(System.tmp_dir!(), "storyteller-oauth-test-#{Ecto.UUID.generate()}")
    path = Path.join(directory, "credentials.json")
    on_exit(fn -> File.rm_rf(directory) end)

    store = start_supervised!({TokenStore, path: path, name: nil})

    %{store: store}
  end

  test "first sign-in uses the dynamic client, PKCE, state, nonce, and only persists verified plan scopes",
       context do
    test_pid = self()
    http = token_http(test_pid, token_response())
    opts = [store: context.store, http: http, oidc: FakeOIDC]

    assert {:ok, authorization_url} = OAuth.start_authorization(opts)
    query = query_params(authorization_url)

    assert query["client_id"] == "dynamic_agent_client"
    assert query["agent_name_hint"] == "Storyteller"
    assert query["ext_agent_host_id"] == TokenStore.host_id(context.store)
    assert query["response_type"] == "code"
    assert query["redirect_uri"] == "http://127.0.0.1:4000/auth/callback"
    assert query["code_challenge_method"] == "S256"
    assert query["scope"] =~ "chatgpt.tokens.use.direct"
    assert query["resource"] == "https://api.openai.com/v1"
    refute Map.has_key?(query, "client_secret")

    claims = claims(query["nonce"], "fixture-account-subject", "fixture-issued-client")
    Process.put({FakeOIDC, :claims}, claims)

    assert {:ok, %{email: "fixture@example.invalid"}} =
             OAuth.callback(
               %{
                 "state" => query["state"],
                 "code" => "fixture-authorization-code",
                 "client_id" => "fixture-issued-client"
               },
               opts
             )

    assert_receive {:token_request, options}
    form = Keyword.fetch!(options, :form)
    assert Keyword.fetch!(form, :grant_type) == "authorization_code"
    assert Keyword.fetch!(form, :client_id) == "fixture-issued-client"
    assert Keyword.fetch!(form, :code) == "fixture-authorization-code"
    assert Keyword.fetch!(form, :redirect_uri) == query["redirect_uri"]
    assert Keyword.fetch!(form, :resource) == "https://api.openai.com/v1"

    verifier = Keyword.fetch!(form, :code_verifier)
    challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)
    assert challenge == query["code_challenge"]

    assert %Credentials{} = credentials = TokenStore.credentials(context.store)
    assert credentials.client_id == "fixture-issued-client"
    assert credentials.subject == "fixture-account-subject"
    assert credentials.host_id == TokenStore.host_id(context.store)
    assert Credentials.plan_usage_enabled?(credentials)
    assert OAuth.status(store: context.store).connected?

    assert {:error, :invalid_or_expired_state} =
             OAuth.callback(
               %{
                 "state" => query["state"],
                 "code" => "fixture-replay",
                 "client_id" => "fixture-issued-client"
               },
               opts
             )
  end

  test "authorization rejects a non-loopback or altered callback URI", context do
    opts = [
      store: context.store,
      oidc: FakeOIDC,
      callback_uri: "http://localhost:4000/auth/callback"
    ]

    assert {:error, :invalid_callback_uri} = OAuth.start_authorization(opts)
  end

  test "a failed reauthorization for another account leaves the active account intact", context do
    original =
      credentials_for(context.store, subject: "active-subject", email: "active@example.invalid")

    assert :ok = TokenStore.put_credentials(original, context.store)

    opts = [store: context.store, http: token_http(self(), token_response()), oidc: FakeOIDC]
    assert {:ok, authorization_url} = OAuth.start_authorization(opts)
    query = query_params(authorization_url)

    Process.put(
      {FakeOIDC, :claims},
      claims(query["nonce"], "different-subject", original.client_id)
    )

    assert {:error, :account_mismatch} =
             OAuth.callback(
               %{
                 "state" => query["state"],
                 "code" => "fixture-code",
                 "client_id" => original.client_id
               },
               opts
             )

    assert TokenStore.credentials(context.store) == original
    assert OAuth.status(store: context.store).connected?
  end

  test "callback client mismatch is rejected without replacing credentials", context do
    original = credentials_for(context.store)
    assert :ok = TokenStore.put_credentials(original, context.store)
    opts = [store: context.store, http: token_http(self(), token_response()), oidc: FakeOIDC]

    assert {:ok, authorization_url} = OAuth.start_authorization(opts)
    query = query_params(authorization_url)

    assert {:error, :client_id_mismatch} =
             OAuth.callback(
               %{
                 "state" => query["state"],
                 "code" => "fixture-code",
                 "client_id" => "different-client"
               },
               opts
             )

    assert TokenStore.credentials(context.store) == original
  end

  test "missing plan usage scope is rejected without replacing credentials", context do
    original = credentials_for(context.store)
    assert :ok = TokenStore.put_credentials(original, context.store)
    response = Map.put(token_response(), "scopes", ["openid", "profile", "offline_access"])
    opts = [store: context.store, http: token_http(self(), response), oidc: FakeOIDC]

    assert {:ok, authorization_url} = OAuth.start_authorization(opts)
    query = query_params(authorization_url)
    Process.put({FakeOIDC, :claims}, claims(query["nonce"], original.subject, original.client_id))

    assert {:error, :account_ineligible} =
             OAuth.callback(
               %{
                 "state" => query["state"],
                 "code" => "fixture-code",
                 "client_id" => original.client_id
               },
               opts
             )

    assert TokenStore.credentials(context.store) == original
  end

  test "refresh rotates both tokens and a transient refresh failure preserves the active account",
       context do
    original = credentials_for(context.store, expires_at: System.system_time(:second) - 1)
    assert :ok = TokenStore.put_credentials(original, context.store)

    refresh_http = fn method, url, options ->
      if method == :post and url == FakeOIDC.token_endpoint() do
        assert Keyword.fetch!(Keyword.fetch!(options, :form), :grant_type) == "refresh_token"
        form = Keyword.fetch!(options, :form)
        assert Keyword.fetch!(form, :client_id) == original.client_id
        assert Keyword.fetch!(form, :refresh_token) == original.refresh_token
        assert Keyword.fetch!(form, :resource) == "https://api.openai.com/v1"

        %{
          status: 200,
          body:
            Jason.encode!(%{
              "access_token" => "fixture-access-after-refresh",
              "refresh_token" => "fixture-refresh-after-refresh",
              "expires_in" => 3_600
            })
        }
      else
        {:error, :unexpected_request}
      end
    end

    opts = [store: context.store, http: refresh_http, oidc: FakeOIDC]

    assert {:ok, "fixture-access-after-refresh"} = OAuth.access_token(opts)
    rotated = TokenStore.credentials(context.store)
    assert rotated.refresh_token == "fixture-refresh-after-refresh"
    assert rotated.access_token == "fixture-access-after-refresh"

    expired = %{rotated | expires_at: System.system_time(:second) - 1}
    assert :ok = TokenStore.put_credentials(expired, context.store)
    failing_http = fn _method, _url, _options -> {:error, :timeout} end

    assert {:error, :temporary_auth_error} =
             OAuth.access_token(Keyword.put(opts, :http, failing_http))

    assert TokenStore.credentials(context.store) == expired
  end

  test "disconnect revokes the refresh token and clears local credentials", context do
    credentials = credentials_for(context.store)
    assert :ok = TokenStore.put_credentials(credentials, context.store)

    test_pid = self()

    revoke_http = fn method, url, options ->
      if method == :post and url == FakeOIDC.revocation_endpoint() do
        send(test_pid, {:revoke_request, options})
        %{status: 200, body: ""}
      else
        {:error, :unexpected_request}
      end
    end

    assert {:ok, :revoked} =
             OAuth.disconnect(store: context.store, http: revoke_http, oidc: FakeOIDC)

    assert_receive {:revoke_request, options}
    form = Keyword.fetch!(options, :form)
    assert Keyword.fetch!(form, :token) == credentials.refresh_token
    assert Keyword.fetch!(form, :token_type_hint) == "refresh_token"
    assert Keyword.fetch!(form, :client_id) == credentials.client_id
    signed_out = TokenStore.credentials(context.store)
    assert signed_out.access_token == nil
    assert signed_out.refresh_token == nil
    assert OAuth.status(store: context.store).connected? == false
    assert OAuth.status(store: context.store).registered?
  end

  defp credentials_for(store, overrides \\ []) do
    fields =
      Keyword.merge(
        [
          client_id: "fixture-issued-client",
          subject: "fixture-account-subject",
          email: "fixture@example.invalid",
          host_id: TokenStore.host_id(store),
          id_token: "fixture-id-token",
          access_token: "fixture-access-token",
          refresh_token: "fixture-refresh-token",
          expires_at: System.system_time(:second) + 3_600,
          scopes: [
            "openid",
            "profile",
            "email",
            "offline_access",
            "resource.invoke",
            "chatgpt.tokens.use.direct"
          ]
        ],
        overrides
      )

    struct!(Credentials, fields)
  end

  defp token_response do
    %{
      "access_token" => "fixture-access-token",
      "refresh_token" => "fixture-refresh-token",
      "id_token" => "fixture-id-token",
      "token_type" => "Bearer",
      "expires_in" => 3_600,
      "scopes" => [
        "openid",
        "profile",
        "email",
        "offline_access",
        "resource.invoke",
        "chatgpt.tokens.use.direct"
      ]
    }
  end

  defp token_http(test_pid, body) do
    fn :post, url, options ->
      if url == FakeOIDC.token_endpoint() do
        send(test_pid, {:token_request, options})
        %{status: 200, body: Jason.encode!(body)}
      else
        {:error, :unexpected_request}
      end
    end
  end

  defp query_params(url) do
    url
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.query_decoder()
    |> Map.new()
  end

  defp claims(nonce, subject, client_id) do
    now = System.system_time(:second)

    %{
      "iss" => "https://auth.openai.com",
      "aud" => client_id,
      "sub" => subject,
      "email" => "fixture@example.invalid",
      "nonce" => nonce,
      "iat" => now,
      "exp" => now + 300
    }
  end

  defmodule FakeOIDC do
    def authorization_endpoint, do: "https://auth.openai.com/api/accounts/authorize"
    def token_endpoint, do: "https://auth.openai.com/api/accounts/oauth/token"
    def revocation_endpoint, do: "https://auth.openai.com/api/accounts/oauth/revoke"

    def metadata(_http) do
      {:ok,
       %{
         "authorization_endpoint" => authorization_endpoint(),
         "token_endpoint" => token_endpoint(),
         "revocation_endpoint" => revocation_endpoint()
       }}
    end

    def verify_id_token("fixture-id-token", expected, _http) do
      claims = Process.get({__MODULE__, :claims})

      if is_map(claims) and claims["aud"] == expected.client_id and
           claims["nonce"] == expected.nonce and claims["iss"] == "https://auth.openai.com" and
           is_integer(claims["iat"]) and claims["exp"] > System.system_time(:second) do
        {:ok, claims}
      else
        {:error, :invalid_id_token}
      end
    end

    def verify_id_token(_, _, _), do: {:error, :invalid_id_token}
  end
end
