defmodule Storyteller.Repo.Migrations.AddRemoteMessageEvent do
  use Ecto.Migration

  def up do
    drop constraint(:play_events, :play_events_type_check)

    create constraint(:play_events, :play_events_type_check,
             check:
               "event_type IN ('player_action', 'player_question', 'time_passage', 'gm_narration', 'npc_dialogue', 'remote_message', 'character_activity', 'roll_request', 'player_roll', 'state_change')"
           )
  end

  def down do
    drop constraint(:play_events, :play_events_type_check)

    create constraint(:play_events, :play_events_type_check,
             check:
               "event_type IN ('player_action', 'player_question', 'time_passage', 'gm_narration', 'npc_dialogue', 'character_activity', 'roll_request', 'player_roll', 'state_change')"
           )
  end
end
