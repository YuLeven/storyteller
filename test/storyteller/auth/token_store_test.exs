defmodule Storyteller.Auth.TokenStoreTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Storyteller.Auth.{Credentials, TokenStore}

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "storyteller-auth-#{Ecto.UUID.generate()}"
      )

    name = String.to_atom("storyteller_auth_store_#{Ecto.UUID.generate()}")
    path = Path.join(directory, "credentials.json")

    on_exit(fn -> File.rm_rf(directory) end)

    %{directory: directory, name: name, path: path}
  end

  test "startup corrects broad modes on an existing credential file and directory", context do
    server = start_store(context)
    original_host_id = TokenStore.host_id(server)

    assert :ok = File.chmod(context.directory, 0o755)
    assert :ok = File.chmod(context.path, 0o644)
    assert :ok = stop_supervised(context.name)

    restarted = start_store(context)

    assert TokenStore.host_id(restarted) == original_host_id
    assert mode(context.directory) == 0o700
    assert mode(context.path) == 0o600
  end

  test "startup rejects a symlink at the credential file path", context do
    _server = start_store(context)
    assert :ok = stop_supervised(context.name)

    assert :ok = File.rm(context.path)
    target = Path.join(context.directory, "other-file.json")
    assert :ok = File.write(target, ~s({"fixture":"not credentials"}))
    assert :ok = File.ln_s(target, context.path)

    assert {:error, :credential_store_unreadable} =
             TokenStore.start_link(path: context.path, name: context.name)
  end

  test "startup rejects a non-regular credential file path", context do
    _server = start_store(context)
    assert :ok = stop_supervised(context.name)

    assert :ok = File.rm(context.path)
    assert :ok = File.mkdir(context.path)

    assert {:error, :credential_store_unreadable} =
             TokenStore.start_link(path: context.path, name: context.name)
  end

  test "a rotated refresh token survives a store restart without exposing credential inspection",
       context do
    server = start_store(context)
    credentials = credentials_for(server, expires_at: System.system_time(:second) - 1)
    assert :ok = TokenStore.put_credentials(credentials, server)

    refresh = fn current ->
      if current.refresh_token == "fixture-refresh-before-rotation" do
        {:ok,
         %{
           current
           | access_token: "fixture-access-after-rotation",
             refresh_token: "fixture-refresh-after-rotation",
             expires_at: System.system_time(:second) + 3_600
         }}
      else
        {:error, :unexpected_refresh_input}
      end
    end

    assert {:ok, "fixture-access-after-rotation"} =
             TokenStore.access_token(refresh, server)

    assert :ok = stop_supervised(context.name)
    restarted = start_store(context)
    persisted = TokenStore.credentials(restarted)

    assert persisted.access_token == "fixture-access-after-rotation"
    assert persisted.refresh_token == "fixture-refresh-after-rotation"

    assert {:ok, "fixture-access-after-rotation"} =
             TokenStore.access_token(
               fn _ -> flunk("a fresh access token should not refresh") end,
               restarted
             )

    assert inspect(persisted) == "#Storyteller.Auth.Credentials<redacted>"
    refute inspect(persisted) =~ "fixture-refresh-after-rotation"
  end

  test "sign-out clears local tokens even when remote revocation is unavailable and keeps registration",
       context do
    server = start_store(context)
    credentials = credentials_for(server)
    assert :ok = TokenStore.put_credentials(credentials, server)

    assert {:error, :revocation_unconfirmed} =
             TokenStore.sign_out(fn _credentials -> {:error, :offline} end, server)

    signed_out = TokenStore.credentials(server)
    assert signed_out.id_token == nil
    assert signed_out.access_token == nil
    assert signed_out.refresh_token == nil
    assert signed_out.expires_at == nil
    assert signed_out.scopes == []

    assert %{
             client_id: "fixture-issued-client",
             subject: "fixture-account-subject",
             host_id: host_id
           } = TokenStore.registration(server)

    assert host_id == TokenStore.host_id(server)
    assert :ok = stop_supervised(context.name)

    restarted = start_store(context)
    assert TokenStore.registration(restarted).client_id == "fixture-issued-client"

    persisted_json = File.read!(context.path)
    refute persisted_json =~ "fixture-id-token"
    refute persisted_json =~ "fixture-access-token"
    refute persisted_json =~ "fixture-refresh-token"
  end

  defp start_store(%{name: name, path: path}) do
    start_supervised!({TokenStore, path: path, name: name}, id: name)
  end

  defp credentials_for(server, overrides \\ []) do
    fields =
      Keyword.merge(
        [
          client_id: "fixture-issued-client",
          subject: "fixture-account-subject",
          email: "fixture@example.invalid",
          host_id: TokenStore.host_id(server),
          id_token: "fixture-id-token",
          access_token: "fixture-access-token",
          refresh_token: "fixture-refresh-before-rotation",
          expires_at: System.system_time(:second) + 3_600,
          scopes: ["chatgpt.tokens.use.direct", "offline_access"]
        ],
        overrides
      )

    struct!(Credentials, fields)
  end

  defp mode(path) do
    {:ok, stat} = File.stat(path)
    band(stat.mode, 0o777)
  end
end
