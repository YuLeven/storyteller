defmodule Storyteller.Auth.OIDCTest do
  use ExUnit.Case, async: true

  alias Storyteller.Auth.OIDC

  @now 1_800_000_000
  @expected %{
    client_id: "fixture-issued-client",
    nonce: "fixture-nonce",
    now: @now
  }

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

  test "requires a matching authorized party for multiple audiences" do
    claims = valid_claims(%{"aud" => ["fixture-issued-client", "another-client"]})
    claims_with_matching_authorized_party = Map.put(claims, "azp", "fixture-issued-client")

    assert {:error, :invalid_id_token} = OIDC.validate_verified_claims(claims, @expected)

    assert :ok =
             OIDC.validate_verified_claims(claims_with_matching_authorized_party, @expected)
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
end
