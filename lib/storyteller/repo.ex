defmodule Storyteller.Repo do
  use Ecto.Repo,
    otp_app: :storyteller,
    adapter: Ecto.Adapters.Postgres
end
