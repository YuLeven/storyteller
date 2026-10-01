defmodule Storyteller.Repo.Migrations.AddTurnFailureStage do
  use Ecto.Migration

  def change do
    alter table(:play_turns) do
      add :failure_stage, :string
    end

    create constraint(:play_turns, :play_turns_failure_stage_check,
             check:
               "failure_stage IS NULL OR failure_stage IN ('context', 'provider', 'response_decoding', 'proposal_validation', 'commit')"
           )
  end
end
