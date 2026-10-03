defmodule Storyteller.Repo.Migrations.AddTurnFailureCategory do
  use Ecto.Migration

  def up do
    alter table(:play_turns) do
      add :failure_category, :string
    end

    create constraint(:play_turns, :play_turns_failure_category_check,
             check: """
             failure_category IS NULL OR (
               failure_category IN (
                 'proposal_shape',
                 'time_advance',
                 'player_agency',
                 'location_presence',
                 'private_fact_boundary',
                 'proposal_rules'
               )
               AND failure_code = 'invalid_response'
               AND failure_stage = 'proposal_validation'
             )
             """
           )
  end

  def down do
    drop constraint(:play_turns, :play_turns_failure_category_check)

    alter table(:play_turns) do
      remove :failure_category
    end
  end
end
