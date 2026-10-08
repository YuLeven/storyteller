defmodule Storyteller.Repo.Migrations.DefaultGMModelToLuna do
  use Ecto.Migration

  def up do
    execute(
      "UPDATE gm_model_preferences SET model_slug = 'gpt-6-luna', updated_at = NOW() WHERE id = 1 AND model_slug IS NULL"
    )
  end

  # Keep a user's explicit Luna selection intact if this migration is rolled back.
  def down, do: :ok
end
