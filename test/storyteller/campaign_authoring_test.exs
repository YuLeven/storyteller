defmodule Storyteller.CampaignAuthoringTest do
  use Storyteller.DataCase, async: true

  import Storyteller.CampaignFixtures

  alias Storyteller.Campaigns
  alias Storyteller.Campaigns.AuthoringCorrection
  alias Storyteller.Play
  alias Storyteller.Play.{Character, State}

  test "player name headlines the roster while the full profile details reach the GM" do
    campaign =
      campaign_fixture(%{
        player_character_name: "Tamsin Quill",
        player_character: "A retired sky-cartographer who marks storms before they arrive."
      })

    assert {:ok, projection} = Play.public_projection(campaign.id)
    player = Enum.find(projection.characters, &(&1.speaker_id == "player"))

    assert player.name == "Tamsin Quill"

    assert player.visible_facts["description"] ==
             "A retired sky-cartographer who marks storms before they arrive."

    [session] = campaign.sessions

    assert {:ok, turn} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "distinct-player-identity-context",
               "Ask what Tamsin knows about the weather."
             )

    assert {:ok, context} = Play.model_context(turn.id)
    prompt_player = Enum.find(context.characters, &(&1.speaker_id == "player"))

    assert prompt_player.name == "Tamsin Quill"

    assert prompt_player.visible_facts["description"] ==
             "A retired sky-cartographer who marks storms before they arrive."
  end

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

  test "setup binds an active duty to the character's canonical starting place and keeps it GM-only" do
    campaign =
      campaign_fixture(%{
        starting_location: "The Finca",
        gm_characters: [
          %{
            speaker_id: "npc:cellar-keeper",
            name: "Marcel",
            starting_place: "The river bodega",
            active_duty_name: "Tend the morning fermentation checks"
          }
        ]
      })

    character = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:cellar-keeper")

    bodega =
      Repo.get_by!(Storyteller.Play.Place, campaign_id: campaign.id, name: "The river bodega")

    assert character.current_place_id == bodega.place_id
    assert character.duty_name == "Tend the morning fermentation checks"
    assert character.duty_place_id == bodega.place_id

    assert {:ok, projection} = Play.public_projection(campaign.id)
    projected = Enum.find(projection.characters, &(&1.speaker_id == "npc:cellar-keeper"))
    refute Map.has_key?(projected, :active_duty)
    refute Jason.encode!(projection) =~ "Tend the morning fermentation checks"
    refute Jason.encode!(projection) =~ "duty_place_id"

    [session] = campaign.sessions
    assert {:ok, turn} = Play.submit_turn(campaign.id, session.id, "duty-context", "Look around.")
    assert {:ok, context} = Play.model_context(turn.id)
    gm_character = Enum.find(context.characters, &(&1.speaker_id == "npc:cellar-keeper"))

    assert gm_character.active_duty == %{
             name: "Tend the morning fermentation checks",
             place_id: bodega.place_id,
             place_name: "The river bodega"
           }
  end

  test "active duties change only through a reasoned revision-checked private correction" do
    campaign =
      campaign_fixture(%{
        starting_location: "The Finca",
        gm_characters: [
          %{
            speaker_id: "npc:cellar-keeper",
            name: "Marcel",
            starting_place: "The Finca"
          }
        ]
      })

    character = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:cellar-keeper")
    state_before = Repo.get_by!(State, campaign_id: campaign.id)
    assert {:ok, history_before} = Play.public_timeline(campaign.id)
    assert {:ok, before_projection} = Play.public_projection(campaign.id)

    attrs = %{
      "correction_reason" => "Marcel is assigned to watch the fermentation vats.",
      "expected_revision" => before_projection.revision,
      "character_active_duties" => %{
        "npc:cellar-keeper" => %{"duty_name" => "Watch the fermentation vats"}
      }
    }

    assert {:ok, _campaign} = Campaigns.update_campaign_authoring(campaign, attrs)

    character = Repo.get_by!(Character, id: character.id)
    assert character.duty_name == "Watch the fermentation vats"
    assert character.duty_place_id == character.current_place_id

    [correction] = Repo.all(AuthoringCorrection)
    assert correction.contains_private_changes

    assert correction.before_state["gm_characters"]["npc:cellar-keeper"]["active_duty"] == %{
             "name" => nil,
             "place_id" => nil
           }

    assert correction.after_state["gm_characters"]["npc:cellar-keeper"]["active_duty"] == %{
             "name" => "Watch the fermentation vats",
             "place_id" => character.current_place_id
           }

    assert Campaigns.list_public_authoring_corrections(campaign.id) == []

    assert Repo.get_by!(State, campaign_id: campaign.id).elapsed_world_minutes ==
             state_before.elapsed_world_minutes

    assert Repo.get_by!(State, campaign_id: campaign.id).revision == state_before.revision + 1
    assert {:ok, history_after} = Play.public_timeline(campaign.id)
    assert history_after == history_before

    assert {:ok, assigned_projection} = Play.public_projection(campaign.id)

    assert {:error, :stale_authoring_revision} =
             Campaigns.update_campaign_authoring(campaign, %{
               "correction_reason" => "Attempt to overwrite a newer assignment.",
               "expected_revision" => before_projection.revision,
               "character_active_duties" => %{
                 "npc:cellar-keeper" => %{"duty_name" => "Watch the press room"}
               }
             })

    assert {:error, :invalid_correction_reason} =
             Campaigns.update_campaign_authoring(campaign, %{
               "expected_revision" => assigned_projection.revision,
               "character_active_duties" => %{
                 "npc:cellar-keeper" => %{"duty_name" => "Watch the press room"}
               }
             })

    assert {:ok, _campaign} =
             Campaigns.update_campaign_authoring(campaign, %{
               "correction_reason" => "Marcel's assignment at the vats has ended.",
               "expected_revision" => assigned_projection.revision,
               "character_active_duties" => %{"npc:cellar-keeper" => %{"duty_name" => ""}}
             })

    released = Repo.get_by!(Character, id: character.id)
    assert is_nil(released.duty_name)
    assert is_nil(released.duty_place_id)

    assert Repo.get_by!(State, campaign_id: campaign.id).elapsed_world_minutes ==
             state_before.elapsed_world_minutes

    assert Repo.get_by!(State, campaign_id: campaign.id).revision == state_before.revision + 2
    assert {:ok, history_after_release} = Play.public_timeline(campaign.id)
    assert history_after_release == history_before
  end

  test "a GM duty needs a canonical starting place and its edit rejects unresolved turns" do
    attrs =
      valid_campaign_attrs()
      |> Map.put(:gm_characters, [
        %{speaker_id: "npc:cellar-keeper", name: "Marcel", active_duty_name: "Tend the vats"}
      ])

    assert {:error, {:setup, message}} = Campaigns.create_campaign(attrs)
    assert message =~ "needs a starting place"

    campaign =
      campaign_fixture(%{
        starting_location: "The Finca",
        gm_characters: [
          %{
            speaker_id: "npc:cellar-keeper",
            name: "Marcel",
            starting_place: "The Finca"
          }
        ]
      })

    [session] = campaign.sessions

    assert {:ok, turn} =
             Play.submit_turn(campaign.id, session.id, "open-duty-turn", "Look around.")

    assert turn.status == :pending
    assert {:ok, projection} = Play.public_projection(campaign.id)

    assert {:error, :authoring_turn_in_progress} =
             Campaigns.update_campaign_authoring(campaign, %{
               "correction_reason" => "Marcel begins ferment checks.",
               "expected_revision" => projection.revision,
               "character_active_duties" => %{
                 "npc:cellar-keeper" => %{"duty_name" => "Check fermentation"}
               }
             })

    assert Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:cellar-keeper").duty_name ==
             nil
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
               "correction_reason" => "Clarify the new reef signal and courier details.",
               "title" => "The Beacon at Low Tide",
               "premise" => "A new signal arrives from the outer reef.",
               "setting" => "A fictional island harbor",
               "tone" => "Warm and quietly suspenseful",
               "narration_language" => "French",
               "player_character_name" => "Ilya",
               "player_character" => "A patient harbor courier who knows every island path.",
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
    assert updated_campaign.player_character_name == "Ilya"

    assert updated_campaign.player_character ==
             "A patient harbor courier who knows every island path."

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
    assert player.name == "Ilya"

    assert player.visible_facts["description"] ==
             "A patient harbor courier who knows every island path."

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
    assert player_context.name == "Ilya"

    assert player_context.visible_facts["description"] ==
             "A patient harbor courier who knows every island path."

    refute Map.has_key?(player_context, :voice_guidance)

    assert {:ok, projection} = Play.public_projection(campaign.id)
    projected_keeper = Enum.find(projection.characters, &(&1.speaker_id == "keeper-elin"))
    projected_player = Enum.find(projection.characters, &(&1.speaker_id == "player"))

    assert projected_keeper.visible_facts["description"] ==
             "Maintains the lighthouse and studies the reef lights."

    assert projected_player.name == "Ilya"

    assert projected_player.visible_facts["description"] ==
             "A patient harbor courier who knows every island path."

    refute Jason.encode!(projection) =~ "second signal beneath the lower lens"
    refute Jason.encode!(projection) =~ "Gentle island lilt"
  end

  test "changed setup requires a reason while an unchanged save creates no correction" do
    campaign = campaign_fixture()

    assert {:error, :invalid_correction_reason} =
             Campaigns.update_campaign_authoring(campaign, %{"title" => "A changed title"})

    assert Campaigns.get_campaign!(campaign.id).title == campaign.title
    assert Repo.aggregate(AuthoringCorrection, :count, :id) == 0

    assert {:ok, unchanged} =
             Campaigns.update_campaign_authoring(campaign, %{"title" => campaign.title})

    assert unchanged.title == campaign.title
    assert Repo.aggregate(AuthoringCorrection, :count, :id) == 0
  end

  test "public setup correction stores before and after values but exposes only a safe summary" do
    campaign =
      campaign_fixture(%{
        player_character_name: "Tamsin Quill",
        player_character: "A retired sky-cartographer.",
        gm_characters: [
          %{
            speaker_id: "keeper-elin",
            name: "Keeper Elin",
            visible_facts: %{"description" => "Maintains the lighthouse."}
          }
        ]
      })

    assert {:ok, _campaign} =
             Campaigns.update_campaign_authoring(campaign, %{
               "correction_reason" => "Clarify the courier's name and the keeper's role.",
               "title" => "The Beacon at Low Tide",
               "player_character_name" => "Tamsin Vale",
               "gm_character_setup" => %{
                 "keeper-elin" => %{
                   "visible_facts_text" => "Maintains the lighthouse and charts the reefs."
                 }
               }
             })

    correction = Repo.get_by!(AuthoringCorrection, campaign_id: campaign.id)
    refute correction.contains_private_changes
    assert correction.reason == "Clarify the courier's name and the keeper's role."

    assert correction.before_state == %{
             "campaign" => %{
               "title" => campaign.title,
               "player_character_name" => "Tamsin Quill"
             },
             "player_character" => %{"name" => "Tamsin Quill"},
             "gm_characters" => %{
               "keeper-elin" => %{
                 "visible_facts" => %{"description" => "Maintains the lighthouse."}
               }
             }
           }

    assert correction.after_state == %{
             "campaign" => %{
               "title" => "The Beacon at Low Tide",
               "player_character_name" => "Tamsin Vale"
             },
             "player_character" => %{"name" => "Tamsin Vale"},
             "gm_characters" => %{
               "keeper-elin" => %{
                 "visible_facts" => %{
                   "description" => "Maintains the lighthouse and charts the reefs."
                 }
               }
             }
           }

    assert [summary] = Campaigns.list_public_authoring_corrections(campaign.id)
    assert summary.sequence == correction.sequence
    assert summary.reason == correction.reason

    assert summary.summary_categories == [
             "campaign_setup",
             "player_character",
             "character_details"
           ]

    refute Map.has_key?(summary, :before_state)
    refute Map.has_key?(summary, :after_state)

    assert {:ok, projection} = Play.public_projection(campaign.id)
    refute Jason.encode!(projection) =~ correction.reason
  end

  test "a private setup correction is persisted but omitted from safe correction summaries" do
    campaign =
      campaign_fixture(%{
        gm_characters: [
          %{
            speaker_id: "watcher-ivo",
            name: "Watcher Ivo",
            gm_private_facts: %{"notes" => "Knows the sealed passage."},
            voice_guidance: %{"cadence" => "Measured pauses."}
          }
        ]
      })

    secret_reason = "Record the newly discovered private passage."
    private_value = "The passage opens beneath the north stair."

    assert {:ok, _campaign} =
             Campaigns.update_campaign_authoring(campaign, %{
               "correction_reason" => secret_reason,
               "gm_character_setup" => %{
                 "watcher-ivo" => %{"private_notes" => private_value}
               },
               "character_voice_guidance" => %{
                 "watcher-ivo" => %{"cadence" => "Waits before naming the hidden stair."}
               }
             })

    correction = Repo.get_by!(AuthoringCorrection, campaign_id: campaign.id)
    assert correction.contains_private_changes

    assert correction.before_state["gm_characters"]["watcher-ivo"]["gm_private_facts"]["notes"] ==
             "Knows the sealed passage."

    assert Campaigns.list_public_authoring_corrections(campaign.id) == []

    assert {:ok, projection} = Play.public_projection(campaign.id)
    projection_json = Jason.encode!(projection)
    refute projection_json =~ private_value
    refute projection_json =~ secret_reason
    refute projection_json =~ "Waits before naming the hidden stair."
  end

  test "an enclosing rollback undoes setup, character, and correction writes together" do
    campaign =
      campaign_fixture(%{
        gm_characters: [%{speaker_id: "npc:keeper", name: "Keeper"}]
      })

    player_before = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")

    assert {:error, :authoring_test_rollback} =
             Repo.transaction(fn ->
               assert {:ok, _updated} =
                        Campaigns.update_campaign_authoring(campaign, %{
                          "correction_reason" => "Test atomic rollback.",
                          "title" => "Changed then rolled back",
                          "player_character_name" => "A different hero"
                        })

               Repo.rollback(:authoring_test_rollback)
             end)

    assert Campaigns.get_campaign!(campaign.id).title == campaign.title

    assert Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player") ==
             player_before

    assert Repo.aggregate(AuthoringCorrection, :count, :id) == 0
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
