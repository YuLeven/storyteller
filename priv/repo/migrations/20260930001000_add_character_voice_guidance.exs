defmodule Storyteller.Repo.Migrations.AddCharacterVoiceGuidance do
  use Ecto.Migration

  def change do
    alter table(:play_characters) do
      add :voice_guidance, :map, null: false, default: %{}
    end
  end
end
