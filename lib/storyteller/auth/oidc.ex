defmodule Storyteller.Auth.OIDC do
  @moduledoc "Strict OpenID Connect ID-token verification for Sign in with ChatGPT."

  alias Storyteller.Auth.HTTP

  @issuer "https://auth.openai.com"
  @discovery_url @issuer <> "/.well-known/openid-configuration"
  @allowed_algorithms ["RS256", "ES256"]
  @clock_skew_seconds 60

  @doc "Returns the trusted OpenID Provider metadata used by this flow."
  def metadata(http \\ nil) do
    with {:ok, metadata} <- discovery(http),
         true <- trusted_metadata_url?(metadata["authorization_endpoint"]),
         true <- trusted_metadata_url?(metadata["token_endpoint"]),
         true <-
           is_nil(metadata["revocation_endpoint"]) or
             trusted_metadata_url?(metadata["revocation_endpoint"]) do
      {:ok, metadata}
    else
      _ -> {:error, :identity_provider_unavailable}
    end
  end

  def verify_id_token(id_token, expected, http \\ nil)

  def verify_id_token(id_token, expected, http)
      when is_binary(id_token) and is_map(expected) do
    with {:ok, discovery} <- discovery(http),
         {:ok, jwks} <- fetch_jwks(discovery, http),
         {:ok, header} <- token_header(id_token),
         {:ok, jwk} <- signing_key(header, jwks),
         {:ok, claims} <- verify_signature(id_token, header, jwk),
         :ok <- validate_verified_claims(claims, expected) do
      {:ok, claims}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_id_token}
    end
  rescue
    _ -> {:error, :invalid_id_token}
  catch
    _, _ -> {:error, :invalid_id_token}
  end

  def verify_id_token(_, _, _), do: {:error, :invalid_id_token}

  defp discovery(http) do
    with {:ok, response} <- HTTP.request(:get, @discovery_url, [], http),
         200 <- response_status(response),
         {:ok, metadata} <- HTTP.decode_json(response_body(response)),
         @issuer <- metadata["issuer"],
         jwks_uri when is_binary(jwks_uri) <- metadata["jwks_uri"],
         true <- trusted_metadata_url?(jwks_uri) do
      {:ok, metadata}
    else
      _ -> {:error, :identity_provider_unavailable}
    end
  end

  defp fetch_jwks(discovery, http) do
    with {:ok, response} <- HTTP.request(:get, discovery["jwks_uri"], [], http),
         200 <- response_status(response),
         {:ok, %{"keys" => keys}} <- HTTP.decode_json(response_body(response)),
         true <- is_list(keys) do
      {:ok, keys}
    else
      _ -> {:error, :identity_provider_unavailable}
    end
  end

  defp token_header(token) do
    jwt = Module.concat(["JOSE", "JWT"])
    jws = Module.concat(["JOSE", "JWS"])
    protected = apply(jwt, :peek_protected, [token])
    {_, header} = apply(jws, :to_map, [protected])

    if is_map(header) and header["alg"] in @allowed_algorithms and is_binary(header["kid"]) do
      {:ok, header}
    else
      {:error, :invalid_id_token}
    end
  end

  defp signing_key(header, keys) do
    case Enum.find(keys, &matching_key?(&1, header)) do
      key when is_map(key) -> {:ok, apply(Module.concat(["JOSE", "JWK"]), :from, [key])}
      _ -> {:error, :invalid_id_token}
    end
  end

  defp matching_key?(key, header) when is_map(key) do
    key["kid"] == header["kid"] and
      key["use"] in [nil, "sig"] and
      key["alg"] in [nil, header["alg"]] and
      algorithm_matches_key?(header["alg"], key)
  end

  defp matching_key?(_, _), do: false

  defp algorithm_matches_key?("RS256", %{"kty" => "RSA"}), do: true

  defp algorithm_matches_key?("ES256", %{"kty" => "EC", "crv" => "P-256"}), do: true

  defp algorithm_matches_key?(_, _), do: false

  defp verify_signature(token, header, jwk) do
    jwt = Module.concat(["JOSE", "JWT"])

    case apply(jwt, :verify_strict, [jwk, [header["alg"]], token]) do
      {true, verified_jwt, _jws} ->
        {_, claims} = apply(jwt, :to_map, [verified_jwt])
        if is_map(claims), do: {:ok, claims}, else: {:error, :invalid_id_token}

      _ ->
        {:error, :invalid_id_token}
    end
  end

  def validate_verified_claims(claims, expected)
      when is_map(claims) and is_map(expected) do
    now = Map.get(expected, :now, System.system_time(:second))
    expected_audience = Map.get(expected, :client_id)
    expected_nonce = Map.get(expected, :nonce)

    cond do
      not is_integer(now) -> {:error, :invalid_id_token}
      not is_binary(expected_audience) or expected_audience == "" -> {:error, :invalid_id_token}
      not is_binary(expected_nonce) or expected_nonce == "" -> {:error, :invalid_id_token}
      claims["iss"] != @issuer -> {:error, :invalid_id_token}
      not audience_matches?(claims, expected_audience) -> {:error, :invalid_id_token}
      not is_integer(claims["exp"]) or claims["exp"] <= now -> {:error, :invalid_id_token}
      not is_integer(claims["iat"]) or claims["iat"] < 0 -> {:error, :invalid_id_token}
      claims["iat"] > now + @clock_skew_seconds -> {:error, :invalid_id_token}
      claims["exp"] <= claims["iat"] -> {:error, :invalid_id_token}
      not is_binary(claims["sub"]) or claims["sub"] == "" -> {:error, :invalid_id_token}
      claims["nonce"] != expected_nonce -> {:error, :invalid_id_token}
      true -> :ok
    end
  end

  def validate_verified_claims(_, _), do: {:error, :invalid_id_token}

  defp audience_matches?(%{"aud" => audience} = claims, expected) when is_binary(audience) do
    audience == expected and authorized_party_matches?(claims, expected)
  end

  defp audience_matches?(%{"aud" => audiences} = claims, expected) when is_list(audiences) do
    expected in audiences and
      (length(audiences) == 1 or claims["azp"] == expected) and
      authorized_party_matches?(claims, expected)
  end

  defp audience_matches?(_, _), do: false

  defp authorized_party_matches?(claims, expected) do
    is_nil(claims["azp"]) or claims["azp"] == expected
  end

  defp trusted_metadata_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: "auth.openai.com", userinfo: nil, port: port} ->
        port in [nil, 443]

      _ ->
        false
    end
  end

  defp trusted_metadata_url?(_), do: false

  defp response_status(%{status: status}) when is_integer(status), do: status
  defp response_status(%{"status" => status}) when is_integer(status), do: status
  defp response_status(_), do: nil

  defp response_body(%{body: body}), do: body
  defp response_body(%{"body" => body}), do: body
  defp response_body(_), do: nil
end
