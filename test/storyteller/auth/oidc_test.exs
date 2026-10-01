defmodule Storyteller.Auth.OIDCTest do
  use ExUnit.Case, async: true

  alias Storyteller.Auth.OIDC

  @now 1_800_000_000
  @expected %{
    client_id: "fixture-issued-client",
    nonce: "fixture-nonce",
    now: @now
  }

  @signing_key_id "local-oidc-test-key"

  test "accepts verified claims with an integer issued-at within clock skew" do
    claims = valid_claims(%{"iat" => @now + 60})

    assert :ok = OIDC.validate_verified_claims(claims, @expected)
  end

  test "rejects verified claims with a missing issued-at" do
    claims = valid_claims() |> Map.delete("iat")

    assert {:error, :invalid_id_token} =
             OIDC.validate_verified_claims(claims, @expected)
  end

  test "rejects verified claims with a non-integer issued-at" do
    claims = valid_claims(%{"iat" => Integer.to_string(@now)})

    assert {:error, :invalid_id_token} =
             OIDC.validate_verified_claims(claims, @expected)
  end

  test "rejects verified claims issued beyond the allowed future clock skew" do
    claims = valid_claims(%{"iat" => @now + 61})

    assert {:error, :invalid_id_token} =
             OIDC.validate_verified_claims(claims, @expected)
  end

  test "rejects a single-audience list with a mismatched authorized party" do
    claims = valid_claims(%{"aud" => ["fixture-issued-client"], "azp" => "other-client"})

    assert {:error, :invalid_id_token} =
             OIDC.validate_verified_claims(claims, @expected)
  end

  test "rejects a scalar audience with a mismatched authorized party" do
    claims = valid_claims(%{"azp" => "other-client"})

    assert {:error, :invalid_id_token} =
             OIDC.validate_verified_claims(claims, @expected)
  end

  test "accepts a single-audience list when the authorized party is absent or matches" do
    claims_without_authorized_party = valid_claims(%{"aud" => ["fixture-issued-client"]})

    claims_with_matching_authorized_party =
      valid_claims(%{"aud" => ["fixture-issued-client"], "azp" => "fixture-issued-client"})

    assert :ok = OIDC.validate_verified_claims(claims_without_authorized_party, @expected)

    assert :ok =
             OIDC.validate_verified_claims(claims_with_matching_authorized_party, @expected)
  end

  test "verifies an RS256 ID token against the discovered JWKS before accepting its claims",
       context do
    token = signed_id_token(context.signing_key, %{})

    assert {:ok, claims} = OIDC.verify_id_token(token, @expected, local_http(context.jwks_key))
    assert claims["sub"] == "fixture-account-subject"
  end

  test "rejects an ID token with a signature from a different key", context do
    token = signed_id_token(context.other_signing_key, %{})

    assert {:error, :invalid_id_token} =
             OIDC.verify_id_token(token, @expected, local_http(context.jwks_key))
  end

  test "rejects a correctly signed ID token with the wrong audience", context do
    token = signed_id_token(context.signing_key, %{"aud" => "another-client"})

    assert {:error, :invalid_id_token} =
             OIDC.verify_id_token(token, @expected, local_http(context.jwks_key))
  end

  test "rejects a correctly signed ID token with the wrong issuer", context do
    token = signed_id_token(context.signing_key, %{"iss" => "https://issuer.example.invalid"})

    assert {:error, :invalid_id_token} =
             OIDC.verify_id_token(token, @expected, local_http(context.jwks_key))
  end

  test "rejects a correctly signed ID token with the wrong nonce", context do
    token = signed_id_token(context.signing_key, %{"nonce" => "different-fixture-nonce"})

    assert {:error, :invalid_id_token} =
             OIDC.verify_id_token(token, @expected, local_http(context.jwks_key))
  end

  setup_all do
    signing_key = fixture_signing_key()
    other_signing_key = fixture_signing_key()

    jwks_key =
      signing_key
      |> JOSE.JWK.to_public()
      |> JOSE.JWK.to_map()
      |> elem(1)

    {:ok, signing_key: signing_key, other_signing_key: other_signing_key, jwks_key: jwks_key}
  end

  test "requires a matching authorized party for multiple audiences" do
    claims = valid_claims(%{"aud" => ["fixture-issued-client", "another-client"]})
    claims_with_matching_authorized_party = Map.put(claims, "azp", "fixture-issued-client")

    assert {:error, :invalid_id_token} = OIDC.validate_verified_claims(claims, @expected)

    assert :ok =
             OIDC.validate_verified_claims(claims_with_matching_authorized_party, @expected)
  end

  test "loads auth metadata only from the trusted OpenAI issuer and endpoints" do
    http = fn :get, "https://auth.openai.com/.well-known/openid-configuration", _options ->
      %{status: 200, body: Jason.encode!(provider_metadata())}
    end

    assert {:ok, metadata} = OIDC.metadata(http)
    assert metadata["authorization_endpoint"] == "https://auth.openai.com/api/accounts/authorize"
    assert metadata["token_endpoint"] == "https://auth.openai.com/api/accounts/oauth/token"
  end

  test "rejects an untrusted token or revocation endpoint from discovery metadata" do
    http = fn :get, "https://auth.openai.com/.well-known/openid-configuration", _options ->
      metadata = Map.put(provider_metadata(), "token_endpoint", "https://example.invalid/token")
      %{status: 200, body: Jason.encode!(metadata)}
    end

    assert {:error, :identity_provider_unavailable} = OIDC.metadata(http)
  end

  defp valid_claims(overrides \\ %{}) do
    Map.merge(
      %{
        "iss" => "https://auth.openai.com",
        "aud" => "fixture-issued-client",
        "sub" => "fixture-account-subject",
        "nonce" => "fixture-nonce",
        "iat" => @now,
        "exp" => @now + 300
      },
      overrides
    )
  end

  defp provider_metadata do
    %{
      "issuer" => "https://auth.openai.com",
      "jwks_uri" => "https://auth.openai.com/.well-known/jwks.json",
      "authorization_endpoint" => "https://auth.openai.com/api/accounts/authorize",
      "token_endpoint" => "https://auth.openai.com/api/accounts/oauth/token",
      "revocation_endpoint" => "https://auth.openai.com/api/accounts/oauth/revoke"
    }
  end

  defp fixture_signing_key do
    JOSE.JWK.generate_key({:rsa, 2048})
    |> JOSE.JWK.merge(%{
      "kid" => @signing_key_id,
      "alg" => "RS256",
      "use" => "sig"
    })
  end

  defp signed_id_token(signing_key, overrides) do
    claims =
      Map.merge(
        %{
          "iss" => "https://auth.openai.com",
          "aud" => "fixture-issued-client",
          "sub" => "fixture-account-subject",
          "nonce" => "fixture-nonce",
          "iat" => @now,
          "exp" => @now + 300
        },
        overrides
      )

    signing_key
    |> JOSE.JWT.sign(%{"alg" => "RS256", "kid" => @signing_key_id}, claims)
    |> JOSE.JWS.compact()
    |> elem(1)
  end

  defp local_http(jwks_key) do
    fn :get, url, _options ->
      case url do
        "https://auth.openai.com/.well-known/openid-configuration" ->
          %{status: 200, body: Jason.encode!(provider_metadata())}

        "https://auth.openai.com/.well-known/jwks.json" ->
          %{status: 200, body: Jason.encode!(%{"keys" => [jwks_key]})}

        _unexpected_url ->
          {:error, :network_error}
      end
    end
  end
end
