defmodule Storyteller.Repo.Migrations.AddTurnInteractionIntents do
  use Ecto.Migration

  def up do
    alter table(:play_turns) do
      add :intent, :string, null: false, default: "action"
    end

    create constraint(:play_turns, :play_turns_intent_check,
             check: "intent IN ('action', 'question', 'time_passage', 'opening_scene')"
           )

    drop constraint(:play_events, :play_events_type_check)

    create constraint(:play_events, :play_events_type_check,
             check:
               "event_type IN ('player_action', 'player_question', 'time_passage', 'gm_narration', 'npc_dialogue', 'character_activity', 'roll_request', 'player_roll', 'state_change')"
           )
  end

  def down do
    drop constraint(:play_events, :play_events_type_check)

    create constraint(:play_events, :play_events_type_check,
             check:
               "event_type IN ('player_action', 'gm_narration', 'npc_dialogue', 'character_activity', 'roll_request', 'player_roll', 'state_change')"
           )

    drop constraint(:play_turns, :play_turns_intent_check)

    alter table(:play_turns) do
      remove :intent
    end
  end
end
