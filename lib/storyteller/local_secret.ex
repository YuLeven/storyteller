defmodule Storyteller.LocalSecret do
  @moduledoc """
  Creates a stable development cookie-signing key in the local user's private data directory.

  This keeps the development key out of source control while preserving browser
  sessions across local server restarts. Production uses `SECRET_KEY_BASE`.
  """

  import Bitwise

  @minimum_secret_bytes 64

  def get_or_create!(path) when is_binary(path) do
    path = Path.expand(path)
    directory = Path.dirname(path)

    ensure_secure_directory!(directory)

    case File.lstat(path) do
      {:ok, %{type: :regular}} -> read_existing!(path)
      {:error, :enoent} -> create_or_read!(path)
      {:ok, _other_type} -> raise ArgumentError, "local secret must be a regular file"
      {:error, reason} -> raise File.Error, reason: reason, action: "read file", path: path
    end
  end

  defp create_or_read!(path) do
    secret = Base.url_encode64(:crypto.strong_rand_bytes(@minimum_secret_bytes), padding: false)

    case File.write(path, secret, [:binary, :exclusive, :sync]) do
      :ok ->
        secure_file!(path)
        secret

      {:error, :eexist} ->
        read_existing!(path)

      {:error, reason} ->
        raise File.Error, reason: reason, action: "create file", path: path
    end
  end

  defp read_existing!(path) do
    secure_file!(path)

    case File.read(path) do
      {:ok, secret} -> normalize_secret!(secret)
      {:error, reason} -> raise File.Error, reason: reason, action: "read file", path: path
    end
  end

  defp normalize_secret!(secret) do
    normalized = if String.valid?(secret), do: String.trim(secret), else: ""

    if byte_size(normalized) >= @minimum_secret_bytes do
      normalized
    else
      raise ArgumentError, "local secret file is invalid"
    end
  end

  defp ensure_secure_directory!(directory) do
    with :ok <- File.mkdir_p(directory),
         {:ok, %{type: :directory}} <- File.lstat(directory),
         :ok <- File.chmod(directory, 0o700),
         {:ok, stat} <- File.stat(directory),
         true <- band(stat.mode, 0o777) == 0o700 do
      :ok
    else
      _ -> raise ArgumentError, "local secret directory must be private and writable"
    end
  end

  defp secure_file!(path) do
    with {:ok, %{type: :regular}} <- File.lstat(path),
         :ok <- File.chmod(path, 0o600),
         {:ok, stat} <- File.stat(path),
         true <- band(stat.mode, 0o777) == 0o600 do
      :ok
    else
      _ -> raise ArgumentError, "local secret file must be a private regular file"
    end
  end
end
