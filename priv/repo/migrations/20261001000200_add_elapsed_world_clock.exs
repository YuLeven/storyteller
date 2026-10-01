defmodule Storyteller.Repo.Migrations.AddElapsedWorldClock do
  use Ecto.Migration

  def up do
    alter table(:play_states) do
      add :elapsed_world_minutes, :bigint, null: false, default: 0
      add :elapsed_world_anchor_minutes, :bigint, null: false, default: 0
      add :elapsed_world_anchor, :map, null: false, default: %{}
    end

    execute """
    UPDATE play_states
    SET elapsed_world_anchor = jsonb_strip_nulls(jsonb_build_object(
      'date', COALESCE(
        NULLIF(public_state->'date', 'null'::jsonb),
        NULLIF(public_state->'current_date', 'null'::jsonb),
        NULLIF(public_state->'world_date', 'null'::jsonb),
        NULLIF(public_state->'calendar_date', 'null'::jsonb)
      ),
      'time', COALESCE(
        NULLIF(public_state->'time', 'null'::jsonb),
        NULLIF(public_state->'current_time', 'null'::jsonb),
        NULLIF(public_state->'time_of_day', 'null'::jsonb),
        NULLIF(public_state->'world_time', 'null'::jsonb)
      )
    ))
    """

    create constraint(:play_states, :play_states_elapsed_world_minutes_check,
             check: "elapsed_world_minutes >= 0"
           )

    create constraint(:play_states, :play_states_elapsed_anchor_check,
             check:
               "elapsed_world_anchor_minutes >= 0 AND elapsed_world_anchor_minutes <= elapsed_world_minutes"
           )
  end

  def down do
    drop constraint(:play_states, :play_states_elapsed_anchor_check)

    drop constraint(:play_states, :play_states_elapsed_world_minutes_check)

    alter table(:play_states) do
      remove :elapsed_world_minutes
      remove :elapsed_world_anchor_minutes
      remove :elapsed_world_anchor
    end
  end
end
