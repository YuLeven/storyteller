defmodule Storyteller.Auth.Credentials do
  @moduledoc "Server-side ChatGPT plan OAuth credentials and account metadata."

  @enforce_keys [:client_id, :subject, :host_id]
  defstruct [
    :client_id,
    :subject,
    :email,
    :host_id,
    :id_token,
    :access_token,
    :refresh_token,
    :expires_at,
    scopes: []
  ]

  @type t :: %__MODULE__{
          client_id: String.t(),
          subject: String.t(),
          email: String.t() | nil,
          host_id: String.t(),
          id_token: String.t() | nil,
          access_token: String.t() | nil,
          refresh_token: String.t() | nil,
          expires_at: integer() | nil,
          scopes: [String.t()]
        }

  @plan_scope "chatgpt.tokens.use.direct"

  def plan_usage_enabled?(%__MODULE__{} = credentials) do
    @plan_scope in credentials.scopes and is_binary(credentials.access_token) and
      is_binary(credentials.refresh_token)
  end

  def clear_tokens(%__MODULE__{} = credentials) do
    %{
      credentials
      | id_token: nil,
        access_token: nil,
        refresh_token: nil,
        expires_at: nil,
        scopes: []
    }
  end

  def persisted_fields(%__MODULE__{} = credentials) do
    %{
      "client_id" => credentials.client_id,
      "subject" => credentials.subject,
      "email" => credentials.email,
      "host_id" => credentials.host_id,
      "id_token" => credentials.id_token,
      "access_token" => credentials.access_token,
      "refresh_token" => credentials.refresh_token,
      "expires_at" => credentials.expires_at,
      "scopes" => credentials.scopes
    }
  end

  def from_persisted(map) when is_map(map) do
    with client_id when is_binary(client_id) <- map["client_id"],
         subject when is_binary(subject) <- map["subject"],
         host_id when is_binary(host_id) <- map["host_id"],
         scopes when is_list(scopes) <- map["scopes"] || [],
         true <- Enum.all?(scopes, &is_binary/1),
         true <- optional_binary?(map["email"]),
         true <- optional_binary?(map["id_token"]),
         true <- optional_binary?(map["access_token"]),
         true <- optional_binary?(map["refresh_token"]),
         true <- is_nil(map["expires_at"]) or is_integer(map["expires_at"]) do
      {:ok,
       %__MODULE__{
         client_id: client_id,
         subject: subject,
         email: map["email"],
         host_id: host_id,
         id_token: map["id_token"],
         access_token: map["access_token"],
         refresh_token: map["refresh_token"],
         expires_at: map["expires_at"],
         scopes: scopes
       }}
    else
      _ -> {:error, :invalid_credential_record}
    end
  end

  def from_persisted(_), do: {:error, :invalid_credential_record}

  defp optional_binary?(nil), do: true
  defp optional_binary?(value), do: is_binary(value)
end

defimpl Inspect, for: Storyteller.Auth.Credentials do
  import Inspect.Algebra

  def inspect(_credentials, _opts) do
    concat(["#Storyteller.Auth.Credentials<", "redacted", ">"])
  end
end
