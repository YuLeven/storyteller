defmodule Storyteller.Repo.Migrations.AddGameTimeToPlayEvents do
  use Ecto.Migration

  def change do
    alter table(:play_events) do
      add :game_time, :map
    end
  end
end
