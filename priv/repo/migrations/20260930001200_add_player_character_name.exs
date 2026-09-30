defmodule Storyteller.Repo.Migrations.AddPlayerCharacterName do
  use Ecto.Migration

  def up do
    alter table(:campaigns) do
      add :player_character_name, :string
    end

    # Legacy values commonly used "Name, description". Split only that
    # unambiguous delimiter; the full legacy text remains in player_character
    # and in the player's visible description facts. Ambiguous values retain
    # their full text as the name so no user-entered detail is discarded.
    execute """
    UPDATE campaigns
    SET player_character_name = COALESCE(
      NULLIF(BTRIM(SUBSTRING(player_character FROM '^([^,]{1,100}),[[:space:]]+.+$')), ''),
      player_character
    )
    """

    alter table(:campaigns) do
      modify :player_character_name, :string, null: false
    end
  end

  def down do
    alter table(:campaigns) do
      remove :player_character_name
    end
  end
end
