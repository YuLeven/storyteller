defmodule Storyteller.PlayTest do
  use Storyteller.DataCase

  import Storyteller.CampaignFixtures

  alias Storyteller.Campaigns
  alias Storyteller.Panels
  alias Storyteller.Panels.Field, as: PanelField
  alias Storyteller.Play
  alias Storyteller.Play.{Character, Event, Objective, Roll, State, Turn}

  test "GM memory is persisted by visibility and only recent events are sent back to the model" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, pending} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "bounded-memory",
               "Ask the keeper about her plans."
             )

    for sequence <- 1..90 do
      Repo.insert!(
        Event.changeset(%Event{}, %{
          campaign_id: campaign.id,
          session_id: session.id,
          turn_id: pending.id,
          sequence: sequence,
          event_type: :gm_narration,
          visibility: :public,
          payload: %{"text" => "Earlier scene #{sequence}"}
        })
      )
    end

    state = Repo.get_by!(State, campaign_id: campaign.id)
    Repo.update!(State.changeset(state, %{event_sequence: 90}))

    context_agent = Agent.start_link(fn -> nil end) |> elem(1)

    provider = fn request ->
      context = decode_request(request)
      Agent.update(context_agent, fn _ -> context end)

      memory_update = %{
        "public_summary" => "The keeper is studying an unusual eastern star.",
        "gm_private_summary" => "The keeper suspects the observatory chart was altered."
      }

      {:ok, Jason.encode!(ordinary_proposal(%{"memory_update" => memory_update}))}
    end

    assert {:ok, %{status: :completed} = resolved} =
             Play.retry_turn(pending.id, provider: provider)

    context = Agent.get(context_agent, & &1)
    assert context["memory"]["public_summary"] == ""
    assert context["memory"]["gm_private_summary"] == ""
    assert length(context["history"]) == 40
    assert hd(context["history"])["sequence"] == 51
    assert List.last(context["history"])["sequence"] == 90

    assert {:ok, persisted_context} = Play.model_context(resolved.id)

    assert persisted_context.memory.public_summary ==
             "The keeper is studying an unusual eastern star."

    assert persisted_context.memory.gm_private_summary ==
             "The keeper suspects the observatory chart was altered."

    {:ok, timeline_before_invalid_memory} = Play.public_timeline(campaign.id)

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "oversized-memory",
               "Look again at the chart.",
               provider:
                 ordinary_provider(%{
                   "memory_update" => %{
                     "public_summary" => String.duplicate("x", 6_001),
                     "gm_private_summary" => ""
                   }
                 })
             )

    {:ok, timeline_after_invalid_memory} = Play.public_timeline(campaign.id)
    assert timeline_after_invalid_memory == timeline_before_invalid_memory

    {:ok, after_invalid_memory} = Play.model_context(resolved.id)
    assert after_invalid_memory.memory.public_summary == persisted_context.memory.public_summary

    assert {:ok, projection} = Play.public_projection(campaign.id)
    refute Map.has_key?(projection, :memory)
    refute Map.has_key?(projection, :gm_private_history_summary)
  end

  test "player character details update publicly and reach the next session's GM context" do
    campaign =
      campaign_fixture(%{
        player_character_details: [
          %{label: "Health", value: "Exhausted"},
          %{label: "Skills", value: "Pruning"}
        ],
        gm_characters: [
          %{
            speaker_id: "npc:lyra",
            name: "Lyra",
            visible_facts: %{"role" => "keeper"},
            gm_private_facts: %{"motive" => "protect the chart"}
          }
        ]
      })

    session = hd(campaign.sessions)
    captured_context = Agent.start_link(fn -> nil end) |> elem(1)

    first_provider = fn request ->
      context = decode_request(request)
      Agent.update(captured_context, fn _ -> context end)

      {:ok,
       Jason.encode!(
         ordinary_proposal(%{
           "character_updates" => [
             %{
               "speaker_id" => "npc:lyra",
               "visible_facts" => %{"last_spoke" => "The eastern star moved once."},
               "gm_private_facts" => %{"still_hidden" => true}
             },
             %{
               "speaker_id" => "player",
               "visible_facts" => %{
                 "health" => "Rested",
                 "Vineyard responsibility" => "Restoring the east terrace"
               },
               "reason" => "The player rests and accepts the terrace work."
             }
           ]
         })
       )}
    end

    assert {:ok, %{status: :completed} = first_turn} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "player-fact-update",
               "Rest and take on the terrace work.",
               provider: first_provider
             )

    before_update_context = Agent.get(captured_context, & &1)

    player_before_update =
      Enum.find(before_update_context["characters"], &(&1["speaker_id"] == "player"))

    assert player_before_update["visible_facts"]["Health"] == "Exhausted"

    assert {:ok, projection} = Play.public_projection(campaign.id)
    player = Enum.find(projection.characters, &(&1.speaker_id == "player"))
    assert player.name == "Mira Vale, a patient apprentice astronomer"
    assert player.visible_facts["description"] == "Mira Vale, a patient apprentice astronomer"
    assert player.visible_facts["Health"] == "Rested"
    refute Map.has_key?(player.visible_facts, "health")
    assert player.visible_facts["Skills"] == "Pruning"
    assert player.visible_facts["Vineyard responsibility"] == "Restoring the east terrace"

    {:ok, timeline} = Play.public_timeline(campaign.id)

    [fact_event] =
      Enum.filter(timeline, &(&1.speaker_id == "player" and &1.event_type == :state_change))

    assert fact_event.payload["visible_facts"]["Health"] == "Rested"
    assert fact_event.payload["reason"] == "The player rests and accepts the terrace work."
    refute Map.has_key?(fact_event.payload, "gm_private_facts")

    player_record = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")
    assert player_record.gm_private_facts == %{}

    {:ok, next_session} = Campaigns.start_session(campaign)

    next_provider = fn request ->
      context = decode_request(request)
      Agent.update(captured_context, fn _ -> context end)
      {:ok, Jason.encode!(ordinary_proposal(%{"character_updates" => []}))}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "player-fact-next-session",
               "Check on the terrace work.",
               provider: next_provider
             )

    next_context = Agent.get(captured_context, & &1)
    player_context = Enum.find(next_context["characters"], &(&1["speaker_id"] == "player"))
    assert player_context["visible_facts"]["Health"] == "Rested"
    assert player_context["visible_facts"]["Skills"] == "Pruning"

    assert player_context["visible_facts"]["Vineyard responsibility"] ==
             "Restoring the east terrace"

    assert Repo.get!(Turn, first_turn.id).status == :completed
  end

  test "player fact updates reject private writes, missing reasons, unknown speakers, and identity changes atomically" do
    {campaign, session} = play_campaign("The Glass Observatory")
    initial_player = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")

    Repo.update!(
      Character.changeset(initial_player, %{
        gm_private_facts: %{"secret" => "Never overwrite this private note."}
      })
    )

    bad_proposals = [
      {
        "player-private-facts",
        %{
          "public_changes" => %{"weather" => "A rejected storm"},
          "character_updates" => [
            %{
              "speaker_id" => "npc:lyra",
              "visible_facts" => %{"trust" => "She trusts the player."},
              "gm_private_facts" => %{}
            },
            %{
              "speaker_id" => "player",
              "visible_facts" => %{"Health" => "Changed"},
              "gm_private_facts" => %{"secret" => "Proposed overwrite."},
              "reason" => "The action supports the visible change."
            }
          ]
        }
      },
      {
        "player-missing-reason",
        %{
          "character_updates" => [
            %{"speaker_id" => "player", "visible_facts" => %{"Health" => "Changed"}}
          ]
        }
      },
      {
        "player-unknown-id",
        %{
          "character_updates" => [
            %{
              "speaker_id" => "not-a-campaign-character",
              "visible_facts" => %{"Health" => "Changed"},
              "reason" => "The action supports the visible change."
            }
          ]
        }
      },
      {
        "player-identity-change",
        %{
          "character_updates" => [
            %{
              "speaker_id" => "player",
              "visible_facts" => %{
                "description" => "A different person",
                "name" => "Someone else"
              },
              "reason" => "This must not change core identity."
            }
          ]
        }
      },
      {
        "player-canonical-location-alias",
        %{
          "character_updates" => [
            %{
              "speaker_id" => "player",
              "visible_facts" => %{"current_place_name" => "A different place"},
              "reason" => "The location must come from the canonical place ledger."
            }
          ]
        }
      }
    ]

    for {key, overrides} <- bad_proposals do
      assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
               Play.submit_turn(campaign.id, session.id, key, "Take a consequential action.",
                 provider: ordinary_provider(overrides)
               )
    end

    assert {:ok, projection} = Play.public_projection(campaign.id)
    refute projection.world["weather"] == "A rejected storm"
    player = Enum.find(projection.characters, &(&1.speaker_id == "player"))
    refute Map.has_key?(player.visible_facts, "Health")

    keeper = Enum.find(projection.characters, &(&1.speaker_id == "npc:lyra"))
    refute Map.has_key?(keeper.visible_facts, "trust")

    unchanged_player = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")
    assert unchanged_player.name == initial_player.name
    assert unchanged_player.visible_facts == initial_player.visible_facts

    assert unchanged_player.gm_private_facts == %{
             "secret" => "Never overwrite this private note."
           }

    assert {:ok, []} = Play.public_timeline(campaign.id)
  end

  test "public projections separate private world and character facts" do
    {campaign, session} = play_campaign("The Glass Observatory")

    request_context = Agent.start_link(fn -> nil end) |> elem(1)

    provider = fn request ->
      context = decode_request(request)
      Agent.update(request_context, fn _ -> context end)

      {:ok,
       Jason.encode!(
         ordinary_proposal(%{
           "location_changes" => move_player_to("upper-dome", "Upper dome")
         })
       )}
    end

    assert {:ok, turn} =
             Play.submit_turn(campaign.id, session.id, "action-1", "Ask the keeper what she saw.",
               provider: provider,
               model: "test-model"
             )

    assert turn.status == :completed

    assert {:ok, %{revision: 1, world: world, characters: characters}} =
             Play.public_projection(campaign.id)

    keeper = Enum.find(characters, &(&1.speaker_id == "npc:lyra"))
    player = Enum.find(characters, &(&1.speaker_id == "player"))

    assert world["location"] == "Upper dome"
    refute Map.has_key?(world, "gm_private")
    assert keeper.speaker_id == "npc:lyra"
    assert keeper.visible_facts["role"] == "keeper"
    assert keeper.visible_activity == "She checks the brass shutter."
    refute Map.has_key?(keeper, :gm_private_facts)
    assert player.speaker_id == "player"

    assert %{
             "world" => %{"gm_private" => %{"weather_cause" => "a distant pressure front"}},
             "characters" => [%{"gm_private_facts" => %{"motive" => "protect the chart"}} | _],
             "player_action" => "Ask the keeper what she saw."
           } =
             Agent.get(request_context, & &1)

    assert {:ok, public_events} = Play.public_timeline(campaign.id)

    assert Enum.all?(
             public_events,
             &(&1.event_type in [
                 :player_action,
                 :gm_narration,
                 :npc_dialogue,
                 :character_activity,
                 :state_change
               ])
           )

    assert Enum.map(public_events, & &1.position) == Enum.to_list(1..length(public_events))

    assert Enum.any?(
             public_events,
             &(&1.event_type == :npc_dialogue and &1.speaker_id == "npc:lyra")
           )
  end

  test "objectives use ordered stable changes and remain canonical across sessions" do
    {campaign, session} = play_campaign("The Glass Observatory")
    captured_context = Agent.start_link(fn -> nil end) |> elem(1)

    first_provider = fn request ->
      context = decode_request(request)
      Agent.update(captured_context, fn _ -> context end)

      {:ok,
       Jason.encode!(
         ordinary_proposal(%{
           "objective_changes" => [
             %{
               "type" => "create",
               "objective" => %{
                 "objective_id" => "repair-east-terrace",
                 "title" => "Repair the east terrace",
                 "details" => "Find suitable stone and rebuild the retaining wall.",
                 "visibility" => "public"
               },
               "reason" => "The player agrees to restore the damaged terrace."
             },
             %{
               "type" => "update",
               "objective_id" => "repair-east-terrace",
               "title" => "Restore the eastern terrace",
               "reason" => "The established plan clarifies which terrace is meant."
             },
             %{
               "type" => "create",
               "objective" => %{
                 "objective_id" => "altered-chart-truth",
                 "title" => "Discover who altered the star chart",
                 "details" => "The chart was secretly changed before the observatory closed.",
                 "visibility" => "gm_private"
               },
               "reason" => "The keeper's private suspicion is not yet known to the player."
             }
           ]
         })
       )}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "objective-start",
               "I will repair the terrace.",
               provider: first_provider
             )

    {:ok, first_timeline} = Play.public_timeline(campaign.id)

    first_objective_event =
      Enum.find(first_timeline, &Map.has_key?(&1.payload, "objective_changes"))

    assert Enum.map(
             first_objective_event.payload["objective_changes"],
             & &1["objective"]["title"]
           ) ==
             ["Repair the east terrace", "Restore the eastern terrace"]

    refute Jason.encode!(first_timeline) =~ "altered-chart-truth"
    refute Jason.encode!(first_timeline) =~ "Discover who altered the star chart"
    refute Jason.encode!(first_timeline) =~ "The chart was secretly changed"

    {:ok, public_projection} = Play.public_projection(campaign.id)

    assert [
             %{
               objective_id: "repair-east-terrace",
               title: "Restore the eastern terrace",
               status: :open
             }
           ] =
             public_projection.objectives

    {:ok, next_session} = Campaigns.start_session(campaign)

    second_provider = fn request ->
      context = decode_request(request)
      Agent.update(captured_context, fn _ -> context end)

      {:ok,
       Jason.encode!(
         ordinary_proposal(%{
           "objective_changes" => [
             %{
               "type" => "update",
               "objective_id" => "repair-east-terrace",
               "status" => "completed",
               "reason" => "The terrace wall has been rebuilt and inspected."
             },
             %{
               "type" => "create",
               "objective" => %{
                 "objective_id" => "map-the-old-cellar",
                 "title" => "Map the old cellar",
                 "visibility" => "public"
               },
               "reason" => "The player discovers an uncharted cellar entrance."
             },
             %{
               "type" => "create",
               "objective" => %{
                 "objective_id" => "retire-the-false-lead",
                 "title" => "Check the abandoned trail",
                 "visibility" => "public"
               },
               "reason" => "The group decides the trail is no longer worth pursuing."
             },
             %{
               "type" => "update",
               "objective_id" => "retire-the-false-lead",
               "status" => "abandoned",
               "reason" => "The lead has been ruled out."
             }
           ]
         })
       )}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "objective-progress",
               "The wall is finished; we should map the cellar instead.",
               provider: second_provider
             )

    context = Agent.get(captured_context, & &1)

    assert Enum.any?(context["objectives"]["public"], fn objective ->
             objective["objective_id"] == "repair-east-terrace" and objective["status"] == "open"
           end)

    assert Enum.any?(context["objectives"]["gm_private"], fn objective ->
             objective["objective_id"] == "altered-chart-truth" and
               objective["title"] == "Discover who altered the star chart"
           end)

    assert Jason.encode!(context["history"]) =~ "The chart was secretly changed"

    {:ok, public_projection} = Play.public_projection(campaign.id)

    assert Enum.find(public_projection.objectives, &(&1.objective_id == "repair-east-terrace")).status ==
             :completed

    assert Enum.find(public_projection.objectives, &(&1.objective_id == "retire-the-false-lead")).status ==
             :abandoned

    assert Enum.find(public_projection.objectives, &(&1.objective_id == "map-the-old-cellar")).status ==
             :open

    {:ok, public_timeline} = Play.public_timeline(campaign.id)
    refute Jason.encode!(public_projection) =~ "altered-chart-truth"
    refute Jason.encode!(public_timeline) =~ "altered-chart-truth"
    refute Jason.encode!(public_timeline) =~ "Discover who altered the star chart"
  end

  test "invalid ordered objective proposals fail without applying earlier operations" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "invalid-objective-sequence",
               "Agree to a plan.",
               provider:
                 ordinary_provider(%{
                   "public_changes" => %{"weather" => "Changed by a rejected proposal"},
                   "objective_changes" => [
                     %{
                       "type" => "create",
                       "objective" => %{
                         "objective_id" => "new-plan",
                         "title" => "Repair the west gate",
                         "visibility" => "public"
                       },
                       "reason" => "The player agrees to repair it."
                     },
                     %{
                       "type" => "update",
                       "objective_id" => "missing-plan",
                       "status" => "completed",
                       "reason" => "This ID does not exist."
                     }
                   ]
                 })
             )

    assert Repo.all(from objective in Objective, where: objective.campaign_id == ^campaign.id) ==
             []

    assert {:ok, []} = Play.public_timeline(campaign.id)

    assert {:ok, %{world: %{"weather" => "Clear"}, objectives: []}} =
             Play.public_projection(campaign.id)

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "duplicate-objective-id",
               "Repeat the same commitment.",
               provider:
                 ordinary_provider(%{
                   "objective_changes" => [
                     %{
                       "type" => "create",
                       "objective" => %{
                         "objective_id" => "same-id",
                         "title" => "First title",
                         "visibility" => "public"
                       },
                       "reason" => "The first commitment is established."
                     },
                     %{
                       "type" => "create",
                       "objective" => %{
                         "objective_id" => "same-id",
                         "title" => "Different title",
                         "visibility" => "public"
                       },
                       "reason" => "A duplicate stable ID is invalid."
                     }
                   ]
                 })
             )

    assert Repo.all(from objective in Objective, where: objective.campaign_id == ^campaign.id) ==
             []

    assert {:ok, []} = Play.public_timeline(campaign.id)
  end

  test "places seed character presence, persist across turns, and keep private locations out of player views" do
    {campaign, session} = play_campaign("The Quiet Vineyard")
    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        public_state: Map.put(state.public_state, "location", "Vineyard gate")
      })
    )

    assert {:ok, _state} =
             Play.initialize_campaign(campaign, %{
               characters: [
                 %{
                   speaker_id: "npc:lyra",
                   name: "Lyra Vale",
                   visible_facts: %{"role" => "cellar keeper", "location" => "North cellar"}
                 }
               ]
             })

    assert {:ok, initial} = Play.public_projection(campaign.id)
    player = Enum.find(initial.characters, &(&1.speaker_id == "player"))
    lyra = Enum.find(initial.characters, &(&1.speaker_id == "npc:lyra"))
    assert player.current_place.name == "Vineyard gate"
    assert lyra.current_place.name == "North cellar"
    assert Enum.map(initial.places, & &1.name) |> Enum.sort() == ["North cellar", "Vineyard gate"]

    location_changes = [
      %{
        "type" => "create_place",
        "place" => %{
          "place_id" => "press-room",
          "name" => "Old press room",
          "description" => "Cool stone walls and a lingering scent of oak.",
          "visibility" => "public",
          "facts" => %{"surroundings" => "A row of aging barrels"}
        },
        "reason" => "The player follows the cellar passage."
      },
      %{
        "type" => "move_character",
        "speaker_id" => "player",
        "place_id" => "press-room",
        "reason" => "The player enters the old press room."
      },
      %{
        "type" => "create_place",
        "place" => %{
          "place_id" => "sealed-vault",
          "name" => "Sealed reserve vault",
          "visibility" => "gm_private",
          "facts" => %{"secret" => "A missing vintage is hidden here."}
        },
        "reason" => "The cellar keeper has a concealed private room."
      },
      %{
        "type" => "move_character",
        "speaker_id" => "npc:lyra",
        "place_id" => "sealed-vault",
        "reason" => "The keeper slips into the concealed vault."
      }
    ]

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "place-transition",
               "I explore the cellar.",
               provider: ordinary_provider(%{"location_changes" => location_changes}),
               model: "test-model"
             )

    observed_context = Agent.start_link(fn -> nil end) |> elem(1)

    context_provider = fn request ->
      Agent.update(observed_context, fn _ -> decode_request(request) end)
      {:ok, Jason.encode!(ordinary_proposal())}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(campaign.id, session.id, "place-context", "Look around the room.",
               provider: context_provider,
               model: "test-model"
             )

    context = Agent.get(observed_context, & &1)
    assert Enum.any?(context["places"]["gm_private"], &(&1["place_id"] == "sealed-vault"))
    context_lyra = Enum.find(context["characters"], &(&1["speaker_id"] == "npc:lyra"))
    assert context_lyra["current_place"]["place_id"] == "sealed-vault"

    assert {:ok, projection} = Play.public_projection(campaign.id)
    projected_player = Enum.find(projection.characters, &(&1.speaker_id == "player"))
    projected_lyra = Enum.find(projection.characters, &(&1.speaker_id == "npc:lyra"))
    assert projected_player.current_place.name == "Old press room"
    assert projection.world["location"] == "Old press room"
    assert projected_lyra.current_place == nil
    assert Enum.all?(projection.places, &(&1.place_id != "sealed-vault"))

    assert {:ok, public_events} = Play.public_timeline(campaign.id)
    encoded_events = Jason.encode!(public_events)
    refute encoded_events =~ "sealed-vault"
    refute encoded_events =~ "Sealed reserve vault"
    refute encoded_events =~ "concealed private room"
    assert Enum.any?(public_events, &Map.has_key?(&1.payload, "location_changes"))

    assert {:ok, next_session} = Campaigns.start_session(campaign)
    next_session_context = Agent.start_link(fn -> nil end) |> elem(1)

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "place-next-session",
               "Start the next day in the press room.",
               provider: fn request ->
                 Agent.update(next_session_context, fn _ -> decode_request(request) end)
                 {:ok, Jason.encode!(ordinary_proposal())}
               end,
               model: "test-model"
             )

    next_context = Agent.get(next_session_context, & &1)
    next_player = Enum.find(next_context["characters"], &(&1["speaker_id"] == "player"))
    assert next_player["current_place"]["name"] == "Old press room"
    assert Enum.any?(next_context["places"]["gm_private"], &(&1["place_id"] == "sealed-vault"))
  end

  test "introduces a new GM character who can speak, act, carry an item, and be publicly present immediately" do
    {campaign, session} = play_campaign("The Amber Orchard")

    creation = %{
      "speaker_id" => "npc:orin",
      "name" => "Orin Vale",
      "visible_facts" => %{"role" => "orchard courier", "known_for" => "careful maps"},
      "gm_private_facts" => %{"motive" => "quietly searching for his missing sister"}
    }

    location_changes = [
      %{
        "type" => "create_place",
        "place" => %{
          "place_id" => "south-gate",
          "name" => "South Gate",
          "visibility" => "public",
          "facts" => %{"surroundings" => "A low stone wall borders the road."}
        },
        "reason" => "The scene establishes the meeting place."
      },
      %{
        "type" => "move_character",
        "speaker_id" => "npc:orin",
        "place_id" => "south-gate",
        "reason" => "Orin meets the player at the gate."
      }
    ]

    inventory_changes = [
      %{
        "type" => "add",
        "item" => %{
          "id" => "orin-route-book",
          "name" => "Route book",
          "quantity" => 1,
          "owner_id" => "npc:orin",
          "visibility" => "public",
          "properties" => %{}
        },
        "reason" => "Orin arrives carrying his route book."
      }
    ]

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "meet-orin",
               "Ask the courier for directions.",
               provider:
                 ordinary_provider(%{
                   "character_creations" => [creation],
                   "dialogue" => [
                     %{"speaker_id" => "npc:orin", "text" => "The north path is clear."}
                   ],
                   "activities" => [
                     %{"speaker_id" => "npc:orin", "text" => "Orin checks his map."}
                   ],
                   "character_updates" => [
                     %{
                       "speaker_id" => "npc:orin",
                       "visible_facts" => %{"met_at" => "South Gate"},
                       "gm_private_facts" => %{
                         "first_impression" => "The player seems observant."
                       }
                     }
                   ],
                   "location_changes" => location_changes,
                   "inventory_changes" => inventory_changes
                 }),
               model: "test-model"
             )

    assert {:ok, projection} = Play.public_projection(campaign.id)
    orin = Enum.find(projection.characters, &(&1.speaker_id == "npc:orin"))
    assert orin.name == "Orin Vale"
    assert orin.role == :gm
    assert orin.visible_facts == Map.put(creation["visible_facts"], "met_at", "South Gate")
    assert orin.visible_activity == "Orin checks his map."
    assert orin.current_place.name == "South Gate"
    assert Enum.any?(projection.inventory, &(&1["owner_id"] == "npc:orin"))

    assert {:ok, events} = Play.public_timeline(campaign.id)
    assert Enum.any?(events, &(&1.event_type == :npc_dialogue and &1.speaker_id == "npc:orin"))

    assert Enum.any?(
             events,
             &(&1.event_type == :character_activity and &1.speaker_id == "npc:orin")
           )

    assert Enum.any?(events, &Map.has_key?(&1.payload, "character_created"))
    refute Jason.encode!(events) =~ "quietly searching for his missing sister"
    refute Jason.encode!(events) =~ "The player seems observant."
  end

  test "new NPC private facts and GM-private presence reach later sessions without public leakage" do
    {campaign, session} = play_campaign("The Amber Orchard")

    creation = %{
      "speaker_id" => "npc:elira",
      "name" => "Elira Moss",
      "visible_facts" => %{"trade" => "herbalist"},
      "gm_private_facts" => %{"fear" => "the flooded passage", "plan" => "hide the silver key"}
    }

    location_changes = [
      %{
        "type" => "create_place",
        "place" => %{
          "place_id" => "flooded-passage",
          "name" => "Flooded Passage",
          "visibility" => "gm_private",
          "facts" => %{"concealed" => "A silver key rests under a loose stone."}
        },
        "reason" => "The GM establishes a hidden passage."
      },
      %{
        "type" => "move_character",
        "speaker_id" => "npc:elira",
        "place_id" => "flooded-passage",
        "reason" => "Elira keeps watch in the hidden passage."
      }
    ]

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "meet-elira",
               "Look for a guide.",
               provider:
                 ordinary_provider(%{
                   "character_creations" => [creation],
                   "dialogue" => [],
                   "activities" => [],
                   "location_changes" => location_changes,
                   "character_updates" => []
                 }),
               model: "test-model"
             )

    assert {:ok, projection} = Play.public_projection(campaign.id)
    elira = Enum.find(projection.characters, &(&1.speaker_id == "npc:elira"))
    assert elira.visible_facts == creation["visible_facts"]
    assert elira.current_place == nil
    refute Enum.any?(projection.places, &(&1.place_id == "flooded-passage"))

    assert {:ok, public_events} = Play.public_timeline(campaign.id)
    public_json = Jason.encode!(public_events)
    refute public_json =~ "fear"
    refute public_json =~ "flooded-passage"
    refute public_json =~ "Flooded Passage"
    refute public_json =~ "silver key"

    assert {:ok, next_session} = Campaigns.start_session(campaign)
    captured_context = Agent.start_link(fn -> nil end) |> elem(1)

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "ask-elira",
               "Ask the herbalist about her work.",
               provider: fn request ->
                 Agent.update(captured_context, fn _context -> decode_request(request) end)

                 {:ok,
                  Jason.encode!(
                    ordinary_proposal(%{
                      "dialogue" => [],
                      "activities" => [],
                      "character_updates" => []
                    })
                  )}
               end,
               model: "test-model"
             )

    context = Agent.get(captured_context, & &1)
    context_elira = Enum.find(context["characters"], &(&1["speaker_id"] == "npc:elira"))
    assert context_elira["visible_facts"] == creation["visible_facts"]
    assert context_elira["gm_private_facts"] == creation["gm_private_facts"]
    assert context_elira["current_place"]["place_id"] == "flooded-passage"
    assert Enum.any?(context["places"]["gm_private"], &(&1["place_id"] == "flooded-passage"))
  end

  test "rejects duplicate new character IDs and unknown or invalid place references atomically" do
    invalid_scenarios = [
      {"existing-id", [%{"speaker_id" => "npc:lyra", "name" => "Another Lyra"}], []},
      {"player-id", [%{"speaker_id" => "player", "name" => "Replacement"}], []},
      {
        "duplicate-new-ids",
        [
          %{"speaker_id" => "npc:new", "name" => "First"},
          %{"speaker_id" => "npc:new", "name" => "Second"}
        ],
        []
      },
      {
        "unknown-place",
        [%{"speaker_id" => "npc:new", "name" => "Newcomer"}],
        [
          %{
            "type" => "move_character",
            "speaker_id" => "npc:new",
            "place_id" => "missing-place",
            "reason" => "No place exists."
          }
        ]
      },
      {
        "invalid-place-id",
        [%{"speaker_id" => "npc:new", "name" => "Newcomer"}],
        [
          %{
            "type" => "create_place",
            "place" => %{
              "place_id" => "bad/place",
              "name" => "Bad place",
              "visibility" => "public"
            },
            "reason" => "Invalid IDs are rejected."
          },
          %{
            "type" => "move_character",
            "speaker_id" => "npc:new",
            "place_id" => "bad/place",
            "reason" => "It cannot be used."
          }
        ]
      }
    ]

    for {key, creations, location_changes} <- invalid_scenarios do
      {campaign, session} = play_campaign("The Quiet Observatory")
      before_projection = Play.public_projection(campaign.id)

      assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
               Play.submit_turn(
                 campaign.id,
                 session.id,
                 "invalid-introduction-#{key}",
                 "Meet someone new.",
                 provider:
                   ordinary_provider(%{
                     "character_creations" => creations,
                     "location_changes" => location_changes
                   }),
                 model: "test-model"
               )

      assert Play.public_projection(campaign.id) == before_projection
      assert {:ok, []} = Play.public_timeline(campaign.id)
      refute Repo.get_by(Character, campaign_id: campaign.id, speaker_id: "npc:new")

      assert Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player").name ==
               campaign.player_character
    end
  end

  test "free-form world changes cannot teleport the player or overwrite the canonical location" do
    {campaign, session} = play_campaign("The Quiet Vineyard")
    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        public_state: Map.put(state.public_state, "location", "Vineyard gate")
      })
    )

    assert {:ok, _state} = Play.initialize_campaign(campaign)

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "free-form-location",
               "I leave the gate.",
               provider: ordinary_provider(%{"public_changes" => %{"location" => "The moon"}}),
               model: "test-model"
             )

    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert projection.world["location"] == "Vineyard gate"

    assert Enum.find(projection.characters, &(&1.speaker_id == "player")).current_place.name ==
             "Vineyard gate"

    assert {:ok, []} = Play.public_timeline(campaign.id)
  end

  test "inventory is canonical, private to the GM when marked, and continues across sessions" do
    {campaign, session} = play_campaign("The Quiet Observatory")

    herbs = %{
      "id" => "healing-herbs",
      "name" => "Healing herbs",
      "quantity" => 2,
      "unit" => "bundles",
      "owner_id" => "player",
      "visibility" => "public",
      "properties" => %{"healing" => %{"points" => 2}}
    }

    private_key = %{
      "id" => "sealed-key",
      "name" => "Sealed iron key",
      "quantity" => 1,
      "owner_id" => "npc:lyra",
      "visibility" => "gm_private",
      "properties" => %{}
    }

    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        public_state: Map.put(state.public_state, "inventory", [herbs]),
        gm_private_state: Map.put(state.gm_private_state, "inventory", [private_key])
      })
    )

    first_context = Agent.start_link(fn -> nil end) |> elem(1)

    provider = fn request ->
      context = decode_request(request)
      Agent.update(first_context, fn _ -> context end)

      changes = [
        %{
          "type" => "transfer",
          "item_id" => "healing-herbs",
          "owner_id" => "npc:lyra",
          "reason" => "Lyra takes the treatment supplies to the injured keeper."
        },
        %{
          "type" => "consume",
          "item_id" => "healing-herbs",
          "quantity" => 1,
          "reason" => "One bundle is used to clean a cut."
        },
        %{
          "type" => "add",
          "item" => %{
            "id" => "brass-key",
            "name" => "Brass key",
            "quantity" => 1,
            "owner_id" => "player",
            "visibility" => "public",
            "category" => "Key",
            "properties" => %{"opens" => "the observatory cabinet"}
          },
          "reason" => "The keeper explicitly hands over the cabinet key."
        },
        %{
          "type" => "consume",
          "item_id" => "sealed-key",
          "quantity" => 1,
          "reason" => "The keeper hides the key in a locked drawer."
        }
      ]

      {:ok, Jason.encode!(ordinary_proposal(%{"inventory_changes" => changes}))}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "inventory-moves",
               "Help the keeper tend the injured visitor.",
               provider: provider,
               model: "test-model"
             )

    context = Agent.get(first_context, & &1)
    assert Enum.map(context["inventory"]["player_visible"], & &1["id"]) == ["healing-herbs"]
    assert Enum.map(context["inventory"]["gm_private"], & &1["id"]) == ["sealed-key"]

    assert {:ok, projection} = Play.public_projection(campaign.id)

    assert MapSet.new(Enum.map(projection.inventory, & &1["id"])) ==
             MapSet.new(["healing-herbs", "brass-key"])

    refute Enum.any?(projection.inventory, &(&1["id"] == "sealed-key"))
    refute Map.has_key?(projection.world, "inventory")

    moved_herbs = Enum.find(projection.inventory, &(&1["id"] == "healing-herbs"))
    assert moved_herbs["owner_id"] == "npc:lyra"
    assert moved_herbs["quantity"] == 1

    {:ok, public_events} = Play.public_timeline(campaign.id)
    inventory_event = Enum.find(public_events, &Map.has_key?(&1.payload, "inventory_changes"))
    assert length(inventory_event.payload["inventory_changes"]) == 3
    refute Jason.encode!(inventory_event.payload) =~ "reason"
    refute Jason.encode!(inventory_event.payload) =~ "sealed-key"

    state = Repo.get_by!(State, campaign_id: campaign.id)
    assert state.gm_private_state["inventory"] == []
    refute Jason.encode!(public_events) =~ "sealed-key"

    assert {:ok, next_session} = Campaigns.start_session(campaign)
    resumed_context = Agent.start_link(fn -> nil end) |> elem(1)

    resumed_provider = fn request ->
      Agent.update(resumed_context, fn _ -> decode_request(request) end)
      {:ok, Jason.encode!(ordinary_proposal())}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "inventory-resume",
               "Check what supplies remain.",
               provider: resumed_provider,
               model: "test-model"
             )

    next_context = Agent.get(resumed_context, & &1)

    assert Enum.map(next_context["inventory"]["player_visible"], & &1["id"]) == [
             "healing-herbs",
             "brass-key"
           ]

    assert Enum.map(next_context["inventory"]["gm_private"], & &1["id"]) == []
  end

  test "an Amber Orchard harvest sale consumes produce and carries cash into the next session" do
    {campaign, session} = play_campaign("Amber Orchard harvest sale test fixture")

    apples = %{
      "id" => "orchard-apples",
      "name" => "Amber apples",
      "quantity" => 8,
      "unit" => "basket",
      "category" => "produce",
      "owner_id" => "player",
      "visibility" => "public",
      "properties" => %{"variety" => "Amberfall", "grade" => "first"}
    }

    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{public_state: Map.put(state.public_state, "inventory", [apples])})
    )

    insert_panel_field!(campaign.id, %{
      key: "orchard_cash",
      panel: "Orchard ledger",
      label: "Cash",
      value_type: :money,
      unit: "silver",
      visibility: :public,
      value: %{"value" => "18.5"}
    })

    first_context = Agent.start_link(fn -> nil end) |> elem(1)

    sale_provider = fn request ->
      Agent.update(first_context, fn _ -> decode_request(request) end)

      {:ok,
       Jason.encode!(
         ordinary_proposal(%{
           "inventory_changes" => [
             %{
               "type" => "consume",
               "item_id" => "orchard-apples",
               "quantity" => 1,
               "reason" => "A customer buys one basket at the orchard stand."
             }
           ],
           "panel_changes" => [
             %{
               "type" => "delta",
               "key" => "orchard_cash",
               "delta" => "6.25",
               "reason" => "A customer buys one basket at the orchard stand."
             }
           ]
         })
       )}
    end

    complete_turn(
      campaign,
      session,
      "amber-orchard-harvest-sale",
      "Sell a basket of this morning's apples.",
      sale_provider
    )

    before_sale_context = Agent.get(first_context, & &1)
    [starting_stock] = before_sale_context["inventory"]["player_visible"]
    assert starting_stock["quantity"] == 8

    assert [%{"key" => "orchard_cash", "value" => "18.5", "unit" => "silver"}] =
             Enum.filter(before_sale_context["panels"], &(&1["key"] == "orchard_cash"))

    sale_event =
      Repo.all(
        from event in Event,
          where: event.campaign_id == ^campaign.id and event.event_type == :state_change,
          order_by: [asc: event.sequence]
      )
      |> Enum.find(&Map.has_key?(&1.payload, "panel_changes"))

    assert sale_event.payload["panel_changes"] == [
             %{
               "key" => "orchard_cash",
               "label" => "Cash",
               "unit" => "silver",
               "type" => "delta",
               "before" => "18.5",
               "delta" => "6.25",
               "after" => "24.75",
               "reason" => "A customer buys one basket at the orchard stand."
             }
           ]

    assert {:ok, next_session} = Campaigns.start_session(campaign)
    next_context = Agent.start_link(fn -> nil end) |> elem(1)

    next_session_provider = fn request ->
      Agent.update(next_context, fn _ -> decode_request(request) end)
      {:ok, Jason.encode!(ordinary_proposal())}
    end

    complete_turn(
      campaign,
      next_session,
      "amber-orchard-check-ledger",
      "Check the remaining apples and cash.",
      next_session_provider
    )

    resumed_context = Agent.get(next_context, & &1)
    [remaining_stock] = resumed_context["inventory"]["player_visible"]
    assert remaining_stock["id"] == "orchard-apples"
    assert remaining_stock["quantity"] == 7

    assert [%{"key" => "orchard_cash", "value" => "24.75", "unit" => "silver"}] =
             Enum.filter(resumed_context["panels"], &(&1["key"] == "orchard_cash"))

    assert {:ok, %{inventory: [projected_stock], panels: [cash_panel]}} =
             Play.public_projection(campaign.id)

    assert projected_stock["id"] == "orchard-apples"
    assert projected_stock["quantity"] == 7
    assert projected_stock["owner_id"] == "player"

    assert [%{key: "orchard_cash", type: :money, unit: "silver", value: "24.75"}] =
             cash_panel.fields
  end

  test "inventory cannot change through free-form world changes or narration alone" do
    {campaign, session} = play_campaign("The Quiet Observatory")

    item = %{
      "id" => "field-journal",
      "name" => "Field journal",
      "quantity" => 1,
      "owner_id" => "player",
      "visibility" => "public",
      "properties" => %{}
    }

    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{public_state: Map.put(state.public_state, "inventory", [item])})
    )

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "free-form-inventory",
               "Take a silver compass.",
               provider: ordinary_provider(%{"public_changes" => %{"inventory" => []}})
             )

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "unproposed-inventory",
               "Take a silver compass.",
               provider:
                 ordinary_provider(%{
                   "narration" => "You pocket a silver compass and keep walking."
                 })
             )

    assert {:ok, %{inventory: [^item]}} = Play.public_projection(campaign.id)
    {:ok, events} = Play.public_timeline(campaign.id)
    refute Enum.any?(events, &Map.has_key?(&1.payload, "inventory_changes"))
  end

  test "partial stack transfer conserves quantity and rejects a later invalid operation atomically" do
    {campaign, session} = play_campaign("The Quiet Observatory")

    herbs = %{
      "id" => "healing-herbs",
      "name" => "Healing herbs",
      "quantity" => 4,
      "unit" => "bundles",
      "owner_id" => "player",
      "visibility" => "public",
      "properties" => %{"healing" => %{"points" => 2}}
    }

    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{public_state: Map.put(state.public_state, "inventory", [herbs])})
    )

    split = %{
      "type" => "transfer",
      "item_id" => "healing-herbs",
      "quantity" => 2,
      "new_item_id" => "lyra-herbs",
      "owner_id" => "npc:lyra",
      "reason" => "Lyra carries two bundles to the infirmary."
    }

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "partial-transfer",
               "I hand Lyra two bundles.",
               provider: ordinary_provider(%{"inventory_changes" => [split]}),
               model: "test-model"
             )

    assert {:ok, %{inventory: inventory}} = Play.public_projection(campaign.id)
    source = Enum.find(inventory, &(&1["id"] == "healing-herbs"))
    transferred = Enum.find(inventory, &(&1["id"] == "lyra-herbs"))

    assert source["quantity"] == 2
    assert source["owner_id"] == "player"
    assert transferred["quantity"] == 2
    assert transferred["owner_id"] == "npc:lyra"
    assert transferred["properties"] == source["properties"]
    assert Enum.sum(Enum.map(inventory, & &1["quantity"])) == 4

    {:ok, events} = Play.public_timeline(campaign.id)
    inventory_event = Enum.find(events, &Map.has_key?(&1.payload, "inventory_changes"))

    assert inventory_event.payload["inventory_changes"] == [
             %{
               "type" => "transfer",
               "item_id" => "healing-herbs",
               "new_item_id" => "lyra-herbs",
               "item_name" => "Healing herbs",
               "quantity" => 2,
               "unit" => "bundles",
               "owner_id" => "npc:lyra"
             }
           ]

    invalid_split = %{split | "new_item_id" => "another-stack"}

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "partial-transfer-rollback",
               "I hand Lyra three more bundles.",
               provider:
                 ordinary_provider(%{
                   "inventory_changes" => [
                     invalid_split,
                     %{
                       "type" => "consume",
                       "item_id" => "healing-herbs",
                       "quantity" => 3,
                       "reason" => "Use more bundles than remain."
                     }
                   ]
                 }),
               model: "test-model"
             )

    assert {:ok, %{inventory: unchanged}} = Play.public_projection(campaign.id)
    assert unchanged == inventory

    {:ok, events_after_invalid_proposal} = Play.public_timeline(campaign.id)

    assert length(
             Enum.filter(
               events_after_invalid_proposal,
               &Map.has_key?(&1.payload, "inventory_changes")
             )
           ) == 1
  end

  test "property updates keep nested fields, audit by visibility, and persist into the next session" do
    {campaign, session} = play_campaign("The Quiet Observatory")

    public_item = %{
      "id" => "brass-focus",
      "name" => "Brass focus",
      "quantity" => 1,
      "unit" => nil,
      "owner_id" => "player",
      "visibility" => "public",
      "properties" => %{
        "magic" => %{"charges" => 4, "school" => "abjuration"},
        "maker" => "Mira Vale"
      }
    }

    private_item = %{
      "id" => "sealed-wand",
      "name" => "Sealed wand",
      "quantity" => 1,
      "owner_id" => "npc:lyra",
      "visibility" => "gm_private",
      "properties" => %{"secret" => %{"charges" => 7, "source" => "the hidden vault"}}
    }

    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        public_state: Map.put(state.public_state, "inventory", [public_item]),
        gm_private_state: Map.put(state.gm_private_state, "inventory", [private_item])
      })
    )

    public_update = %{
      "type" => "update",
      "item_id" => "brass-focus",
      "properties" => %{"magic" => %{"charges" => 3, "condition" => "worn"}},
      "reason" => "The focus loses a charge when the ward is restored."
    }

    private_update = %{
      "type" => "update",
      "item_id" => "sealed-wand",
      "properties" => %{"secret" => %{"charges" => 6}},
      "reason" => "Lyra privately seals one charge away."
    }

    first_context = Agent.start_link(fn -> nil end) |> elem(1)

    provider = fn request ->
      context = decode_request(request)
      Agent.update(first_context, fn _ -> context end)

      {:ok,
       Jason.encode!(ordinary_proposal(%{"inventory_changes" => [public_update, private_update]}))}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "update-item-properties",
               "Restore the observatory ward.",
               provider: provider,
               model: "test-model"
             )

    initial_context = Agent.get(first_context, & &1)

    assert hd(initial_context["inventory"]["player_visible"])["properties"] ==
             public_item["properties"]

    assert hd(initial_context["inventory"]["gm_private"])["properties"] ==
             private_item["properties"]

    expected_public_properties = %{
      "magic" => %{"charges" => 3, "school" => "abjuration", "condition" => "worn"},
      "maker" => "Mira Vale"
    }

    expected_private_properties = %{
      "secret" => %{"charges" => 6, "source" => "the hidden vault"}
    }

    assert {:ok, %{inventory: [updated_public_item]} = projection} =
             Play.public_projection(campaign.id)

    assert updated_public_item["id"] == public_item["id"]
    assert updated_public_item["properties"] == expected_public_properties
    refute Jason.encode!(projection) =~ "sealed-wand"

    {:ok, public_events} = Play.public_timeline(campaign.id)

    [public_inventory_event] =
      Enum.filter(public_events, &Map.has_key?(&1.payload, "inventory_changes"))

    [public_change] = public_inventory_event.payload["inventory_changes"]
    assert public_change["type"] == "update"
    assert public_change["item_id"] == "brass-focus"
    refute Map.has_key?(public_change, "reason")
    refute Jason.encode!(public_change) =~ "sealed-wand"
    refute Jason.encode!(public_change) =~ "hidden vault"

    inventory_audit_events =
      Repo.all(Event)
      |> Enum.filter(fn event ->
        event.campaign_id == campaign.id and Map.has_key?(event.payload, "inventory_changes")
      end)

    [public_audit_event] = Enum.filter(inventory_audit_events, &(&1.visibility == :public))
    assert public_audit_event.payload == public_inventory_event.payload

    [private_inventory_event] =
      Enum.filter(inventory_audit_events, &(&1.visibility == :gm_private))

    [private_change] = private_inventory_event.payload["inventory_changes"]
    assert private_inventory_event.visibility == :gm_private
    assert private_change["item_id"] == "sealed-wand"
    assert private_change["reason"] == private_update["reason"]
    assert private_change["properties"] == private_update["properties"]
    refute Enum.any?(public_events, &(Jason.encode!(&1.payload) =~ "Lyra privately seals"))

    assert {:ok, next_session} = Campaigns.start_session(campaign)
    next_context = Agent.start_link(fn -> nil end) |> elem(1)

    resumed_provider = fn request ->
      Agent.update(next_context, fn _ -> decode_request(request) end)
      {:ok, Jason.encode!(ordinary_proposal())}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "read-updated-properties",
               "Check the focus before we continue.",
               provider: resumed_provider,
               model: "test-model"
             )

    resumed_context = Agent.get(next_context, & &1)

    assert hd(resumed_context["inventory"]["player_visible"])["properties"] ==
             expected_public_properties

    assert hd(resumed_context["inventory"]["gm_private"])["properties"] ==
             expected_private_properties
  end

  test "a later invalid inventory operation rolls back a property update" do
    {campaign, session} = play_campaign("The Quiet Observatory")

    item = %{
      "id" => "warding-charm",
      "name" => "Warding charm",
      "quantity" => 1,
      "owner_id" => "player",
      "visibility" => "public",
      "properties" => %{"charges" => 4, "ward" => %{"strength" => "faint"}}
    }

    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{public_state: Map.put(state.public_state, "inventory", [item])})
    )

    update = %{
      "type" => "update",
      "item_id" => "warding-charm",
      "properties" => %{"charges" => 1, "ward" => %{"strength" => "strong"}},
      "reason" => "The charm absorbs the final spark."
    }

    invalid_later_update = %{
      "type" => "update",
      "item_id" => "missing-item",
      "properties" => %{"charges" => 1},
      "reason" => "An unknown item cannot be updated."
    }

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "property-update-rollback",
               "I repair the charm.",
               provider:
                 ordinary_provider(%{
                   "inventory_changes" => [update, invalid_later_update]
                 }),
               model: "test-model"
             )

    assert {:ok, %{inventory: [^item]}} = Play.public_projection(campaign.id)
    {:ok, public_events} = Play.public_timeline(campaign.id)
    refute Enum.any?(public_events, &Map.has_key?(&1.payload, "inventory_changes"))

    refute Repo.all(Event)
           |> Enum.any?(fn event ->
             event.campaign_id == campaign.id and Map.has_key?(event.payload, "inventory_changes")
           end)
  end

  test "GM panel changes are typed, atomic, and private values stay out of public events" do
    {campaign, session} = play_campaign("The Glass Observatory")

    insert_panel_field!(campaign.id, %{
      key: "cash",
      panel: "Finances",
      label: "Available cash",
      value_type: :money,
      unit: "ARS",
      visibility: :public,
      value: %{"value" => "1000"}
    })

    insert_panel_field!(campaign.id, %{
      key: "keeper_secret",
      panel: "GM notes",
      label: "Hidden clue",
      value_type: :text,
      visibility: :gm_private,
      value: %{"value" => "unnoticed crack"}
    })

    insert_panel_field!(campaign.id, %{
      key: "season",
      panel: "Orchard",
      label: "Season",
      value_type: :status,
      visibility: :public,
      value: %{"value" => "Dormant"}
    })

    insert_panel_field!(campaign.id, %{
      key: "next_review",
      panel: "Calendar",
      label: "Next review",
      value_type: :date,
      visibility: :public,
      value: %{"value" => "2026-09-15"}
    })

    context_agent = Agent.start_link(fn -> nil end) |> elem(1)

    provider = fn request ->
      context = decode_request(request)
      Agent.update(context_agent, fn _ -> context end)

      proposal =
        ordinary_proposal(%{
          "panel_changes" => [
            %{
              "type" => "delta",
              "key" => "cash",
              "delta" => "250.50",
              "reason" => "A patron pays for the evening's telescope viewing."
            },
            %{
              "type" => "set",
              "key" => "season",
              "value" => "Harvest",
              "reason" => "The campaign calendar marks the harvest season."
            },
            %{
              "type" => "set",
              "key" => "next_review",
              "value" => "2026-10-01",
              "reason" => "The campaign calendar schedules the next ledger review."
            },
            %{
              "type" => "set",
              "key" => "keeper_secret",
              "value" => "revealed later",
              "reason" => "The keeper revises the private observation note."
            }
          ]
        })

      {:ok, Jason.encode!(proposal)}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "panel-update",
               "A patron pays 250.50 ARS to view the telescope.",
               provider: provider,
               model: "test-model"
             )

    assert [%{"key" => "cash", "value" => "1000", "unit" => "ARS"}] =
             Agent.get(context_agent, fn context ->
               assert Enum.any?(context["panels"], &(&1["key"] == "keeper_secret"))
               Enum.filter(context["panels"], &(&1["key"] == "cash"))
             end)

    assert {:ok, %{panels: panels}} = Play.public_projection(campaign.id)
    assert [%{key: "cash", value: "1250.5"}] = Enum.find(panels, &(&1.name == "Finances")).fields

    assert [%{key: "season", value: "Harvest"}] =
             Enum.find(panels, &(&1.name == "Orchard")).fields

    assert [%{key: "next_review", value: "2026-10-01"}] =
             Enum.find(panels, &(&1.name == "Calendar")).fields

    assert {:ok, timeline} = Play.public_timeline(campaign.id)
    public_panel_event = Enum.find(timeline, &Map.has_key?(&1.payload, "panel_changes"))

    assert Enum.map(public_panel_event.payload["panel_changes"], & &1["key"]) == [
             "cash",
             "season",
             "next_review"
           ]

    refute inspect(public_panel_event.payload) =~ "keeper_secret"
    refute inspect(timeline) =~ "revealed later"

    private_panel_event =
      Repo.all(
        from event in Event,
          where: event.campaign_id == ^campaign.id and event.visibility == :gm_private,
          order_by: [asc: event.sequence]
      )
      |> Enum.find(&Map.has_key?(&1.payload, "panel_changes"))

    assert [
             %{
               "key" => "keeper_secret",
               "before" => "unnoticed crack",
               "after" => "revealed later"
             }
           ] =
             private_panel_event.payload["panel_changes"]

    assert {:ok, private_field} = Panels.public_projection(campaign.id)

    refute Enum.any?(
             private_field.panels,
             &Enum.any?(&1.fields, fn field -> field.key == "keeper_secret" end)
           )

    timeline_before_invalid = timeline

    invalid_operations = [
      {"missing-panel-reason", "Sell the last bottle.",
       [
         %{
           "type" => "delta",
           "key" => "cash",
           "delta" => "3"
         }
       ]},
      {"negative-panel-result", "Spend beyond the balance.",
       [
         %{
           "type" => "delta",
           "key" => "cash",
           "delta" => "-2000",
           "reason" => "The player buys supplies."
         }
       ]},
      {"duplicate-panel-operation", "Sell two baskets.",
       [
         %{
           "type" => "delta",
           "key" => "cash",
           "delta" => "3",
           "reason" => "A customer buys the first basket."
         },
         %{
           "type" => "delta",
           "key" => "cash",
           "delta" => "3",
           "reason" => "A customer buys the second basket."
         }
       ]},
      {"wrong-panel-operation", "Change the cash field to text.",
       [
         %{
           "type" => "set",
           "key" => "cash",
           "value" => "900",
           "reason" => "The cash field has the wrong operation type."
         }
       ]}
    ]

    for {key, action, operations} <- invalid_operations do
      assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
               Play.submit_turn(
                 campaign.id,
                 session.id,
                 key,
                 action,
                 provider: ordinary_provider(%{"panel_changes" => operations}),
                 model: "test-model"
               )
    end

    assert {:ok, unchanged} = Play.public_projection(campaign.id)

    assert [%{key: "cash", value: "1250.5"}] =
             Enum.find(unchanged.panels, &(&1.name == "Finances")).fields

    assert {:ok, unchanged_timeline} = Play.public_timeline(campaign.id)
    assert unchanged_timeline == timeline_before_invalid

    assert {:ok, next_session} = Campaigns.start_session(campaign)
    next_context_agent = Agent.start_link(fn -> nil end) |> elem(1)

    next_session_provider = fn request ->
      Agent.update(next_context_agent, fn _ -> decode_request(request) end)
      {:ok, Jason.encode!(ordinary_proposal())}
    end

    complete_turn(
      campaign,
      next_session,
      "read-panel-values-next-session",
      "Check the campaign ledger.",
      next_session_provider
    )

    next_context = Agent.get(next_context_agent, & &1)
    assert Enum.find(next_context["panels"], &(&1["key"] == "cash"))["value"] == "1250.5"
    assert Enum.find(next_context["panels"], &(&1["key"] == "season"))["value"] == "Harvest"

    assert Enum.find(next_context["panels"], &(&1["key"] == "keeper_secret"))["value"] ==
             "revealed later"
  end

  test "reviewing a ledger without a transaction does not change canonical balances" do
    {campaign, session} = play_campaign("The Quiet Accounts")

    insert_panel_field!(campaign.id, %{
      key: "cash",
      panel: "Finances",
      label: "Cash",
      value_type: :money,
      unit: "ARS",
      visibility: :public,
      value: %{"value" => "100"}
    })

    instructions_agent = Agent.start_link(fn -> nil end) |> elem(1)

    provider = fn request ->
      Agent.update(instructions_agent, fn _ -> request.instructions end)
      {:ok, Jason.encode!(ordinary_proposal())}
    end

    complete_turn(campaign, session, "review-accounts", "Review the account balance.", provider)

    instructions = Agent.get(instructions_agent, & &1) |> String.replace(~r/\s+/, " ")
    assert instructions =~ "Merely reading or reviewing a ledger does not change it"

    assert {:ok, %{panels: [panel]}} = Play.public_projection(campaign.id)
    assert [%{key: "cash", value: "100"}] = panel.fields

    assert {:ok, timeline} = Play.public_timeline(campaign.id)
    refute Enum.any?(timeline, &Map.has_key?(&1.payload, "panel_changes"))
  end

  test "campaign snapshots stay isolated and campaign history continues across sessions" do
    {first, first_session} = play_campaign("The Glass Observatory")
    {second, second_session} = play_campaign("The Copper Archive")

    complete_turn(
      first,
      first_session,
      "first",
      "Look at the map.",
      ordinary_provider(%{"location_changes" => move_player_to("dome", "Dome")})
    )

    complete_turn(
      second,
      second_session,
      "second",
      "Open the catalog.",
      ordinary_provider(%{"location_changes" => move_player_to("archive", "Archive")})
    )

    assert {:ok, next_session} = Campaigns.start_session(first)

    complete_turn(
      first,
      next_session,
      "third",
      "Ask about the missing page.",
      ordinary_provider()
    )

    assert {:ok, first_projection} = Play.public_projection(first.id)
    assert {:ok, second_projection} = Play.public_projection(second.id)
    assert first_projection.world["location"] == "Dome"
    assert second_projection.world["location"] == "Archive"

    assert {:ok, first_history} = Play.public_timeline(first.id)
    assert Enum.count(first_history, &(&1.event_type == :player_action)) == 2
    assert Enum.any?(first_history, &(&1.session_id == first_session.id))
    assert Enum.any?(first_history, &(&1.session_id == next_session.id))

    assert Enum.all?(
             Play.public_timeline(second.id) |> elem(1),
             &(&1.session_id == second_session.id)
           )

    assert Enum.map(first_history, & &1.position) == Enum.to_list(1..length(first_history))
  end

  test "idempotency replays a completed turn and rejects key reuse with different text" do
    {campaign, session} = play_campaign("The Glass Observatory")
    caller = self()

    provider = fn _request ->
      send(caller, :provider_called)
      {:ok, Jason.encode!(ordinary_proposal())}
    end

    assert {:ok, first} =
             Play.submit_turn(campaign.id, session.id, "same-key", "Wait by the telescope.",
               provider: provider,
               model: "test-model"
             )

    assert_receive :provider_called

    assert {:ok, replay} =
             Play.submit_turn(campaign.id, session.id, "same-key", "Wait by the telescope.",
               provider: fn _ ->
                 flunk("a completed idempotent turn must not call the provider again")
               end
             )

    assert replay.id == first.id
    refute_receive :provider_called

    assert {:error, :idempotency_conflict} =
             Play.submit_turn(campaign.id, session.id, "same-key", "Leave the room.")

    assert Repo.aggregate(Turn, :count) == 1

    assert Enum.count(
             Play.public_timeline(campaign.id) |> elem(1),
             &(&1.event_type == :player_action)
           ) == 1
  end

  test "an ordinary action completes without asking for a D20" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, turn} =
             Play.submit_turn(campaign.id, session.id, "ordinary", "Polish the lens.",
               provider: ordinary_provider(),
               model: "test-model"
             )

    assert turn.status == :completed
    assert Repo.aggregate(Roll, :count) == 0

    assert {:error, :roll_not_authorized} =
             Play.click_player_d20(turn.id, roll_source: fn -> flunk("no roll was requested") end)
  end

  test "pending turns reconnect with the same record and can be resumed without duplicating input" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, pending} =
             Play.submit_turn(campaign.id, session.id, "resume", "Watch the eastern sky.")

    assert pending.status == :pending
    assert Play.get_turn(campaign.id, "resume").id == pending.id

    assert {:ok, same_pending} =
             Play.submit_turn(campaign.id, session.id, "resume", "Watch the eastern sky.",
               provider: fn _ ->
                 flunk("replayed pending submission does not start a second resolution")
               end
             )

    assert same_pending.id == pending.id
    assert {:ok, []} = Play.public_timeline(campaign.id)

    assert {:ok, resumed} =
             Play.retry_turn(pending.id, provider: ordinary_provider(), model: "test-model")

    assert resumed.id == pending.id
    assert resumed.status == :completed
    assert {:ok, timeline} = Play.public_timeline(campaign.id)
    assert Enum.count(timeline, &(&1.event_type == :player_action)) == 1
  end

  test "only an explicit click authorizes one app-generated D20 and the result survives replay" do
    {campaign, session} = play_campaign("The Glass Observatory")
    caller = self()
    calls = :atomics.new(1, [])

    provider = fn request ->
      count = :atomics.add_get(calls, 1, 1)
      context = decode_request(request)

      proposal =
        if count == 1 do
          roll_proposal()
        else
          assert context["player_roll"]["result"] == 17
          ordinary_proposal(%{"public_changes" => %{"world_time" => "Second watch"}})
        end

      {:ok, Jason.encode!(proposal)}
    end

    assert {:ok, waiting} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "climb",
               "Climb to the dome's narrow ledge.",
               provider: provider,
               model: "test-model"
             )

    assert waiting.status == :awaiting_roll
    assert waiting.roll_request["test"] == "Keep your balance on the ledge"
    assert Repo.aggregate(Roll, :count) == 0

    assert {:error, :turn_already_open} =
             Play.submit_turn(campaign.id, session.id, "too-soon", "Do something else.")

    assert {:error, :invalid_roll} =
             Play.click_player_d20(waiting.id, roll_source: fn -> 21 end)

    assert Repo.aggregate(Roll, :count) == 0

    source = fn ->
      send(caller, :roll_source_called)
      17
    end

    assert {:ok, %{turn: completed, roll: %Roll{result: 17}}} =
             Play.click_player_d20(waiting.id,
               roll_source: source,
               provider: provider,
               model: "test-model"
             )

    assert completed.status == :completed
    assert_receive :roll_source_called
    assert :atomics.get(calls, 1) == 2

    assert {:ok, %{turn: replay, roll: %Roll{result: 17}}} =
             Play.click_player_d20(waiting.id,
               roll_source: fn -> flunk("a replay must return the stored D20") end
             )

    assert replay.id == completed.id
    assert :atomics.get(calls, 1) == 2
    assert Repo.aggregate(Roll, :count) == 1

    assert {:ok, timeline} = Play.public_timeline(campaign.id)
    assert Enum.count(timeline, &(&1.event_type == :player_roll)) == 1
    assert Enum.find(timeline, &(&1.event_type == :player_roll)).payload["result"] == 17
  end

  test "provider timeout or malformed output leaves canonical state and timeline untouched, then retry succeeds" do
    for provider_error <- [{:error, :timeout}, {:ok, "not JSON"}] do
      {campaign, session} = play_campaign("The Glass Observatory")
      before = Play.public_projection(campaign.id)

      assert {:ok, failed} =
               Play.submit_turn(campaign.id, session.id, "retry-me", "Describe the sky.",
                 provider: fn _request -> provider_error end,
                 model: "test-model"
               )

      assert failed.status == :failed
      assert failed.player_input == "Describe the sky."
      assert {:ok, []} = Play.public_timeline(campaign.id)
      assert Play.public_projection(campaign.id) == before

      assert {:ok, retried} =
               Play.retry_turn(failed.id, provider: ordinary_provider(), model: "test-model")

      assert retried.status == :completed
      assert {:ok, events} = Play.public_timeline(campaign.id)
      assert Enum.count(events, &(&1.event_type == :player_action)) == 1
      assert Enum.at(events, 0).payload["text"] == "Describe the sky."
    end
  end

  test "a new action supersedes a failed turn while its explicit retry remains available before that choice" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, failed} =
             Play.submit_turn(campaign.id, session.id, "lost", "Check the window.",
               provider: fn _ -> {:error, :usage_unavailable} end
             )

    assert failed.status == :failed

    assert {:ok, completed} =
             Play.submit_turn(campaign.id, session.id, "new-action", "Ask for tea.",
               provider: ordinary_provider(),
               model: "test-model"
             )

    assert completed.status == :completed
    assert Repo.get!(Turn, failed.id).status == :superseded
    assert {:ok, events} = Play.public_timeline(campaign.id)
    assert Enum.count(events, &(&1.event_type == :player_action)) == 1
    assert Enum.at(events, 0).payload["text"] == "Ask for tea."
  end

  test "a reclaimed resolution attempt fences a late successful provider result" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, pending} =
             Play.submit_turn(campaign.id, session.id, "fence-success", "Watch the sky.")

    owner = self()

    old_provider = fn _request ->
      send(owner, {:old_provider_started, self()})

      receive do
        :return_old_result ->
          {:ok,
           Jason.encode!(
             ordinary_proposal(%{
               "location_changes" => move_player_to("stale", "Stale worker")
             })
           )}
      end
    end

    old_worker =
      Task.async(fn ->
        Play.retry_turn(pending.id, provider: old_provider, model: "test-model")
      end)

    assert_receive {:old_provider_started, old_provider_pid}
    mark_resolution_stale!(pending.id)

    assert {:ok, current} =
             Play.retry_turn(pending.id,
               provider:
                 ordinary_provider(%{
                   "location_changes" => move_player_to("fresh", "Fresh worker")
                 }),
               model: "test-model"
             )

    assert current.status == :completed
    send(old_provider_pid, :return_old_result)
    assert {:ok, late} = Task.await(old_worker, 5_000)
    assert late.status == :completed

    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert projection.world["location"] == "Fresh worker"

    assert Enum.count(
             Play.public_timeline(campaign.id) |> elem(1),
             &(&1.event_type == :player_action)
           ) == 1
  end

  test "a reclaimed resolution attempt fences a late provider failure" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, pending} =
             Play.submit_turn(campaign.id, session.id, "fence-failure", "Watch the sky.")

    owner = self()

    old_provider = fn _request ->
      send(owner, {:old_provider_started, self()})

      receive do
        :return_old_failure -> {:error, :timeout}
      end
    end

    old_worker =
      Task.async(fn ->
        Play.retry_turn(pending.id, provider: old_provider, model: "test-model")
      end)

    assert_receive {:old_provider_started, old_provider_pid}
    mark_resolution_stale!(pending.id)

    assert {:ok, current} =
             Play.retry_turn(pending.id, provider: ordinary_provider(), model: "test-model")

    assert current.status == :completed
    send(old_provider_pid, :return_old_failure)
    assert {:ok, late} = Task.await(old_worker, 5_000)
    assert late.status == :completed
    assert late.failure_code == nil
    assert Repo.get!(Turn, pending.id).status == :completed

    assert Enum.count(
             Play.public_timeline(campaign.id) |> elem(1),
             &(&1.event_type == :player_action)
           ) == 1
  end

  test "session rollover closes a pending provider turn and the next session can play" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, pending} =
             Play.submit_turn(campaign.id, session.id, "rollover-race", "Look through the lens.")

    owner = self()

    provider = fn _request ->
      send(owner, {:provider_started, self()})

      receive do
        :return_after_rollover ->
          {:ok,
           Jason.encode!(
             ordinary_proposal(%{
               "location_changes" => move_player_to("must-not-commit", "Must not commit")
             })
           )}
      end
    end

    worker =
      Task.async(fn -> Play.retry_turn(pending.id, provider: provider, model: "test-model") end)

    assert_receive {:provider_started, provider_pid}

    assert {:ok, next_session} = Campaigns.start_session(campaign)
    closed = Repo.get!(Turn, pending.id)
    assert closed.status == :failed
    assert closed.failure_code == "session_closed"

    send(provider_pid, :return_after_rollover)
    assert {:ok, late} = Task.await(worker, 5_000)
    assert late.status == :failed

    assert Play.public_projection(campaign.id)
           |> elem(1)
           |> Map.fetch!(:world)
           |> Map.fetch!("location") == nil

    assert {:ok, []} = Play.public_timeline(campaign.id)

    assert {:ok, next_turn} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "after-rollover",
               "Ask about the weather.",
               provider: ordinary_provider(),
               model: "test-model"
             )

    assert next_turn.status == :completed
    assert Repo.get!(Turn, pending.id).status == :superseded
  end

  test "campaign archive closes an in-flight provider turn before it can commit" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, pending} =
             Play.submit_turn(campaign.id, session.id, "archive-race", "Open the dome.")

    owner = self()

    provider = fn _request ->
      send(owner, {:provider_started, self()})

      receive do
        :return_after_archive ->
          {:ok,
           Jason.encode!(
             ordinary_proposal(%{
               "location_changes" => move_player_to("must-not-commit", "Must not commit")
             })
           )}
      end
    end

    worker =
      Task.async(fn -> Play.retry_turn(pending.id, provider: provider, model: "test-model") end)

    assert_receive {:provider_started, provider_pid}

    assert {:ok, archived} = Campaigns.archive_campaign(campaign)
    closed = Repo.get!(Turn, pending.id)
    assert closed.status == :failed
    assert closed.failure_code == "session_closed"

    send(provider_pid, :return_after_archive)
    assert {:ok, late} = Task.await(worker, 5_000)
    assert late.status == :failed

    assert Play.public_projection(campaign.id)
           |> elem(1)
           |> Map.fetch!(:world)
           |> Map.fetch!("location") == nil

    assert {:ok, []} = Play.public_timeline(campaign.id)

    assert {:error, :campaign_unavailable} =
             Play.submit_turn(archived.id, session.id, "after-archive", "No action.")

    assert {:ok, restored} = Campaigns.restore_campaign(archived)
    assert {:ok, new_session} = Campaigns.start_session(restored)

    assert {:ok, resumed} =
             Play.submit_turn(restored.id, new_session.id, "after-restore", "Begin again.",
               provider: ordinary_provider(),
               model: "test-model"
             )

    assert resumed.status == :completed
    assert Repo.get!(Turn, pending.id).status == :superseded
  end

  test "rejects unrecognized speakers and campaign/session mismatches" do
    {campaign, session} = play_campaign("The Glass Observatory")

    invalid_speaker =
      ordinary_proposal(%{
        "dialogue" => [%{"speaker_id" => "not-in-this-campaign", "text" => "I know you."}],
        "public_changes" => %{"location" => "Must not commit"}
      })

    assert {:ok, failed} =
             Play.submit_turn(campaign.id, session.id, "bad-speaker", "Listen.",
               provider: fn _ -> {:ok, Jason.encode!(invalid_speaker)} end
             )

    assert failed.status == :failed
    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert projection.world["location"] == nil
    assert {:ok, []} = Play.public_timeline(campaign.id)

    other = campaign_fixture(%{title: "The Copper Archive"})
    other_session = hd(other.sessions)

    assert {:error, changeset} =
             Repo.insert(
               Turn.changeset(%Turn{}, %{
                 campaign_id: campaign.id,
                 session_id: other_session.id,
                 idempotency_key: "cross-campaign",
                 request_hash: String.duplicate("a", 64),
                 player_input: "This relation must be rejected.",
                 status: :completed,
                 resolution_phase: :initial,
                 attempts: 0
               })
             )

    assert Keyword.has_key?(changeset.errors, :session_id)
  end

  defp play_campaign(title) do
    campaign = campaign_fixture(%{title: title})
    session = hd(campaign.sessions)

    state = Repo.get_by!(State, campaign_id: campaign.id)

    assert {:ok, _state} =
             Repo.update(
               State.changeset(state, %{
                 public_state: %{
                   "weather" => "Clear",
                   "location" => nil,
                   "world_time" => "First watch"
                 },
                 gm_private_state: %{"weather_cause" => "a distant pressure front"}
               })
             )

    assert {:ok, _state} =
             Play.initialize_campaign(campaign, %{
               characters: [
                 %{
                   speaker_id: "npc:lyra",
                   name: "Lyra",
                   visible_facts: %{"role" => "keeper"},
                   gm_private_facts: %{"motive" => "protect the chart"},
                   visible_activity: nil
                 }
               ]
             })

    {campaign, session}
  end

  defp insert_panel_field!(campaign_id, attrs) do
    defaults = %{
      campaign_id: campaign_id,
      key: "resource",
      panel: "Resources",
      label: "Resource",
      value_type: :text,
      visibility: :public,
      value: %{"value" => ""},
      position: 0
    }

    Repo.insert!(PanelField.changeset(%PanelField{}, Map.merge(defaults, attrs)))
  end

  defp complete_turn(campaign, session, key, action, provider) do
    assert {:ok, %{status: :completed}} =
             Play.submit_turn(campaign.id, session.id, key, action,
               provider: provider,
               model: "test-model"
             )
  end

  defp ordinary_provider(overrides \\ %{}) do
    proposal = ordinary_proposal(overrides)
    fn _request -> {:ok, Jason.encode!(proposal)} end
  end

  defp ordinary_proposal(overrides \\ %{}) do
    Map.merge(
      %{
        "narration" => "The observatory settles into the quiet of the watch.",
        "dialogue" => [%{"speaker_id" => "npc:lyra", "text" => "The eastern star moved once."}],
        "activities" => [%{"speaker_id" => "npc:lyra", "text" => "She checks the brass shutter."}],
        "public_changes" => %{},
        "private_changes" => %{"weather_cause" => "a distant pressure front"},
        "panel_changes" => [],
        "memory_update" => %{"public_summary" => "", "gm_private_summary" => ""},
        "character_updates" => [
          %{
            "speaker_id" => "npc:lyra",
            "visible_facts" => %{"last_spoke" => "The eastern star moved once."},
            "gm_private_facts" => %{"still_hidden" => true}
          }
        ],
        "location_changes" => [],
        "roll_request" => nil
      },
      overrides
    )
  end

  defp move_player_to(place_id, name) do
    [
      %{
        "type" => "create_place",
        "place" => %{
          "place_id" => place_id,
          "name" => name,
          "visibility" => "public",
          "facts" => %{"kind" => "known place"}
        },
        "reason" => "The scene establishes the place."
      },
      %{
        "type" => "move_character",
        "speaker_id" => "player",
        "place_id" => place_id,
        "reason" => "The player's action brings them there."
      }
    ]
  end

  defp roll_proposal do
    %{
      "narration" => "The narrow ledge is slick; keeping your balance will take focus.",
      "dialogue" => [],
      "activities" => [],
      "public_changes" => %{},
      "private_changes" => %{},
      "panel_changes" => [],
      "character_updates" => [],
      "memory_update" => %{"public_summary" => "", "gm_private_summary" => ""},
      "roll_request" => %{
        "test" => "Keep your balance on the ledge",
        "difficulty" => "A demanding, uncertain climb",
        "target" => 14
      }
    }
  end

  defp decode_request(request) do
    text = request.input |> hd() |> Map.fetch!(:content) |> hd() |> Map.fetch!(:text)
    Jason.decode!(text)
  end

  defp mark_resolution_stale!(turn_id) do
    turn = Repo.get!(Turn, turn_id)

    stale_at =
      DateTime.utc_now() |> DateTime.add(-121, :second) |> DateTime.truncate(:microsecond)

    {:ok, _turn} = Repo.update(Turn.changeset(turn, %{resolution_started_at: stale_at}))
  end
end
