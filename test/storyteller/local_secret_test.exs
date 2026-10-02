defmodule Storyteller.LocalSecretTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Storyteller.LocalSecret

  test "creates a random key with private directory and file permissions and reuses it" do
    path = secret_path()
    on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)

    secret = LocalSecret.get_or_create!(path)

    assert byte_size(secret) >= 64
    assert LocalSecret.get_or_create!(path) == secret
    assert {:ok, directory_stat} = File.stat(Path.dirname(path))
    assert band(directory_stat.mode, 0o777) == 0o700
    assert {:ok, file_stat} = File.stat(path)
    assert band(file_stat.mode, 0o777) == 0o600
  end

  test "repairs permissions on an existing local key without rotating it" do
    path = secret_path()
    directory = Path.dirname(path)
    File.mkdir_p!(directory)
    File.chmod!(directory, 0o755)

    secret = Base.url_encode64(:crypto.strong_rand_bytes(64), padding: false)
    File.write!(path, secret)
    File.chmod!(path, 0o644)

    on_exit(fn -> File.rm_rf!(directory) end)

    assert LocalSecret.get_or_create!(path) == secret
    assert {:ok, directory_stat} = File.stat(directory)
    assert band(directory_stat.mode, 0o777) == 0o700
    assert {:ok, file_stat} = File.stat(path)
    assert band(file_stat.mode, 0o777) == 0o600
  end

  test "rejects a malformed existing key instead of silently rotating it" do
    path = secret_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, " " <> String.duplicate("a", 63))

    on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)

    assert_raise ArgumentError, "local secret file is invalid", fn ->
      LocalSecret.get_or_create!(path)
    end
  end

  defp secret_path do
    Path.join(
      System.tmp_dir!(),
      "storyteller-local-secret-#{Ecto.UUID.generate()}/dev_secret_key_base"
    )
  end
end
