defmodule Storyteller.Repo.Migrations.ExpandTurnFailureCategories do
  use Ecto.Migration

  @new_categories ~w(
    narration dialogue activity world_change panel_change character_creation
    character_update inventory_change roll_request communication_path remote_message
    objective_change continuity_change memory_update
  )

  @old_categories ~w(
    proposal_shape time_advance player_agency location_presence private_fact_boundary
    proposal_rules
  )

  def up do
    drop constraint(:play_turns, :play_turns_failure_category_check)

    create constraint(:play_turns, :play_turns_failure_category_check,
             check: failure_category_check(@old_categories ++ @new_categories)
           )
  end

  def down do
    drop constraint(:play_turns, :play_turns_failure_category_check)

    execute(
      "UPDATE play_turns SET failure_category = 'proposal_rules' " <>
        "WHERE failure_category IN (" <>
        Enum.map_join(@new_categories, ", ", &"'#{&1}'") <>
        ")"
    )

    create constraint(:play_turns, :play_turns_failure_category_check,
             check: failure_category_check(@old_categories)
           )
  end

  defp failure_category_check(categories) do
    """
    failure_category IS NULL OR (
      failure_category IN (#{Enum.map_join(categories, ", ", &"'#{&1}'")})
      AND failure_code = 'invalid_response'
      AND failure_stage = 'proposal_validation'
    )
    """
  end
end
