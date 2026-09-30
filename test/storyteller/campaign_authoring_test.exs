defmodule Storyteller.CampaignAuthoringTest do
  use Storyteller.DataCase, async: true

  import Storyteller.CampaignFixtures

  alias Storyteller.Campaigns
  alias Storyteller.Play
  alias Storyteller.Play.Character

  test "GM character voice guidance persists separately from public character facts" do
    campaign =
      campaign_fixture(%{
        gm_characters: [
          %{
            speaker_id: "captain-ren",
            name: "Captain Ren",
            visible_facts: %{"description" => "A harbor officer."},
            gm_private_facts: %{"motive" => "Protects the signal crew."},
            voice_guidance: %{
              quirks: "Taps the compass twice.",
              accent_dialect: "Soft coastal vowels.",
              cadence: "Short clauses, measured pauses.",
              vocabulary: "Uses harbor terms.",
              mannerisms: "Looks toward the tide before answering."
            }
          }
        ]
      })

    character = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "captain-ren")

    assert character.voice_guidance == %{
             "quirks" => "Taps the compass twice.",
             "accent_dialect" => "Soft coastal vowels.",
             "cadence" => "Short clauses, measured pauses.",
             "vocabulary" => "Uses harbor terms.",
             "mannerisms" => "Looks toward the tide before answering."
           }

    assert character.visible_facts == %{"description" => "A harbor officer."}
    refute character.visible_facts |> Jason.encode!() =~ "coastal vowels"

    assert {:ok, projection} = Play.public_projection(campaign.id)
    projected_character = Enum.find(projection.characters, &(&1.speaker_id == "captain-ren"))
    refute Map.has_key?(projected_character, :voice_guidance)
    refute Jason.encode!(projection) =~ "Taps the compass twice"
  end

  test "voice guidance fields and combined length are bounded and validated" do
    for voice_guidance <- [
          %{"accent_dialect" => String.duplicate("x", 281)},
          %{
            "accent_dialect" => String.duplicate("x", 280),
            "cadence" => String.duplicate("y", 921)
          },
          %{"voice" => "Not a supported voice field."},
          %{"quirks" => %{"instruction" => "malformed value"}}
        ] do
      attrs =
        valid_campaign_attrs()
        |> Map.put(:gm_characters, [%{name: "Captain Ren", voice_guidance: voice_guidance}])

      assert {:error,
              {:setup,
               "Voice notes need up to 280 characters per field and 1,200 characters total."}} =
               Campaigns.create_campaign(attrs)

      assert Campaigns.list_campaigns() == []
    end
  end

  test "campaign authoring edits affect future setup while preserving existing story history" do
    campaign =
      campaign_fixture(%{
        gm_characters: [
          %{
            speaker_id: "keeper-elin",
            name: "Keeper Elin",
            visible_facts: %{
              "description" => "Maintains the lighthouse.",
              "role" => "Keeps the western beacon lit."
            },
            gm_private_facts: %{
              "notes" => "She knows the lower lens is cracked.",
              "motive" => "Protect the harbor families."
            },
            voice_guidance: %{"cadence" => "Slow and deliberate."}
          }
        ]
      })

    session = hd(campaign.sessions)

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "authoring-history-turn",
               "Ask about the lantern.",
               provider: fn _request -> {:ok, Jason.encode!(ordinary_proposal())} end,
               model: "authoring-test"
             )

    assert {:ok, history_before} = Play.public_timeline(campaign.id)

    assert {:ok, updated_campaign} =
             Campaigns.update_campaign_authoring(campaign, %{
               "title" => "The Beacon at Low Tide",
               "premise" => "A new signal arrives from the outer reef.",
               "setting" => "A fictional island harbor",
               "tone" => "Warm and quietly suspenseful",
               "narration_language" => "French",
               "player_character" => "Ilya, a patient harbor courier",
               "gm_character_setup" => %{
                 "keeper-elin" => %{
                   "visible_facts_text" =>
                     "Maintains the lighthouse and studies the reef lights.",
                   "private_notes" => "She has found a second signal beneath the lower lens."
                 }
               },
               "character_voice_guidance" => %{
                 "keeper-elin" => %{
                   "quirks" => "Counts each lantern shutter before opening it.",
                   "accent_dialect" => "Gentle island lilt.",
                   "cadence" => "Slow and deliberate.",
                   "vocabulary" => "Calls storms squalls.",
                   "mannerisms" => "Touches the brass key at her belt."
                 }
               }
             })

    assert updated_campaign.title == "The Beacon at Low Tide"
    assert updated_campaign.premise == "A new signal arrives from the outer reef."
    assert updated_campaign.narration_language == "French"
    assert updated_campaign.player_character == "Ilya, a patient harbor courier"

    assert [saved_session_id] =
             Enum.map(Campaigns.get_campaign!(campaign.id).sessions, & &1.id)

    assert saved_session_id == session.id

    assert {:ok, history_after} = Play.public_timeline(campaign.id)
    assert history_after == history_before

    updated_character =
      Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "keeper-elin")

    assert updated_character.visible_facts["description"] ==
             "Maintains the lighthouse and studies the reef lights."

    assert updated_character.visible_facts["role"] == "Keeps the western beacon lit."

    assert updated_character.gm_private_facts["notes"] ==
             "She has found a second signal beneath the lower lens."

    assert updated_character.gm_private_facts["motive"] == "Protect the harbor families."

    assert updated_character.voice_guidance["quirks"] ==
             "Counts each lantern shutter before opening it."

    assert updated_character.voice_guidance["mannerisms"] == "Touches the brass key at her belt."

    player = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")
    assert player.name == "Ilya, a patient harbor courier"
    assert player.visible_facts["description"] == "Ilya, a patient harbor courier"

    assert {:ok, future_turn} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "future-context-turn",
               "Ask Keeper Elin about the lanterns."
             )

    assert {:ok, future_context} = Play.model_context(future_turn.id)
    keeper_context = Enum.find(future_context.characters, &(&1.speaker_id == "keeper-elin"))
    player_context = Enum.find(future_context.characters, &(&1.speaker_id == "player"))

    assert keeper_context.voice_guidance == updated_character.voice_guidance
    refute Map.has_key?(player_context, :voice_guidance)

    assert {:ok, projection} = Play.public_projection(campaign.id)
    projected_keeper = Enum.find(projection.characters, &(&1.speaker_id == "keeper-elin"))
    projected_player = Enum.find(projection.characters, &(&1.speaker_id == "player"))

    assert projected_keeper.visible_facts["description"] ==
             "Maintains the lighthouse and studies the reef lights."

    assert projected_player.visible_facts["description"] == "Ilya, a patient harbor courier"
    refute Jason.encode!(projection) =~ "second signal beneath the lower lens"
    refute Jason.encode!(projection) =~ "Gentle island lilt"
  end

  test "model-proposed character changes cannot write voice guidance" do
    campaign =
      campaign_fixture(%{
        gm_characters: [
          %{
            speaker_id: "watcher-ivo",
            name: "Watcher Ivo",
            voice_guidance: %{"vocabulary" => "Uses old navigation terms."}
          }
        ]
      })

    session = hd(campaign.sessions)

    proposal =
      ordinary_proposal()
      |> Map.put("character_updates", [
        %{
          "speaker_id" => "watcher-ivo",
          "visible_facts" => %{},
          "gm_private_facts" => %{},
          "voice_guidance" => %{"vocabulary" => "Changes its own voice."}
        }
      ])

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "voice-guidance-proposal",
               "Ask Ivo a question.",
               provider: fn _request -> {:ok, Jason.encode!(proposal)} end,
               model: "authoring-test"
             )

    saved_character = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "watcher-ivo")
    assert saved_character.voice_guidance == %{"vocabulary" => "Uses old navigation terms."}
  end

  defp ordinary_proposal do
    %{
      "narration" => "The harbor lantern turns toward the outer reef.",
      "dialogue" => [],
      "activities" => [],
      "public_changes" => %{},
      "private_changes" => %{},
      "panel_changes" => [],
      "memory_update" => %{"public_summary" => "", "gm_private_summary" => ""},
      "character_updates" => [],
      "character_creations" => [],
      "location_changes" => [],
      "inventory_changes" => [],
      "objective_changes" => [],
      "continuity_changes" => [],
      "roll_request" => nil
    }
  end
end
