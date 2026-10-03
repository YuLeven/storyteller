defmodule Storyteller.PlayTest do
  use Storyteller.DataCase

  import ExUnit.CaptureLog
  import Storyteller.CampaignFixtures

  alias Storyteller.Campaigns
  alias Storyteller.Panels
  alias Storyteller.Panels.Field, as: PanelField
  alias Storyteller.Play
  alias Storyteller.Settings

  alias Storyteller.Play.{
    CanonCorrection,
    CanonCorrections,
    Character,
    ContinuityEntry,
    Event,
    Objective,
    Place,
    PlaceConnection,
    Roll,
    State,
    Turn
  }

  test "emits only numeric provider latency measurements on success" do
    {campaign, session} = play_campaign("The Provider Latency Observatory")
    assert_provider_latency(campaign, session, "provider-latency-success", ordinary_provider(), 1)
  end

  test "emits only numeric provider latency measurements on failure" do
    {campaign, session} = play_campaign("The Provider Failure Observatory")

    assert_provider_latency(
      campaign,
      session,
      "provider-latency-failure",
      fn _request -> {:error, :timeout} end,
      0
    )
  end

  test "provider stream activity renews only its own resolving turn lease" do
    {campaign, session} = play_campaign("The Slow Stream Observatory")
    test_pid = self()

    assert {:ok, pending} =
             Play.submit_turn(campaign.id, session.id, "slow-stream-turn", "I wait.",
               provider: nil
             )

    provider = fn request ->
      send(test_pid, {:stream_activity_callback, self(), request.on_stream_activity})

      receive do
        :finish_stream -> {:ok, Jason.encode!(ordinary_proposal())}
      after
        5_000 -> flunk("the fake provider stream was not released")
      end
    end

    task =
      Task.async(fn ->
        Play.retry_turn(pending.id, provider: provider, model: "test-model")
      end)

    assert_receive {:stream_activity_callback, provider_pid, callback}, 2_000
    assert is_function(callback, 0)

    stale_at = DateTime.add(DateTime.utc_now(), -121, :second) |> DateTime.truncate(:microsecond)
    Repo.update!(Turn.changeset(Repo.get!(Turn, pending.id), %{resolution_started_at: stale_at}))
    assert Play.resolution_lease_expired?(Repo.get!(Turn, pending.id))

    callback.()

    refreshed_turn = Repo.get!(Turn, pending.id)
    refute Play.resolution_lease_expired?(refreshed_turn)
    assert DateTime.compare(refreshed_turn.resolution_started_at, stale_at) == :gt

    send(provider_pid, :finish_stream)
    assert {:ok, %{status: :completed}} = Task.await(task, 5_000)
  end

  test "superseded stream callbacks and outcomes cannot change a newer resolution attempt" do
    for {case_name, provider_outcome} <- [
          {:late_success, {:ok, Jason.encode!(ordinary_proposal())}},
          {:late_failure, {:error, :timeout}}
        ] do
      {campaign, session} = play_campaign("The Fenced Stream Observatory #{case_name}")
      test_pid = self()

      assert {:ok, pending} =
               Play.submit_turn(
                 campaign.id,
                 session.id,
                 "fenced-stream-#{case_name}",
                 "I keep watch.",
                 provider: nil
               )

      provider = fn request ->
        send(
          test_pid,
          {:old_stream_waiting, case_name, self(), request.on_stream_activity}
        )

        receive do
          :release_old_stream -> provider_outcome
        after
          5_000 -> flunk("the fake old stream was not released")
        end
      end

      task =
        Task.async(fn ->
          Play.retry_turn(pending.id, provider: provider, model: "test-model")
        end)

      assert_receive {:old_stream_waiting, ^case_name, old_provider_pid, old_callback}, 2_000

      newer_lease_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      newer_attempt = pending.attempts + 2

      Repo.update!(
        Turn.changeset(Repo.get!(Turn, pending.id), %{
          attempts: newer_attempt,
          resolution_started_at: newer_lease_at
        })
      )

      old_callback.()

      newer_turn = Repo.get!(Turn, pending.id)
      assert newer_turn.status == :resolving
      assert newer_turn.attempts == newer_attempt
      assert newer_turn.resolution_started_at == newer_lease_at

      send(old_provider_pid, :release_old_stream)

      assert {:ok, %{status: :resolving, attempts: ^newer_attempt}} = Task.await(task, 5_000)

      unchanged_turn = Repo.get!(Turn, pending.id)
      assert unchanged_turn.status == :resolving
      assert unchanged_turn.attempts == newer_attempt
      assert unchanged_turn.resolution_started_at == newer_lease_at
      assert is_nil(unchanged_turn.failure_code)
      assert {:ok, []} = Play.public_timeline(campaign.id)
    end
  end

  test "a saved GM model is passed into turn resolution when no call override is supplied" do
    {campaign, session} = play_campaign("The Model Preference Observatory")
    assert {:ok, _preference} = Settings.set_preferred_gm_model("fixture-model")

    test_pid = self()

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(campaign.id, session.id, "preferred-model-turn", "Look around.",
               provider: fn request ->
                 send(test_pid, {:resolved_model, Map.get(request, :model)})
                 {:ok, Jason.encode!(ordinary_proposal())}
               end
             )

    assert_received {:resolved_model, "fixture-model"}
  end

  test "opening scene needs a public player place and presence for its speaking characters" do
    {campaign, session} = play_campaign("The Unplaced Observatory", starting_location: nil)
    assert {:ok, opening_turn} = Play.ensure_opening_scene(campaign.id, session.id)

    unanchored =
      ordinary_proposal(%{
        "dialogue" => [],
        "activities" => [],
        "character_updates" => [],
        "location_changes" => []
      })

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.retry_turn(opening_turn.id,
               provider: fn _request -> {:ok, Jason.encode!(unanchored)} end,
               model: "test-model"
             )

    assert {:ok, []} = Play.public_timeline(campaign.id)
    assert {:ok, projection} = Play.public_projection(campaign.id)
    player = Enum.find(projection.characters, &(&1.speaker_id == "player"))
    assert is_nil(player.current_place_id)

    opening_place_changes = [
      %{
        "type" => "create_place",
        "place" => %{
          "place_id" => "observatory-dome",
          "name" => "The Observatory Dome",
          "visibility" => "public"
        },
        "reason" => "The GM establishes where the opening scene takes place."
      },
      %{
        "type" => "move_character",
        "speaker_id" => "player",
        "place_id" => "observatory-dome",
        "reason" => "Mira begins the story at the observatory."
      }
    ]

    missing_npc_presence =
      ordinary_proposal(%{
        "dialogue" => [%{"speaker_id" => "npc:lyra", "text" => "The dome is opening."}],
        "activities" => [],
        "character_updates" => [],
        "location_changes" => opening_place_changes
      })

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.retry_turn(opening_turn.id,
               provider: fn _request -> {:ok, Jason.encode!(missing_npc_presence)} end,
               model: "test-model"
             )

    assert {:ok, []} = Play.public_timeline(campaign.id)

    anchored =
      ordinary_proposal(%{
        "dialogue" => [%{"speaker_id" => "npc:lyra", "text" => "The dome is opening."}],
        "activities" => [],
        "character_updates" => [],
        "location_changes" =>
          opening_place_changes ++
            [
              %{
                "type" => "move_character",
                "speaker_id" => "npc:lyra",
                "place_id" => "observatory-dome",
                "reason" => "Lyra is present when the scene begins."
              }
            ]
      })

    assert {:ok, %{status: :completed}} =
             Play.retry_turn(opening_turn.id,
               provider: fn _request -> {:ok, Jason.encode!(anchored)} end,
               model: "test-model"
             )

    assert {:ok, projection} = Play.public_projection(campaign.id)
    player = Enum.find(projection.characters, &(&1.speaker_id == "player"))
    lyra = Enum.find(projection.characters, &(&1.speaker_id == "npc:lyra"))
    assert player.current_place_id == "observatory-dome"
    assert lyra.current_place_id == "observatory-dome"
    assert projection.world["location"] == "The Observatory Dome"
  end

  test "opening scene keeps a configured public starting place without inventing another" do
    campaign = campaign_fixture(%{starting_location: "The Glass Observatory"})
    [session] = campaign.sessions
    assert {:ok, opening_turn} = Play.ensure_opening_scene(campaign.id, session.id)

    opening =
      ordinary_proposal(%{"dialogue" => [], "activities" => [], "character_updates" => []})

    assert {:ok, %{status: :completed}} =
             Play.retry_turn(opening_turn.id,
               provider: fn _request -> {:ok, Jason.encode!(opening)} end,
               model: "test-model"
             )

    assert {:ok, projection} = Play.public_projection(campaign.id)
    player = Enum.find(projection.characters, &(&1.speaker_id == "player"))
    assert player.current_place.name == "The Glass Observatory"
    assert player.current_place_id
  end

  test "out-of-character inventory corrections persist into the next session without rewriting story" do
    {campaign, session} = play_campaign("The Orchard Ledger")

    original_item = %{
      "id" => "orchard-wine",
      "name" => "Reserve wine",
      "quantity" => 2,
      "unit" => "bottles",
      "owner_id" => "player",
      "visibility" => "public",
      "properties" => %{"vintage" => "1566"}
    }

    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        public_state: Map.put(state.public_state, "inventory", [original_item])
      })
    )

    assert {:ok, options} = CanonCorrections.options(campaign.id, session.id)
    assert Enum.map(options.inventory, & &1.id) == ["orchard-wine"]

    assert {:ok, added} =
             CanonCorrections.correct(campaign.id, session.id, %{
               "kind" => "inventory",
               "expected_revision" => options.revision,
               "reason" => "One bottle from the last delivery was omitted.",
               "values" => %{
                 "action" => "add",
                 "name" => "Cellar key",
                 "quantity" => "1",
                 "unit" => "key",
                 "owner_id" => "player"
               }
             })

    added_record =
      Repo.get_by!(CanonCorrection, campaign_id: campaign.id, sequence: added.sequence)

    assert added_record.kind == "inventory"
    assert added_record.expected_revision == options.revision
    assert added_record.before_state == %{"item" => nil}
    assert added_record.after_state["item"]["name"] == "Cellar key"

    assert {:ok, options_after_add} = CanonCorrections.options(campaign.id, session.id)

    assert {:ok, _corrected} =
             CanonCorrections.correct(campaign.id, session.id, %{
               "kind" => "inventory",
               "target_id" => "orchard-wine",
               "expected_revision" => options_after_add.revision,
               "reason" => "Only five bottles remain in the cellar.",
               "values" => %{"action" => "set", "quantity" => "5", "owner_id" => ""}
             })

    state = Repo.get_by!(State, campaign_id: campaign.id)
    assert state.revision == options_after_add.revision + 1
    assert state.event_sequence == 0
    assert state.elapsed_world_minutes == 0
    assert {:ok, []} = Play.public_timeline(campaign.id)

    {:ok, next_session} =
      Campaigns.start_session(Campaigns.get_campaign!(campaign.id), %{title: "A later day"})

    captured = Agent.start_link(fn -> nil end) |> elem(1)

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "corrected-inventory-context",
               "Look around.",
               provider: fn request ->
                 Agent.update(captured, fn _ -> decode_request(request) end)

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

    context = Agent.get(captured, & &1)
    reserve = Enum.find(context["inventory"]["player_visible"], &(&1["id"] == "orchard-wine"))
    key = Enum.find(context["inventory"]["player_visible"], &(&1["id"] == added_record.target_id))
    assert reserve["quantity"] == 5
    assert key["name"] == "Cellar key"

    receipts = CanonCorrections.list_receipts(campaign.id)

    assert Enum.map(receipts, & &1.reason) == [
             "Only five bottles remain in the cellar.",
             "One bottle from the last delivery was omitted."
           ]
  end

  test "inventory detail corrections preserve public item identity and reject hidden items" do
    {campaign, session} = play_campaign("The Orchard Item Ledger")

    public_item = %{
      "id" => "orchard-wine",
      "name" => "Reserve wine",
      "quantity" => 2,
      "unit" => "bottles",
      "category" => "wine",
      "description" => "The last two bottles from the 1566 harvest.",
      "owner_id" => "player",
      "visibility" => "public",
      "properties" => %{"vintage" => "1566", "condition" => "clear"}
    }

    hidden_item = %{
      "id" => "sealed-ledger",
      "name" => "Secret cellar ledger",
      "quantity" => 1,
      "unit" => "book",
      "owner_id" => "player",
      "visibility" => "gm_private",
      "properties" => %{}
    }

    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        public_state: Map.put(state.public_state, "inventory", [public_item, hidden_item])
      })
    )

    assert {:ok, options} = CanonCorrections.options(campaign.id, session.id)
    assert Enum.map(options.inventory, & &1.id) == ["orchard-wine"]
    assert hd(options.inventory).properties == public_item["properties"]
    refute inspect(options.inventory) =~ "Secret cellar ledger"

    values = %{
      "action" => "edit",
      "name" => "Barrel-aged reserve",
      "quantity" => "3",
      "unit" => "small casks",
      "category" => "cellar reserve",
      "description" => "Three casks held back for the autumn tasting.",
      "owner_id" => "party",
      "properties" => ~s({"vintage":"1567","condition":"sealed","notes":{"rack":"north"}})
    }

    assert {:ok, receipt} =
             CanonCorrections.correct(campaign.id, session.id, %{
               "kind" => "inventory",
               "target_id" => "orchard-wine",
               "expected_revision" => options.revision,
               "reason" => "The cellar inventory was checked against the physical casks.",
               "values" => values
             })

    record = Repo.get_by!(CanonCorrection, campaign_id: campaign.id, sequence: receipt.sequence)
    state = Repo.get_by!(State, campaign_id: campaign.id)
    corrected = Enum.find(state.public_state["inventory"], &(&1["id"] == "orchard-wine"))

    assert record.before_state == %{"item" => public_item}
    assert record.after_state["item"] == corrected

    assert corrected == %{
             "id" => "orchard-wine",
             "name" => "Barrel-aged reserve",
             "quantity" => 3,
             "unit" => "small casks",
             "category" => "cellar reserve",
             "description" => "Three casks held back for the autumn tasting.",
             "owner_id" => "party",
             "visibility" => "public",
             "properties" => %{
               "vintage" => "1567",
               "condition" => "sealed",
               "notes" => %{"rack" => "north"}
             }
           }

    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert Enum.find(projection.inventory, &(&1["id"] == "orchard-wine")) == corrected

    assert Enum.find(state.public_state["inventory"], &(&1["id"] == "sealed-ledger")) ==
             hidden_item

    assert state.event_sequence == 0
    assert state.elapsed_world_minutes == 0
    assert {:ok, []} = Play.public_timeline(campaign.id)

    assert {:error, :not_found} =
             CanonCorrections.correct(campaign.id, session.id, %{
               "kind" => "inventory",
               "target_id" => "sealed-ledger",
               "expected_revision" => state.revision,
               "reason" => "This hidden item must not be available in player corrections.",
               "values" => %{
                 "action" => "edit",
                 "name" => "Exposed ledger",
                 "quantity" => "1",
                 "properties" => "{}"
               }
             })

    before_invalid_edit = Repo.get_by!(State, campaign_id: campaign.id)

    assert {:error, :invalid_value} =
             CanonCorrections.correct(campaign.id, session.id, %{
               "kind" => "inventory",
               "target_id" => "orchard-wine",
               "expected_revision" => before_invalid_edit.revision,
               "reason" => "This malformed correction should be rejected.",
               "values" => %{
                 "action" => "edit",
                 "name" => "Barrel-aged reserve",
                 "quantity" => "3",
                 "properties" => "[]"
               }
             })

    assert Repo.get_by!(State, campaign_id: campaign.id) == before_invalid_edit
    assert length(CanonCorrections.list_receipts(campaign.id)) == 1
  end

  test "resource corrections use the field type and remain private outside tracked public fields" do
    {campaign, session} = play_campaign("The Cellar Ledger")

    insert_panel_field!(campaign.id, %{
      key: "wine_stock",
      panel: "Cellar",
      label: "Wine in storage",
      value_type: :quantity,
      unit: "bottles",
      value: %{"value" => 12}
    })

    insert_panel_field!(campaign.id, %{
      key: "private_reserve",
      panel: "GM notes",
      label: "Hidden reserve",
      value_type: :quantity,
      visibility: :gm_private,
      value: %{"value" => 4}
    })

    assert {:ok, options} = CanonCorrections.options(campaign.id, session.id)
    assert Enum.map(options.resources, & &1.key) == ["wine_stock"]

    assert {:error, :invalid_correction} =
             CanonCorrections.correct(campaign.id, session.id, %{
               "kind" => "resource",
               "target_id" => "private_reserve",
               "expected_revision" => options.revision,
               "reason" => "Try to reach an unlisted resource.",
               "values" => %{"value" => "0"}
             })

    assert {:error, :invalid_value} =
             CanonCorrections.correct(campaign.id, session.id, %{
               "kind" => "resource",
               "target_id" => "wine_stock",
               "expected_revision" => options.revision,
               "reason" => "A quantity must be a whole number.",
               "values" => %{"value" => "twelve"}
             })

    assert {:ok, receipt} =
             CanonCorrections.correct(campaign.id, session.id, %{
               "kind" => "resource",
               "target_id" => "wine_stock",
               "expected_revision" => options.revision,
               "reason" => "A cellar check found seven bottles.",
               "values" => %{"value" => "7"}
             })

    audit = Repo.get_by!(CanonCorrection, campaign_id: campaign.id, sequence: receipt.sequence)
    assert audit.before_state["value"] == 12
    assert audit.after_state["value"] == 7

    assert Repo.get_by!(PanelField, campaign_id: campaign.id, key: "wine_stock").value == %{
             "value" => 7
           }

    state = Repo.get_by!(State, campaign_id: campaign.id)
    assert state.event_sequence == 0
    assert state.elapsed_world_minutes == 0
    assert {:ok, []} = Play.public_timeline(campaign.id)
  end

  test "location corrections use only public people and places and do not create travel time" do
    {campaign, session} = play_campaign("The Vineyard Map", starting_location: nil)
    finca = establish_starting_place!(campaign, "Finca")

    bodega =
      Repo.insert!(
        Place.changeset(%Place{}, %{
          campaign_id: campaign.id,
          place_id: "bodega",
          name: "Bodega",
          visibility: :public,
          facts: %{}
        })
      )

    hidden_place =
      Repo.insert!(
        Place.changeset(%Place{}, %{
          campaign_id: campaign.id,
          place_id: "sealed-room",
          name: "Sealed room",
          visibility: :gm_private,
          facts: %{}
        })
      )

    lyra = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
    Repo.update!(Character.changeset(lyra, %{current_place_id: finca.place_id}))

    Repo.insert!(
      Character.changeset(%Character{}, %{
        campaign_id: campaign.id,
        speaker_id: "npc:hidden",
        name: "Hidden keeper",
        role: :gm,
        current_place_id: hidden_place.place_id
      })
    )

    unplaced =
      Repo.insert!(
        Character.changeset(%Character{}, %{
          campaign_id: campaign.id,
          speaker_id: "npc:unplaced",
          name: "Unplaced cooper",
          role: :gm,
          current_place_id: nil
        })
      )

    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        gm_private_state:
          Map.put(state.gm_private_state, "inventory", [
            %{
              "id" => "hidden-ledger-key",
              "name" => "Hidden ledger key",
              "quantity" => 1,
              "owner_id" => "npc:hidden",
              "visibility" => "gm_private",
              "properties" => %{}
            }
          ])
      })
    )

    assert {:ok, options} = CanonCorrections.options(campaign.id, session.id)
    assert Enum.map(options.places, & &1.id) == ["bodega", finca.place_id]
    assert Enum.map(options.characters, & &1.id) == ["player", "npc:lyra", "npc:unplaced"]
    refute Jason.encode!(options) =~ "Hidden ledger key"
    refute Jason.encode!(options) =~ "sealed-room"

    before_state = Repo.get_by!(State, campaign_id: campaign.id)

    assert {:error, :not_found} =
             CanonCorrections.correct(campaign.id, session.id, %{
               "kind" => "location",
               "target_id" => "npc:hidden",
               "expected_revision" => options.revision,
               "reason" => "Hidden characters are not selectable.",
               "values" => %{"place_id" => bodega.place_id}
             })

    assert {:ok, receipt} =
             CanonCorrections.correct(campaign.id, session.id, %{
               "kind" => "location",
               "target_id" => "npc:unplaced",
               "expected_revision" => options.revision,
               "reason" => "The cooper's last known stop was the Bodega.",
               "values" => %{"place_id" => bodega.place_id}
             })

    unplaced_audit =
      Repo.get_by!(CanonCorrection, campaign_id: campaign.id, sequence: receipt.sequence)

    assert unplaced_audit.reason == "The cooper's last known stop was the Bodega."
    assert unplaced_audit.before_state["place_id"] == nil
    assert unplaced_audit.before_state["place_name"] == nil
    assert unplaced_audit.after_state["place_id"] == bodega.place_id
    assert unplaced_audit.after_state["place_name"] == "Bodega"
    assert Repo.get_by!(Character, id: unplaced.id).current_place_id == bodega.place_id

    assert {:ok, updated_options} = CanonCorrections.options(campaign.id, session.id)

    assert {:ok, lyra_receipt} =
             CanonCorrections.correct(campaign.id, session.id, %{
               "kind" => "location",
               "target_id" => "npc:lyra",
               "expected_revision" => updated_options.revision,
               "reason" => "The keeper remained at the Finca.",
               "values" => %{"place_id" => bodega.place_id}
             })

    audit =
      Repo.get_by!(CanonCorrection, campaign_id: campaign.id, sequence: lyra_receipt.sequence)

    assert audit.before_state["place_id"] == finca.place_id
    assert audit.after_state["place_id"] == bodega.place_id
    assert Repo.get_by!(Character, id: lyra.id).current_place_id == bodega.place_id

    state = Repo.get_by!(State, campaign_id: campaign.id)
    assert state.revision == before_state.revision + 2
    assert state.event_sequence == before_state.event_sequence
    assert state.elapsed_world_minutes == before_state.elapsed_world_minutes
    assert {:ok, []} = Play.public_timeline(campaign.id)

    {:ok, next_session} =
      Campaigns.start_session(Campaigns.get_campaign!(campaign.id), %{title: "A later visit"})

    captured_context = Agent.start_link(fn -> nil end) |> elem(1)

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "corrected-location-context",
               "Look around.",
               provider: fn request ->
                 Agent.update(captured_context, fn _ -> decode_request(request) end)

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
    corrected_character = Enum.find(context["characters"], &(&1["speaker_id"] == "npc:lyra"))

    corrected_unplaced =
      Enum.find(context["characters"], &(&1["speaker_id"] == "npc:unplaced"))

    assert corrected_character["current_place_id"] == bodega.place_id
    assert corrected_unplaced["current_place_id"] == bodega.place_id
  end

  test "canon corrections reject stale forms and any unresolved game master turn" do
    {campaign, session} = play_campaign("The Stale Ledger")
    assert {:ok, options} = CanonCorrections.options(campaign.id, session.id)

    assert {:error, :stale_correction} =
             CanonCorrections.correct(campaign.id, session.id, %{
               "kind" => "inventory",
               "expected_revision" => options.revision + 1,
               "reason" => "A stale view must not overwrite the current state.",
               "values" => %{
                 "action" => "add",
                 "name" => "Test item",
                 "quantity" => "1",
                 "owner_id" => "player"
               }
             })

    turn =
      Repo.insert!(
        Turn.changeset(%Turn{}, %{
          campaign_id: campaign.id,
          session_id: session.id,
          idempotency_key: "correction-open-turn",
          request_hash: String.duplicate("a", 64),
          player_input: "I am still waiting for the GM.",
          status: :pending,
          resolution_phase: :initial,
          attempts: 0
        })
      )

    assert {:error, :turn_in_progress} =
             CanonCorrections.correct(campaign.id, session.id, %{
               "kind" => "inventory",
               "expected_revision" => options.revision,
               "reason" => "Do not change context while the GM works.",
               "values" => %{
                 "action" => "add",
                 "name" => "Test item",
                 "quantity" => "1",
                 "owner_id" => "player"
               }
             })

    assert Repo.get!(Turn, turn.id).status == :pending
    assert Repo.aggregate(CanonCorrection, :count) == 0
    assert {:ok, []} = Play.public_timeline(campaign.id)
  end

  @tag :privacy_guard
  test "rejects exact GM-private facts in public narration before appending events" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert_private_text_rejected(campaign, session, "private-fact-narration", %{
      "narration" => "Lyra's motive is to protect the chart."
    })

    assert_private_text_rejected(campaign, session, "private-fact-public-summary", %{
      "narration" => "The room grows quiet.",
      "memory_update" => %{
        "public_summary" => "Lyra's motive is to protect the chart.",
        "gm_private_summary" => ""
      }
    })

    assert_private_text_rejected(campaign, session, "new-private-fact-summary", %{
      "narration" => "A hidden mark is beneath the north sill.",
      "memory_update" => %{
        "public_summary" => "The observatory remains quiet.",
        "gm_private_summary" => "A hidden mark is beneath the north sill."
      }
    })

    insert_panel_field!(campaign.id, %{
      key: "season",
      panel: "Calendar",
      label: "Season",
      value_type: :text,
      visibility: :public,
      value: %{"value" => "Dormant"}
    })

    assert_private_text_rejected(campaign, session, "private-fact-panel-reason", %{
      "narration" => "The season changes.",
      "panel_changes" => [
        %{
          "type" => "set",
          "key" => "season",
          "value" => "Awakening",
          "reason" => "The truth is to protect the chart."
        }
      ]
    })
  end

  @tag :privacy_guard
  test "rejects a hidden-place name in public NPC dialogue" do
    {campaign, session} = play_campaign("The Glass Observatory")

    Repo.insert!(
      Place.changeset(%Place{}, %{
        campaign_id: campaign.id,
        place_id: "saffron-vault",
        name: "Saffron Vault",
        visibility: :gm_private,
        facts: %{}
      })
    )

    Repo.insert!(
      Character.changeset(%Character{}, %{
        campaign_id: campaign.id,
        speaker_id: "npc:orin",
        name: "Orin Vale",
        role: :gm,
        visible_facts: %{},
        gm_private_facts: %{},
        current_place_id: "saffron-vault"
      })
    )

    assert_private_text_rejected(campaign, session, "private-place-dialogue", %{
      "dialogue" => [%{"speaker_id" => "npc:lyra", "text" => "The map points to Saffron Vault."}]
    })

    assert_private_text_rejected(campaign, session, "hidden-character-name", %{
      "narration" => "Orin Vale waits beyond the observatory door."
    })
  end

  @tag :privacy_guard
  test "rejects secret inventory names in public character activity" do
    {campaign, session} = play_campaign("The Glass Observatory")
    state = Repo.get_by!(State, campaign_id: campaign.id)

    secret_item = %{
      "id" => "moonstone-key",
      "name" => "Moonstone key",
      "quantity" => 1,
      "unit" => "item",
      "category" => "relic",
      "owner_id" => "npc:lyra",
      "visibility" => "gm_private",
      "properties" => %{}
    }

    Repo.update!(
      State.changeset(state, %{
        gm_private_state: Map.put(state.gm_private_state, "inventory", [secret_item])
      })
    )

    assert_private_text_rejected(campaign, session, "private-inventory-activity", %{
      "activities" => [%{"speaker_id" => "npc:lyra", "text" => "Lyra hides the Moonstone key."}]
    })

    assert_private_text_rejected(campaign, session, "private-item-update", %{
      "activities" => [
        %{"speaker_id" => "npc:lyra", "text" => "The mark reads beneath the north sill."}
      ],
      "inventory_changes" => [
        %{
          "type" => "update",
          "item_id" => "moonstone-key",
          "properties" => %{"inscription" => "beneath the north sill"},
          "reason" => "The inscription becomes legible."
        }
      ]
    })
  end

  @tag :privacy_guard
  test "rejects a hidden inventory phrase in a proposed public inventory reason" do
    {campaign, session} = play_campaign("The Glass Observatory")
    state = Repo.get_by!(State, campaign_id: campaign.id)

    hidden_item = %{
      "id" => "moonstone-key",
      "name" => "Moonstone key",
      "quantity" => 1,
      "unit" => "item",
      "category" => "relic",
      "description" => "beneath the north sill",
      "owner_id" => "npc:lyra",
      "visibility" => "gm_private",
      "properties" => %{}
    }

    Repo.update!(
      State.changeset(state, %{
        gm_private_state: Map.put(state.gm_private_state, "inventory", [hidden_item])
      })
    )

    assert_private_text_rejected(campaign, session, "private-inventory-reason", %{
      "inventory_changes" => [
        %{
          "type" => "add",
          "item" => %{
            "id" => "public-brass-key",
            "name" => "Brass key",
            "quantity" => 1,
            "owner_id" => "player",
            "visibility" => "public",
            "properties" => %{}
          },
          "reason" => "The contents were found beneath the north sill."
        }
      ]
    })

    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert projection.inventory == []
    refute Jason.encode!(projection) =~ "beneath the north sill"
    refute Jason.encode!(projection) =~ "public-brass-key"
  end

  @tag :privacy_guard
  test "an explicit public state reveal permits the same phrase now and in later turns" do
    {campaign, session} = play_campaign("The Glass Observatory")

    proposal =
      ordinary_proposal(%{
        "narration" => "The truth is now public: protect the chart.",
        "public_changes" => %{"revealed_motive" => "protect the chart"},
        "memory_update" => %{
          "public_summary" => "It is now public that Lyra wants to protect the chart.",
          "gm_private_summary" => ""
        }
      })

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "private-fact-revealed",
               "Ask Lyra what she knows.",
               provider: fn _request -> {:ok, Jason.encode!(proposal)} end,
               model: "test-model"
             )

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "private-fact-after-reveal",
               "Discuss the motive.",
               provider:
                 ordinary_provider(%{
                   "narration" => "You both agree to protect the chart."
                 }),
               model: "test-model"
             )

    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert projection.world["revealed_motive"] == "protect the chart"
  end

  @tag :privacy_guard
  test "guards private objective details while allowing generic one-word prose" do
    {campaign, session} = play_campaign("The Glass Observatory")
    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        gm_private_state: Map.put(state.gm_private_state, "mood", "calm")
      })
    )

    Repo.insert!(
      Objective.changeset(%Objective{}, %{
        campaign_id: campaign.id,
        objective_id: "sealed-pact",
        title: "Sealed pact",
        details: "The witness hid the northern charter beneath the old press.",
        status: :open,
        visibility: :gm_private
      })
    )

    insert_panel_field!(campaign.id, %{
      key: "gm_signal",
      panel: "GM notes",
      label: "Hidden signal",
      value_type: :text,
      visibility: :gm_private,
      value: %{"value" => "The silver bell rings at noon."}
    })

    assert_private_text_rejected(campaign, session, "private-objective-detail", %{
      "narration" => "The witness hid the northern charter beneath the old press."
    })

    assert_private_text_rejected(campaign, session, "private-panel-value", %{
      "narration" => "The silver bell rings at noon."
    })

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "generic-private-token",
               "Wait for the wind.",
               provider:
                 ordinary_provider(%{
                   "narration" => "Calm settles over the observatory."
                 }),
               model: "test-model"
             )
  end

  test "a narrative-only turn keeps unchanged scene facts in the canonical board" do
    {campaign, session} = play_campaign("The Glass Observatory")
    state = Repo.get_by!(State, campaign_id: campaign.id)

    public_state =
      state.public_state
      |> Map.delete("world_time")
      |> Map.merge(%{
        "date" => "Harvest Day 1",
        "time" => "Midmorning",
        "weather" => "Cool mist"
      })

    Repo.update!(State.changeset(state, %{public_state: public_state}))

    captured_request = Agent.start_link(fn -> nil end) |> elem(1)
    narration = "Lyra lowers the brass shutter and waits for your answer."

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "concise-stable-scene",
               "Ask Lyra to wait while you finish writing.",
               provider: fn request ->
                 Agent.update(captured_request, fn _ -> decode_request(request) end)

                 proposal =
                   ordinary_proposal(%{
                     "narration" => narration,
                     "dialogue" => [],
                     "activities" => [],
                     "public_changes" => %{},
                     "private_changes" => %{},
                     "panel_changes" => [],
                     "character_updates" => [],
                     "inventory_changes" => [],
                     "location_changes" => [],
                     "objective_changes" => [],
                     "continuity_changes" => []
                   })

                 {:ok, Jason.encode!(proposal)}
               end,
               model: "test-model"
             )

    context = Agent.get(captured_request, & &1)
    assert context["world"]["public"]["date"] == "Harvest Day 1"
    assert context["world"]["public"]["time"] == "Midmorning"
    assert context["world"]["public"]["weather"] == "Cool mist"

    assert {:ok, events} = Play.public_timeline(campaign.id)
    assert Enum.map(events, & &1.event_type) == [:player_action, :gm_narration]

    gm_event = List.last(events)
    assert gm_event.payload["text"] == narration
    assert gm_event.game_time == %{"date" => "Harvest Day 1", "time" => "Midmorning"}

    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert projection.world["date"] == "Harvest Day 1"
    assert projection.world["time"] == "Midmorning"
    assert projection.world["weather"] == "Cool mist"
    lyra = Enum.find(projection.characters, &(&1.speaker_id == "npc:lyra"))
    assert lyra.visible_activity == nil
  end

  test "keeps each present NPC's voice notes attached to its speaker in the provider request" do
    campaign =
      campaign_fixture(%{
        starting_location: "The Finca",
        gm_characters: [
          %{
            speaker_id: "npc:marcel",
            name: "Marcel",
            starting_place: "The Finca",
            visible_facts: %{"description" => "A French beaver cook from Lyon."},
            voice_guidance: %{
              "accent_dialect" =>
                "French from Lyon; suggest naturally through cadence, never spelling.",
              "vocabulary" => "Uses kitchen and cellar words.",
              "mannerisms" => "Taps his wooden spoon against his apron while thinking."
            }
          },
          %{
            speaker_id: "npc:ines",
            name: "Ines",
            starting_place: "The Finca",
            visible_facts: %{"description" => "A precise keeper of the vineyard accounts."},
            voice_guidance: %{
              "cadence" => "Measured, complete sentences with a pause before a warning.",
              "vocabulary" => "Uses figures, ledgers, and harvest terms.",
              "mannerisms" => "Squares the corners of any paper within reach."
            }
          }
        ]
      })

    [session] = campaign.sessions
    captured = Agent.start_link(fn -> nil end) |> elem(1)

    provider = fn request ->
      Agent.update(captured, fn _ -> {request, decode_request(request)} end)

      proposal =
        ordinary_proposal(%{
          "dialogue" => [
            %{"speaker_id" => "npc:marcel", "text" => "The cellar wants a little patience."},
            %{"speaker_id" => "npc:ines", "text" => "We have enough wine for the tasting."}
          ],
          "activities" => [],
          "character_updates" => []
        })

      {:ok, Jason.encode!(proposal)}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "separate-voices",
               "Ask what remains to do.",
               provider: provider,
               model: "test-model"
             )

    {request, request_context} = Agent.get(captured, & &1)
    characters = Map.new(request_context["characters"], &{&1["speaker_id"], &1})
    instructions = String.replace(request.instructions, ~r/\s+/, " ")

    assert instructions =~ "Distinct NPC voices:"
    assert instructions =~ "SENSORY AUTHORITY: The GM owns external and sensory facts."
    assert instructions =~ "Never ask the player to invent how the world or an object tastes"

    assert instructions =~ "ask for their interpretation"

    assert instructions =~
             "use each speaker_id's own accent/dialect, vocabulary, cadence, quirks, and mannerisms"

    assert instructions =~
             "never blend profiles or flatten multiple speakers into one generic voice"

    assert instructions =~ "natural word choice and rhythm, never phonetic spelling or caricature"

    assert characters["npc:marcel"]["name"] == "Marcel"

    assert characters["npc:marcel"]["voice_guidance"] == %{
             "accent_dialect" =>
               "French from Lyon; suggest naturally through cadence, never spelling.",
             "vocabulary" => "Uses kitchen and cellar words.",
             "mannerisms" => "Taps his wooden spoon against his apron while thinking."
           }

    assert characters["npc:ines"]["name"] == "Ines"

    assert characters["npc:ines"]["voice_guidance"] == %{
             "cadence" => "Measured, complete sentences with a pause before a warning.",
             "vocabulary" => "Uses figures, ledgers, and harvest terms.",
             "mannerisms" => "Squares the corners of any paper within reach."
           }

    assert characters["npc:marcel"]["current_place"]["name"] == "The Finca"
    assert characters["npc:ines"]["current_place"]["name"] == "The Finca"
  end

  test "sends a scene-beat handoff rule and keeps a complete NPC exchange in one turn" do
    campaign =
      campaign_fixture(%{
        starting_location: "Moon Orchard Tasting Room",
        gm_characters: [
          %{
            speaker_id: "npc:lyra",
            name: "Lyra",
            starting_place: "Moon Orchard Tasting Room"
          },
          %{
            speaker_id: "npc:sera",
            name: "Sera",
            starting_place: "Moon Orchard Tasting Room"
          }
        ]
      })

    [session] = campaign.sessions
    test_pid = self()

    provider = fn request ->
      send(test_pid, {:scene_beat_request, request.instructions, decode_request(request)})

      proposal =
        ordinary_proposal(%{
          "narration" =>
            "Lanternlight catches the cordial's garnet edge; a sharp plum aroma opens into a dry, peppery finish. Both women taste in silence, then glance toward you.",
          "dialogue" => [
            %{"speaker_id" => "npc:lyra", "text" => "The pepper stays longer than the fruit."},
            %{"speaker_id" => "npc:sera", "text" => "And the finish changes as it cools."}
          ],
          "activities" => [],
          "character_updates" => []
        })

      {:ok, Jason.encode!(proposal)}
    end

    assert {:ok, %{status: :completed} = turn} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "complete-tasting-beat",
               "I taste the cordial and listen.",
               provider: provider,
               model: "test-model"
             )

    assert_receive {:scene_beat_request, instructions, context}, 1_000
    normalized_instructions = String.replace(instructions, ~r/\s+/, " ")
    assert normalized_instructions =~ "Before handoff, complete the immediate scene beat"

    assert normalized_instructions =~
             "Don't stop at one NPC line when a natural response or consequence remains"

    assert context["interaction_mode"] == "action"

    assert {:ok, events} = Play.public_timeline(campaign.id)
    turn_events = Enum.filter(events, &(&1.turn_id == turn.id))

    assert Enum.map(turn_events, & &1.event_type) == [
             :player_action,
             :gm_narration,
             :npc_dialogue,
             :npc_dialogue
           ]

    assert Enum.map(Enum.drop(turn_events, 1), & &1.payload["text"]) == [
             "Lanternlight catches the cordial's garnet edge; a sharp plum aroma opens into a dry, peppery finish. Both women taste in silence, then glance toward you.",
             "The pepper stays longer than the fruit.",
             "And the finish changes as it cools."
           ]
  end

  test "loads a module provider before checking its callback" do
    {campaign, session} = play_campaign("The Glass Observatory")
    provider = Storyteller.PlayTest.LazyModuleProvider

    on_exit(fn -> :persistent_term.erase({provider, :called}) end)

    :code.purge(provider)
    :code.delete(provider)
    refute function_exported?(provider, :stream_response, 1)

    turn =
      Play.submit_turn(
        campaign.id,
        session.id,
        "lazy-module-provider",
        "I listen to the night wind.",
        provider: provider
      )

    assert :persistent_term.get({provider, :called}, false)
    assert {:ok, %{status: :completed}} = turn

    assert function_exported?(provider, :stream_response, 1)
  end

  test "legacy world time aliases collapse consistently in the next GM context and persisted state" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "set-early-time",
               "The orchard wakes at dawn.",
               provider: ordinary_provider(%{"public_changes" => %{"time" => "Early morning"}}),
               model: "test-model"
             )

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "legacy-world-time-change",
               "The morning advances.",
               provider:
                 ordinary_provider(%{"public_changes" => %{"world_time" => "Midmorning"}}),
               model: "test-model"
             )

    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        public_state:
          Map.merge(state.public_state, %{
            "time" => "Early morning",
            "world_time" => "Stale legacy value"
          })
      })
    )

    latest_state_change =
      Repo.one!(
        from event in Event,
          where:
            event.campaign_id == ^campaign.id and event.event_type == :state_change and
              event.visibility == :public,
          order_by: [desc: event.sequence],
          limit: 1
      )

    Repo.update!(
      Event.changeset(latest_state_change, %{
        payload: %{"changes" => %{"world_time" => "Midmorning"}}
      })
    )

    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert projection.world["time"] == "Midmorning"
    refute Map.has_key?(projection.world, "world_time")

    first_context = Agent.start_link(fn -> nil end) |> elem(1)

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "canonical-world-time",
               "Watch the orchard wake.",
               provider: fn request ->
                 context = decode_request(request)
                 Agent.update(first_context, fn _ -> context end)

                 {:ok,
                  Jason.encode!(
                    ordinary_proposal(%{
                      "public_changes" => %{"time" => "Late morning"}
                    })
                  )}
               end,
               model: "test-model"
             )

    context = Agent.get(first_context, & &1)
    assert context["world"]["public"]["time"] == "Midmorning"
    refute Map.has_key?(context["world"]["public"], "world_time")

    canonical_state = Repo.get_by!(State, campaign_id: campaign.id)
    assert canonical_state.public_state["time"] == "Late morning"
    refute Map.has_key?(canonical_state.public_state, "world_time")

    next_context = Agent.start_link(fn -> nil end) |> elem(1)

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "confirm-canonical-world-time",
               "Continue into the day.",
               provider: fn request ->
                 Agent.update(next_context, fn _ -> decode_request(request) end)
                 {:ok, Jason.encode!(ordinary_proposal())}
               end,
               model: "test-model"
             )

    next = Agent.get(next_context, & &1)
    assert next["world"]["public"]["time"] == "Late morning"
    refute Map.has_key?(next["world"]["public"], "world_time")
  end

  test "conflicting aliases in one world-time proposal are rejected atomically" do
    {campaign, session} = play_campaign("The Glass Observatory")
    state_before = Repo.get_by!(State, campaign_id: campaign.id)

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "conflicting-world-time",
               "Wait for the watch to change.",
               provider:
                 ordinary_provider(%{
                   "public_changes" => %{
                     "time" => "Early morning",
                     "world_time" => "Midmorning"
                   }
                 }),
               model: "test-model"
             )

    assert Repo.get_by!(State, campaign_id: campaign.id).public_state == state_before.public_state
    assert {:ok, []} = Play.public_timeline(campaign.id)
  end

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
    terrace = establish_starting_place!(campaign, "East terrace")
    lyra = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
    Repo.update!(Character.changeset(lyra, %{current_place_id: terrace.place_id}))
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
      },
      {
        "gm-canonical-location-alias",
        %{
          "character_updates" => [
            %{
              "speaker_id" => "npc:lyra",
              "visible_facts" => %{"current_place_id" => "somewhere-else"}
            }
          ]
        }
      },
      {
        "gm-private-canonical-location-alias",
        %{
          "character_updates" => [
            %{
              "speaker_id" => "npc:lyra",
              "gm_private_facts" => %{"current_location" => "The hidden cistern"}
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
    {campaign, session} = play_campaign("The Glass Observatory", starting_location: nil)
    upper_dome = establish_starting_place!(campaign, "Upper dome")
    lyra = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
    Repo.update!(Character.changeset(lyra, %{current_place_id: upper_dome.place_id}))

    request_context = Agent.start_link(fn -> nil end) |> elem(1)

    provider = fn request ->
      context = decode_request(request)
      Agent.update(request_context, fn _ -> context end)

      {:ok,
       Jason.encode!(
         ordinary_proposal(%{
           "location_changes" => []
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

  test "continuity entries persist with event provenance beyond the recent window and across sessions" do
    {campaign, session} = play_campaign("The Glass Observatory")
    captured_context = Agent.start_link(fn -> nil end) |> elem(1)

    first_provider = fn request ->
      Agent.update(captured_context, fn _ -> decode_request(request) end)

      {:ok,
       Jason.encode!(
         ordinary_proposal(%{
           "continuity_changes" => [
             %{
               "type" => "create",
               "entry" => %{
                 "entry_id" => "lyra-promise",
                 "kind" => "commitment",
                 "title" => "Lyra's promise",
                 "details" =>
                   "Lyra promised to bring Mira the eastern star chart after the watch.",
                 "visibility" => "public"
               },
               "reason" => "Lyra makes this promise in the scene."
             },
             %{
               "type" => "create",
               "entry" => %{
                 "entry_id" => "lyra-trust",
                 "kind" => "relationship",
                 "title" => "Mira and Lyra",
                 "details" => "Lyra trusts Mira with the observatory keys.",
                 "visibility" => "public"
               },
               "reason" => "Lyra entrusts the keys to Mira."
             },
             %{
               "type" => "create",
               "entry" => %{
                 "entry_id" => "altered-chart-secret",
                 "kind" => "fact",
                 "title" => "The chart was altered",
                 "details" =>
                   "The keeper secretly changed the eastern star chart before Mira arrived.",
                 "visibility" => "gm_private"
               },
               "reason" => "The GM establishes a hidden cause for later play."
             }
           ]
         })
       )}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "continuity-seed",
               "Lyra promises to bring me the chart.",
               provider: first_provider
             )

    public_projection = Play.public_projection(campaign.id) |> elem(1)
    public_entries = Map.new(public_projection.continuity_entries, &{&1.entry_id, &1})

    assert Map.keys(public_entries) |> Enum.sort() == ["lyra-promise", "lyra-trust"]
    refute Jason.encode!(public_projection) =~ "altered-chart-secret"
    refute Jason.encode!(public_projection) =~ "The keeper secretly changed"

    promise = Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, entry_id: "lyra-promise")
    introduced_event = Repo.get!(Event, promise.introduced_by_event_id)
    assert promise.source_event_id == introduced_event.id
    assert introduced_event.visibility == :public
    assert introduced_event.payload["continuity_changes"]
    assert introduced_event.game_time == %{"time" => "First watch"}

    {:ok, next_session} = Campaigns.start_session(campaign)

    for index <- 1..20 do
      provider = fn request ->
        context = decode_request(request)
        if index == 20, do: Agent.update(captured_context, fn _ -> context end)
        {:ok, Jason.encode!(ordinary_proposal())}
      end

      assert {:ok, %{status: :completed}} =
               Play.submit_turn(
                 campaign.id,
                 next_session.id,
                 "continuity-window-#{index}",
                 "Continue the observatory work, beat #{index}.",
                 provider: provider
               )
    end

    context = Agent.get(captured_context, & &1)
    public_context_entries = Map.new(context["continuity"]["public"], &{&1["entry_id"], &1})
    private_context_entries = Map.new(context["continuity"]["gm_private"], &{&1["entry_id"], &1})

    assert length(context["history"]) <= 40
    assert List.last(context["history"])["session_id"] == next_session.id

    assert Enum.any?(context["history"], fn event ->
             String.contains?(event["payload"]["text"] || "", "beat 19")
           end)

    refute Enum.any?(context["history"], &(&1["payload"] |> Jason.encode!() =~ "Lyra's promise"))
    assert public_context_entries["lyra-promise"]["source_sequence"] == introduced_event.sequence
    assert public_context_entries["lyra-promise"]["details"] =~ "eastern star chart"
    assert private_context_entries["altered-chart-secret"]["details"] =~ "secretly changed"
    refute Jason.encode!(context["continuity"]["public"]) =~ "secretly changed"

    trust_before =
      Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, entry_id: "lyra-trust")

    update_provider =
      ordinary_provider(%{
        "continuity_changes" => [
          %{
            "type" => "update",
            "entry_id" => "lyra-promise",
            "status" => "resolved",
            "reason" => "Lyra delivered the chart to Mira."
          },
          %{
            "type" => "update",
            "entry_id" => "lyra-trust",
            "details" => "Lyra trusts Mira with the observatory keys and the eastern chart.",
            "reason" => "Lyra now shares the chart as well as the keys."
          }
        ]
      })

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "resolve-continuity",
               "Lyra gives me the chart.",
               provider: update_provider
             )

    resolved = Repo.get!(ContinuityEntry, promise.id)
    resolution_event = Repo.get!(Event, resolved.source_event_id)
    assert resolved.status == :resolved
    assert resolution_event.visibility == :public

    assert Enum.any?(resolution_event.payload["continuity_changes"], fn change ->
             change["entry"]["entry_id"] == "lyra-promise" and
               change["entry"]["status"] == "resolved"
           end)

    refute Jason.encode!(resolution_event.payload) =~ "Lyra delivered the chart to Mira."
    trust = Repo.get!(ContinuityEntry, trust_before.id)
    assert trust.details =~ "eastern chart"
    assert trust.introduced_by_event_id == trust_before.introduced_by_event_id
    assert trust.source_event_id != trust_before.source_event_id

    public_entries =
      Play.public_projection(campaign.id) |> elem(1) |> Map.fetch!(:continuity_entries)

    assert Enum.find(public_entries, &(&1.entry_id == "lyra-trust")).details =~ "eastern chart"

    refute Enum.any?(
             Play.public_projection(campaign.id) |> elem(1) |> Map.fetch!(:continuity_entries),
             &(&1.entry_id == "lyra-promise")
           )

    {:ok, public_timeline} = Play.public_timeline(campaign.id)

    promise_timeline_events =
      for event <- public_timeline,
          change <- event.payload["continuity_changes"] || [],
          change["entry"]["entry_id"] == "lyra-promise",
          do: {event, change}

    assert length(promise_timeline_events) == 1
    [{promise_timeline_event, promise_timeline_change}] = promise_timeline_events
    assert promise_timeline_event.sequence == resolution_event.sequence
    assert promise_timeline_change["type"] == "update"
    assert promise_timeline_change["entry"]["status"] == "resolved"
    assert promise_timeline_change["entry"]["title"] == "Lyra's promise"
    refute Jason.encode!(promise_timeline_event.payload) =~ "Lyra delivered the chart to Mira."
    refute Jason.encode!(public_timeline) =~ "The keeper secretly changed"

    assert Jason.encode!(public_timeline) =~
             "Lyra trusts Mira with the observatory keys and the eastern chart."

    for index <- 1..20 do
      provider = fn request ->
        context = decode_request(request)
        if index == 20, do: Agent.update(captured_context, fn _ -> context end)
        {:ok, Jason.encode!(ordinary_proposal())}
      end

      assert {:ok, %{status: :completed}} =
               Play.submit_turn(
                 campaign.id,
                 next_session.id,
                 "closed-continuity-window-#{index}",
                 "Continue the observatory work after the promise is fulfilled, beat #{index}.",
                 provider: provider
               )
    end

    closed_context = Agent.get(captured_context, & &1)

    closed_context_entries =
      Map.new(closed_context["continuity"]["public"], &{&1["entry_id"], &1})

    closed_promise = closed_context_entries["lyra-promise"]

    assert length(closed_context["history"]) <= 40
    refute Enum.any?(closed_context["history"], &(&1["sequence"] == resolution_event.sequence))
    assert closed_promise["kind"] == "commitment"
    assert closed_promise["title"] == "Lyra's promise"
    assert closed_promise["details"] =~ "eastern star chart"
    assert closed_promise["status"] == "resolved"
    assert closed_promise["visibility"] == "public"
    assert closed_promise["source_sequence"] == resolution_event.sequence
    refute Jason.encode!(closed_context["continuity"]["public"]) =~ "secretly changed"

    before_recreation = Repo.get_by!(State, campaign_id: campaign.id)
    timeline_before_recreation = Play.public_timeline(campaign.id)

    recreation_provider = fn request ->
      context = decode_request(request)
      Agent.update(captured_context, fn _ -> context end)

      {:ok,
       Jason.encode!(
         ordinary_proposal(%{
           "continuity_changes" => [
             %{
               "type" => "create",
               "entry" => %{
                 "entry_id" => "lyra-promise",
                 "kind" => "commitment",
                 "title" => "Lyra's promise",
                 "details" => "Lyra will bring Mira a chart again.",
                 "visibility" => "public"
               },
               "reason" => "Recreate the resolved promise."
             }
           ]
         })
       )}
    end

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "recreate-resolved-continuity",
               "Ask Lyra to renew her promise.",
               provider: recreation_provider
             )

    attempted_context = Agent.get(captured_context, & &1)
    attempted_entries = Map.new(attempted_context["continuity"]["public"], &{&1["entry_id"], &1})
    assert attempted_entries["lyra-promise"]["status"] == "resolved"

    assert Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, entry_id: "lyra-promise") ==
             resolved

    assert continuity_entry_count(campaign.id) == 3
    assert Repo.get_by!(State, campaign_id: campaign.id).revision == before_recreation.revision
    assert ^timeline_before_recreation = Play.public_timeline(campaign.id)
  end

  test "continuity ledger bounds total retained records and rejects overflow atomically" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "continuity-cap-seed",
               "Lyra makes one durable promise.",
               provider:
                 ordinary_provider(%{
                   "continuity_changes" => [
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "cap-active",
                         "kind" => "commitment",
                         "title" => "The active promise",
                         "details" => "Lyra will bring Mira the chart.",
                         "visibility" => "public"
                       },
                       "reason" => "Lyra says she will bring the chart."
                     }
                   ]
                 })
             )

    source_event =
      Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, entry_id: "cap-active")
      |> then(&Repo.get!(Event, &1.source_event_id))

    for index <- 1..99 do
      assert {:ok, _entry} =
               %ContinuityEntry{}
               |> ContinuityEntry.changeset(%{
                 campaign_id: campaign.id,
                 entry_id: "cap-closed-#{index}",
                 kind: :fact,
                 title: "Retained fact #{index}",
                 details: "A bounded historical fact.",
                 status: :resolved,
                 visibility: :gm_private,
                 introduced_by_event_id: source_event.id,
                 source_event_id: source_event.id
               })
               |> Repo.insert()
    end

    assert continuity_entry_count(campaign.id) == 100
    before = Repo.get_by!(State, campaign_id: campaign.id)
    timeline_before = Play.public_timeline(campaign.id)

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "continuity-overflow",
               "Establish another durable fact.",
               model: "test-model",
               context_input_byte_budget: 50_000,
               provider:
                 ordinary_provider(%{
                   "continuity_changes" => [
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "cap-overflow",
                         "kind" => "fact",
                         "title" => "An overflow fact",
                         "details" => "This one exceeds the retained ledger cap.",
                         "visibility" => "public"
                       },
                       "reason" => "A new fact would exceed the campaign ledger bound."
                     }
                   ]
                 })
             )

    assert continuity_entry_count(campaign.id) == 100
    assert Repo.get_by(ContinuityEntry, campaign_id: campaign.id, entry_id: "cap-overflow") == nil
    assert Repo.get_by!(State, campaign_id: campaign.id).revision == before.revision
    assert ^timeline_before = Play.public_timeline(campaign.id)
  end

  test "private continuity entries cannot be promoted by an update and invalid batches roll back" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "private-continuity-seed",
               "The keeper hides the altered chart.",
               provider:
                 ordinary_provider(%{
                   "continuity_changes" => [
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "private-chart-truth",
                         "kind" => "fact",
                         "title" => "The chart is false",
                         "details" => "The keeper altered the chart before Mira arrived.",
                         "visibility" => "gm_private"
                       },
                       "reason" => "The keeper's secret drives a later reveal."
                     }
                   ]
                 })
             )

    entry =
      Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, entry_id: "private-chart-truth")

    before = Repo.get_by!(State, campaign_id: campaign.id)
    {:ok, timeline_before} = Play.public_timeline(campaign.id)

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "attempt-private-promotion",
               "Reveal what the keeper knows.",
               provider:
                 ordinary_provider(%{
                   "continuity_changes" => [
                     %{
                       "type" => "update",
                       "entry_id" => "private-chart-truth",
                       "title" => "The chart is false",
                       "status" => "resolved",
                       "visibility" => "public",
                       "reason" => "The player guessed the truth."
                     }
                   ]
                 })
             )

    assert Repo.get!(ContinuityEntry, entry.id) == entry
    assert Repo.get_by!(State, campaign_id: campaign.id).revision == before.revision
    assert Play.public_projection(campaign.id) |> elem(1) |> Map.fetch!(:continuity_entries) == []
    assert {:ok, ^timeline_before} = Play.public_timeline(campaign.id)
    refute Jason.encode!(timeline_before) =~ "private-chart-truth"
    refute Jason.encode!(timeline_before) =~ "The keeper altered the chart"

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "invalid-continuity-batch",
               "Make a promise and revise it.",
               provider:
                 ordinary_provider(%{
                   "continuity_changes" => [
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "uncommitted-promise",
                         "kind" => "commitment",
                         "title" => "An uncommitted promise",
                         "details" => "This entry must not be partially saved.",
                         "visibility" => "public"
                       },
                       "reason" => "A valid first operation."
                     },
                     %{
                       "type" => "update",
                       "entry_id" => "missing-entry",
                       "status" => "resolved",
                       "reason" => "This later operation must fail the batch."
                     }
                   ]
                 })
             )

    assert Repo.get_by(ContinuityEntry, campaign_id: campaign.id, entry_id: "uncommitted-promise") ==
             nil

    assert Play.public_projection(campaign.id) |> elem(1) |> Map.fetch!(:continuity_entries) == []
    assert {:ok, ^timeline_before} = Play.public_timeline(campaign.id)
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

  test "the finca to bodega route computes 40 minutes and reaches the next GM context" do
    {campaign, session} = play_campaign("The Finca and Bodega", starting_location: nil)
    finca = establish_starting_place!(campaign, "Finca")
    lyra = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
    Repo.update!(Character.changeset(lyra, %{current_place_id: finca.place_id}))

    location_changes = [
      %{
        "type" => "create_place",
        "place" => %{
          "place_id" => "bodega",
          "name" => "Bodega",
          "visibility" => "public",
          "facts" => %{}
        },
        "reason" => "The winery at the bodega is established."
      },
      %{
        "type" => "move_character",
        "speaker_id" => "player",
        "place_id" => "bodega",
        "reason" => "The player travels to the bodega."
      }
    ]

    travel_changes = [
      %{
        "type" => "create_connection",
        "place_a_id" => finca.place_id,
        "place_b_id" => "bodega",
        "travel_minutes" => 40,
        "scene_relevance" => "A winding road connects the finca and bodega.",
        "visibility" => "public",
        "reason" => "The bodega is a forty-minute trip from the finca."
      }
    ]

    proposal =
      ordinary_proposal(%{
        "narration" => "After the forty-minute ride, the bodega comes into view.",
        "dialogue" => [],
        "activities" => [],
        "character_updates" => [],
        "location_changes" => location_changes,
        "travel_changes" => travel_changes
      })

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(campaign.id, session.id, "finca-to-bodega", "Travel to the bodega.",
               provider: fn _request -> {:ok, Jason.encode!(proposal)} end,
               model: "test-model"
             )

    bodega = Repo.get_by!(Place, campaign_id: campaign.id, place_id: "bodega")
    player = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")
    assert player.current_place_id == bodega.place_id

    connection =
      Repo.get_by!(PlaceConnection,
        campaign_id: campaign.id,
        place_a_id: Enum.min([finca.place_id, bodega.place_id]),
        place_b_id: Enum.max([finca.place_id, bodega.place_id])
      )

    assert connection.travel_minutes == 40

    assert {:ok, events} = Play.public_timeline(campaign.id)

    movement =
      events
      |> Enum.flat_map(&Map.get(&1.payload, "location_changes", []))
      |> Enum.find(&(&1["speaker_id"] == "player" and &1["place_id"] == "bodega"))

    assert movement["travel_minutes"] == 40

    state = Repo.get_by!(State, campaign_id: campaign.id)
    assert state.elapsed_world_minutes == 40
    assert state.elapsed_world_anchor == %{"time" => "First watch"}

    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert projection.elapsed_world_clock.minutes_since_anchor == 40

    assert {:ok, next_session} =
             Campaigns.start_session(Campaigns.get_campaign!(campaign.id), %{
               title: "After the road"
             })

    request_context = Agent.start_link(fn -> nil end) |> elem(1)

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "bodega-scene-context",
               "Look around.",
               provider: fn request ->
                 Agent.update(request_context, fn _ -> decode_request(request) end)

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

    context = Agent.get(request_context, & &1)
    assert Enum.any?(context["travel_connections"]["public"], &(&1["travel_minutes"] == 40))
    assert context["elapsed_world_clock"]["total_minutes"] == 40

    assert Enum.any?(context["travel_connections"]["public_routes"], fn route ->
             route["travel_minutes"] == 40 and finca.place_id in route["place_ids"] and
               bodega.place_id in route["place_ids"]
           end)
  end

  test "a finca employee cannot speak or act at the bodega until canonical travel moves them across sessions" do
    {campaign, first_session} =
      play_campaign("The Finca and Bodega Presence", starting_location: nil)

    finca = establish_starting_place!(campaign, "Finca")
    lyra = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
    Repo.update!(Character.changeset(lyra, %{current_place_id: finca.place_id}))

    arrive_at_bodega =
      ordinary_proposal(%{
        "narration" => "The road winds for forty minutes before the bodega comes into view.",
        "dialogue" => [],
        "activities" => [],
        "character_updates" => [],
        "location_changes" => [
          %{
            "type" => "create_place",
            "place" => %{
              "place_id" => "bodega",
              "name" => "Bodega",
              "visibility" => "public",
              "facts" => %{"kind" => "winery"}
            },
            "reason" => "The bodega is established as a distinct place from the Finca."
          },
          %{
            "type" => "move_character",
            "speaker_id" => "player",
            "place_id" => "bodega",
            "reason" => "The player travels from the Finca to the bodega."
          }
        ],
        "travel_changes" => [
          %{
            "type" => "create_connection",
            "place_a_id" => finca.place_id,
            "place_b_id" => "bodega",
            "travel_minutes" => 40,
            "scene_relevance" =>
              "The winding road between the Finca and the bodega takes forty minutes.",
            "visibility" => "public",
            "reason" => "The bodega is forty minutes from the Finca."
          }
        ]
      })

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               first_session.id,
               "player-travels-to-bodega",
               "I travel from the Finca to the bodega.",
               provider: fn _request -> {:ok, Jason.encode!(arrive_at_bodega)} end,
               model: "test-model"
             )

    bodega = Repo.get_by!(Place, campaign_id: campaign.id, place_id: "bodega")
    player = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")
    lyra = Repo.get_by!(Character, id: lyra.id)
    assert player.current_place_id == bodega.place_id
    assert lyra.current_place_id == finca.place_id

    connection =
      Repo.get_by!(PlaceConnection,
        campaign_id: campaign.id,
        place_a_id: Enum.min([finca.place_id, bodega.place_id]),
        place_b_id: Enum.max([finca.place_id, bodega.place_id])
      )

    assert connection.travel_minutes == 40
    assert Repo.get_by!(State, campaign_id: campaign.id).elapsed_world_minutes == 40

    assert {:ok, later_session} =
             Campaigns.start_session(Campaigns.get_campaign!(campaign.id), %{
               title: "The next visit"
             })

    captured_contexts = Agent.start_link(fn -> [] end) |> elem(1)

    later_context_provider = fn request, proposal ->
      Agent.update(captured_contexts, fn contexts -> [decode_request(request) | contexts] end)
      {:ok, Jason.encode!(proposal)}
    end

    remote_actions = [
      {"remote-dialogue",
       %{
         "dialogue" => [%{"speaker_id" => "npc:lyra", "text" => "The ferment is steady."}],
         "activities" => []
       }},
      {"remote-activity",
       %{
         "dialogue" => [],
         "activities" => [%{"speaker_id" => "npc:lyra", "text" => "She checks a barrel."}]
       }}
    ]

    for {key, remote_lines} <- remote_actions do
      proposal =
        ordinary_proposal(
          Map.merge(
            %{
              "narration" => "At the bodega, the player waits for news from the Finca.",
              "character_updates" => [],
              "location_changes" => [],
              "travel_changes" => []
            },
            remote_lines
          )
        )

      assert {:ok, %{status: :failed, failure_stage: :proposal_validation} = failed} =
               Play.submit_turn(
                 campaign.id,
                 later_session.id,
                 key,
                 "Ask Lyra for an update.",
                 provider: fn request -> later_context_provider.(request, proposal) end,
                 model: "test-model"
               )

      assert Repo.get_by!(Character, id: lyra.id).current_place_id == finca.place_id
      assert {:ok, events} = Play.public_timeline(campaign.id)

      refute Enum.any?(events, fn event ->
               event.turn_id == failed.id and
                 event.event_type in [:npc_dialogue, :character_activity]
             end)
    end

    later_context = Agent.get(captured_contexts, &hd/1)
    context_lyra = Enum.find(later_context["characters"], &(&1["speaker_id"] == "npc:lyra"))
    context_player = Enum.find(later_context["characters"], &(&1["speaker_id"] == "player"))
    assert context_lyra["current_place"]["place_id"] == finca.place_id
    assert context_player["current_place"]["place_id"] == bodega.place_id

    assert Enum.any?(later_context["travel_connections"]["public_routes"], fn route ->
             route["travel_minutes"] == 40 and finca.place_id in route["place_ids"] and
               bodega.place_id in route["place_ids"]
           end)

    arrival =
      ordinary_proposal(%{
        "narration" => "After the forty-minute trip, Lyra joins the player at the bodega.",
        "dialogue" => [%{"speaker_id" => "npc:lyra", "text" => "The ferment is steady."}],
        "activities" => [%{"speaker_id" => "npc:lyra", "text" => "She checks a barrel."}],
        "character_updates" => [],
        "location_changes" => [
          %{
            "type" => "move_character",
            "speaker_id" => "npc:lyra",
            "place_id" => bodega.place_id,
            "reason" => "Lyra makes the journey from the Finca to the bodega."
          }
        ]
      })

    assert {:ok, %{status: :completed} = arrived} =
             Play.submit_turn(
               campaign.id,
               later_session.id,
               "lyra-travels-to-bodega",
               "Ask Lyra to come to the bodega before giving her update.",
               provider: fn request -> later_context_provider.(request, arrival) end,
               model: "test-model"
             )

    lyra = Repo.get_by!(Character, id: lyra.id)
    assert lyra.current_place_id == bodega.place_id

    assert {:ok, events} = Play.public_timeline(campaign.id)

    lyra_movement =
      events
      |> Enum.flat_map(&Map.get(&1.payload, "location_changes", []))
      |> Enum.find(&(&1["speaker_id"] == "npc:lyra" and &1["place_id"] == bodega.place_id))

    assert lyra_movement["travel_minutes"] == 40
    assert Enum.any?(events, &(&1.turn_id == arrived.id and &1.event_type == :npc_dialogue))
    assert Enum.any?(events, &(&1.turn_id == arrived.id and &1.event_type == :character_activity))
  end

  test "a route-valid NPC departure is blocked by active duty until the owner releases it" do
    {campaign, session} = play_campaign("The Cellar Assignment")
    finca = establish_starting_place!(campaign, "Finca")

    bodega =
      Repo.insert!(
        Place.changeset(%Place{}, %{
          campaign_id: campaign.id,
          place_id: "bodega",
          name: "Bodega",
          visibility: :public,
          facts: %{}
        })
      )

    insert_travel_connection!(campaign.id, finca.place_id, bodega.place_id, 40)

    lyra = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
    Repo.update!(Character.changeset(lyra, %{current_place_id: finca.place_id}))

    assert {:ok, before_duty} = Play.public_projection(campaign.id)

    assert {:ok, _campaign} =
             Campaigns.update_campaign_authoring(campaign, %{
               "correction_reason" =>
                 "Lyra is responsible for the Finca's morning cellar checks.",
               "expected_revision" => before_duty.revision,
               "character_active_duties" => %{
                 "npc:lyra" => %{"duty_name" => "Morning cellar checks"}
               }
             })

    state_after_assignment = Repo.get_by!(State, campaign_id: campaign.id)
    assert {:ok, assigned_projection} = Play.public_projection(campaign.id)
    assigned_lyra = Enum.find(assigned_projection.characters, &(&1.speaker_id == "npc:lyra"))
    refute Map.has_key?(assigned_lyra, :active_duty)
    refute Jason.encode!(assigned_projection) =~ "Morning cellar checks"

    attempted_move =
      ordinary_proposal(%{
        "narration" => "A road connects the Finca to the bodega.",
        "dialogue" => [],
        "activities" => [],
        "character_updates" => [],
        "location_changes" => [
          %{
            "type" => "move_character",
            "speaker_id" => "npc:lyra",
            "place_id" => bodega.place_id,
            "reason" => "Lyra takes the forty-minute road to the bodega."
          }
        ]
      })

    captured_context = Agent.start_link(fn -> nil end) |> elem(1)

    assert {:ok, %{status: :failed, failure_stage: :proposal_validation} = failed} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "duty-blocked-departure",
               "I ask Lyra to check the bodega.",
               provider: fn request ->
                 Agent.update(captured_context, fn _ -> decode_request(request) end)
                 {:ok, Jason.encode!(attempted_move)}
               end,
               model: "test-model"
             )

    gm_lyra =
      captured_context
      |> Agent.get(& &1)
      |> then(
        &Enum.find(&1["characters"], fn character -> character["speaker_id"] == "npc:lyra" end)
      )

    assert gm_lyra["active_duty"]["name"] == "Morning cellar checks"
    assert gm_lyra["active_duty"]["place_id"] == finca.place_id

    assert Repo.get_by!(Character, id: lyra.id).current_place_id == finca.place_id
    failed_state = Repo.get_by!(State, campaign_id: campaign.id)
    assert failed_state.elapsed_world_minutes == state_after_assignment.elapsed_world_minutes
    assert failed_state.revision == state_after_assignment.revision
    assert {:ok, events_after_rejection} = Play.public_timeline(campaign.id)
    refute Enum.any?(events_after_rejection, &(&1.turn_id == failed.id))
    refute Jason.encode!(events_after_rejection) =~ "Morning cellar checks"

    assert {:ok, _campaign} =
             Campaigns.update_campaign_authoring(campaign, %{
               "correction_reason" => "Lyra has completed the morning cellar checks.",
               "expected_revision" => assigned_projection.revision,
               "character_active_duties" => %{"npc:lyra" => %{"duty_name" => ""}}
             })

    assert is_nil(Repo.get_by!(Character, id: lyra.id).duty_name)

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "duty-released-departure",
               "Lyra's assignment has ended; she can go to the bodega.",
               provider: fn _request -> {:ok, Jason.encode!(attempted_move)} end,
               model: "test-model"
             )

    lyra = Repo.get_by!(Character, id: lyra.id)
    assert lyra.current_place_id == bodega.place_id
    assert is_nil(lyra.duty_name)

    assert Repo.get_by!(State, campaign_id: campaign.id).elapsed_world_minutes ==
             state_after_assignment.elapsed_world_minutes + 40

    assert {:ok, projection_after_move} = Play.public_projection(campaign.id)
    moved_lyra = Enum.find(projection_after_move.characters, &(&1.speaker_id == "npc:lyra"))
    refute Map.has_key?(moved_lyra, :active_duty)

    assert {:ok, events_after_move} = Play.public_timeline(campaign.id)
    assert Enum.any?(events_after_move, &(&1.event_type == :gm_narration))
    refute Jason.encode!(events_after_move) =~ "Morning cellar checks"
  end

  test "finite duties use the persisted pre-turn clock and release after accepted time" do
    {campaign, session} = play_campaign("The Timed Cellar Assignment")
    finca = establish_starting_place!(campaign, "Finca")

    bodega =
      Repo.insert!(
        Place.changeset(%Place{}, %{
          campaign_id: campaign.id,
          place_id: "timed-bodega",
          name: "Bodega",
          visibility: :public,
          facts: %{}
        })
      )

    insert_travel_connection!(campaign.id, finca.place_id, bodega.place_id, 40)
    lyra = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
    Repo.update!(Character.changeset(lyra, %{current_place_id: finca.place_id}))

    assert {:ok, before_assignment} = Play.public_projection(campaign.id)

    assert {:ok, _campaign} =
             Campaigns.update_campaign_authoring(campaign, %{
               "correction_reason" => "Lyra is on cellar duty for one hour.",
               "expected_revision" => before_assignment.revision,
               "character_active_duties" => %{
                 "npc:lyra" => %{
                   "duty_name" => "One-hour cellar checks",
                   "duty_duration_minutes" => "60"
                 }
               }
             })

    assigned_state = Repo.get_by!(State, campaign_id: campaign.id)
    assert Repo.get_by!(Character, id: lyra.id).duty_release_at_world_minute == 60

    attempted_departure =
      ordinary_proposal(%{
        "dialogue" => [],
        "activities" => [],
        "character_updates" => [],
        "location_changes" => [
          %{
            "type" => "move_character",
            "speaker_id" => "npc:lyra",
            "place_id" => bodega.place_id,
            "reason" => "Lyra tries to leave during her assigned hour."
          }
        ],
        "time_advance_minutes" => 60
      })

    assert {:ok, %{status: :failed, failure_stage: :proposal_validation}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "finite-duty-cannot-advance-first",
               "Lyra leaves for the bodega.",
               provider: fn _request -> {:ok, Jason.encode!(attempted_departure)} end,
               model: "test-model"
             )

    state_after_rejection = Repo.get_by!(State, campaign_id: campaign.id)
    assert state_after_rejection.elapsed_world_minutes == assigned_state.elapsed_world_minutes
    assert state_after_rejection.revision == assigned_state.revision
    assert Repo.get_by!(Character, id: lyra.id).current_place_id == finca.place_id

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "finite-duty-time-passes",
               "I wait while Lyra finishes her one-hour duty.",
               intent: :time_passage,
               provider:
                 ordinary_provider(%{
                   "dialogue" => [],
                   "activities" => [],
                   "character_updates" => [],
                   "location_changes" => [],
                   "time_advance_minutes" => 60
                 }),
               model: "test-model"
             )

    assert Repo.get_by!(State, campaign_id: campaign.id).elapsed_world_minutes == 60

    captured_context = Agent.start_link(fn -> nil end) |> elem(1)

    departure =
      ordinary_proposal(%{
        "dialogue" => [],
        "activities" => [],
        "character_updates" => [],
        "location_changes" => [
          %{
            "type" => "move_character",
            "speaker_id" => "npc:lyra",
            "place_id" => bodega.place_id,
            "reason" => "The duty is complete, so Lyra travels to the bodega."
          }
        ]
      })

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "finite-duty-canonical-departure",
               "Lyra is free to go to the bodega now.",
               provider: fn request ->
                 Agent.update(captured_context, fn _ -> decode_request(request) end)
                 {:ok, Jason.encode!(departure)}
               end,
               model: "test-model"
             )

    gm_lyra =
      captured_context
      |> Agent.get(& &1)
      |> then(
        &Enum.find(&1["characters"], fn character -> character["speaker_id"] == "npc:lyra" end)
      )

    assert gm_lyra["active_duty"]["status"] == "completed"
    assert gm_lyra["active_duty"]["available"]
    assert gm_lyra["active_duty"]["release_at_world_minute"] == 60
    assert Repo.get_by!(Character, id: lyra.id).current_place_id == bodega.place_id
    assert Repo.get_by!(State, campaign_id: campaign.id).elapsed_world_minutes == 100

    assert {:ok, projection} = Play.public_projection(campaign.id)
    refute Jason.encode!(projection) =~ "One-hour cellar checks"
  end

  test "an existing NPC with unknown location cannot be placed in-scene to speak for free" do
    {campaign, session} = play_campaign("The Unplaced Messenger")
    finca = establish_starting_place!(campaign, "Finca")
    lyra = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
    Repo.update!(Character.changeset(lyra, %{current_place_id: nil}))

    before_elapsed_minutes = Repo.get_by!(State, campaign_id: campaign.id).elapsed_world_minutes

    proposal =
      ordinary_proposal(%{
        "narration" => "Lyra suddenly appears beside the player.",
        "dialogue" => [%{"speaker_id" => "npc:lyra", "text" => "I have news."}],
        "activities" => [%{"speaker_id" => "npc:lyra", "text" => "Lyra waves from the doorway."}],
        "character_updates" => [],
        "location_changes" => [
          %{
            "type" => "move_character",
            "speaker_id" => "npc:lyra",
            "place_id" => finca.place_id,
            "reason" => "Lyra joins the player."
          }
        ]
      })

    assert {:ok, %{status: :failed, failure_stage: :proposal_validation} = failed} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "unplaced-npc-teleport",
               "Ask Lyra for news.",
               provider: fn _request -> {:ok, Jason.encode!(proposal)} end,
               model: "test-model"
             )

    assert Repo.get_by!(Character, id: lyra.id).current_place_id == nil

    assert Repo.get_by!(State, campaign_id: campaign.id).elapsed_world_minutes ==
             before_elapsed_minutes

    assert {:ok, events} = Play.public_timeline(campaign.id)
    refute Enum.any?(events, &(&1.turn_id == failed.id))
  end

  test "elapsed time sums each character's sequential route legs and takes the max across concurrent trips" do
    {campaign, session} = play_campaign("The Orchard Road", starting_location: nil)
    finca = establish_starting_place!(campaign, "Finca")

    lyra = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
    Repo.update!(Character.changeset(lyra, %{current_place_id: finca.place_id}))

    proposal =
      ordinary_proposal(%{
        "dialogue" => [],
        "activities" => [],
        "character_updates" => [],
        "time_advance_minutes" => 20,
        "location_changes" => [
          %{
            "type" => "create_place",
            "place" => %{
              "place_id" => "bodega",
              "name" => "Bodega",
              "visibility" => "public",
              "facts" => %{}
            },
            "reason" => "The bodega is established."
          },
          %{
            "type" => "create_place",
            "place" => %{
              "place_id" => "press-room",
              "name" => "Press room",
              "visibility" => "public",
              "facts" => %{}
            },
            "reason" => "The press room is established."
          },
          %{
            "type" => "move_character",
            "speaker_id" => "player",
            "place_id" => "bodega",
            "reason" => "The player reaches the bodega."
          },
          %{
            "type" => "move_character",
            "speaker_id" => "player",
            "place_id" => "press-room",
            "reason" => "The player continues to the press room."
          },
          %{
            "type" => "move_character",
            "speaker_id" => "npc:lyra",
            "place_id" => "bodega",
            "reason" => "Lyra travels to the bodega."
          }
        ],
        "travel_changes" => [
          %{
            "type" => "create_connection",
            "place_a_id" => finca.place_id,
            "place_b_id" => "bodega",
            "travel_minutes" => 40,
            "visibility" => "public",
            "reason" => "The road takes forty minutes."
          },
          %{
            "type" => "create_connection",
            "place_a_id" => "bodega",
            "place_b_id" => "press-room",
            "travel_minutes" => 15,
            "visibility" => "public",
            "reason" => "The track takes fifteen minutes."
          }
        ]
      })

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "sequential-travel",
               "Travel through the bodega to the press room.",
               provider: fn _request -> {:ok, Jason.encode!(proposal)} end,
               model: "test-model"
             )

    state = Repo.get_by!(State, campaign_id: campaign.id)
    assert state.elapsed_world_minutes == 55
    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert projection.elapsed_world_clock.minutes_since_anchor == 55
  end

  test "Ask GM never advances time, time labels re-anchor the cue, and a later wait accumulates" do
    {campaign, session} = play_campaign("The Watchmaker's Orchard")

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(campaign.id, session.id, "ask-no-time", "What do I see?",
               intent: :question,
               provider: ordinary_provider(),
               model: "test-model"
             )

    assert Repo.get_by!(State, campaign_id: campaign.id).elapsed_world_minutes == 0

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "wait-must-name-duration",
               "Let time pass.",
               intent: :time_passage,
               provider: ordinary_provider(),
               model: "test-model"
             )

    assert Repo.get_by!(State, campaign_id: campaign.id).elapsed_world_minutes == 0

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "duration-is-bounded",
               "Wait a very long time.",
               provider: ordinary_provider(%{"time_advance_minutes" => 5_256_000_001}),
               model: "test-model"
             )

    assert Repo.get_by!(State, campaign_id: campaign.id).elapsed_world_minutes == 0

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(campaign.id, session.id, "ask-cannot-advance", "What time is it?",
               intent: :question,
               provider: ordinary_provider(%{"time_advance_minutes" => 1}),
               model: "test-model"
             )

    assert Repo.get_by!(State, campaign_id: campaign.id).elapsed_world_minutes == 0

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(campaign.id, session.id, "update-label", "Let the morning arrive.",
               provider:
                 ordinary_provider(%{
                   "public_changes" => %{"time" => "Morning"},
                   "time_advance_minutes" => 60
                 }),
               model: "test-model"
             )

    state = Repo.get_by!(State, campaign_id: campaign.id)
    assert state.elapsed_world_minutes == 60
    assert state.elapsed_world_anchor_minutes == 60
    assert state.elapsed_world_anchor == %{"time" => "Morning"}

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(campaign.id, session.id, "later-wait", "Wait a little longer.",
               provider: ordinary_provider(%{"time_advance_minutes" => 12}),
               model: "test-model"
             )

    assert {:ok, projection} = Play.public_projection(campaign.id)
    assert projection.elapsed_world_clock.total_minutes == 72
    assert projection.elapsed_world_clock.minutes_since_anchor == 12
  end

  test "a rejected movement and provider failure leave elapsed world time unchanged" do
    {campaign, session} = play_campaign("The Closed Road")
    before = Repo.get_by!(State, campaign_id: campaign.id)

    invalid_move =
      ordinary_proposal(%{
        "time_advance_minutes" => 120,
        "location_changes" => [
          %{
            "type" => "create_place",
            "place" => %{
              "place_id" => "distant-bodega",
              "name" => "Distant bodega",
              "visibility" => "public",
              "facts" => %{}
            },
            "reason" => "The bodega is identified."
          },
          %{
            "type" => "move_character",
            "speaker_id" => "player",
            "place_id" => "distant-bodega",
            "reason" => "The player travels there."
          }
        ]
      })

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(campaign.id, session.id, "unconnected-travel", "Go to the bodega.",
               provider: fn _ -> {:ok, Jason.encode!(invalid_move)} end,
               model: "test-model"
             )

    after_rejection = Repo.get_by!(State, campaign_id: campaign.id)
    assert after_rejection.elapsed_world_minutes == before.elapsed_world_minutes
    refute Repo.get_by(Place, campaign_id: campaign.id, place_id: "distant-bodega")

    assert {:ok, %{status: :failed}} =
             Play.submit_turn(campaign.id, session.id, "provider-failure", "Look around.",
               provider: fn _ -> {:error, :timeout} end,
               model: "test-model"
             )

    assert Repo.get_by!(State, campaign_id: campaign.id).elapsed_world_minutes ==
             before.elapsed_world_minutes
  end

  test "rejects off-scene NPC dialogue but accepts dialogue after a same-turn arrival" do
    {campaign, session} = play_campaign("The Off-scene Messenger")
    finca = establish_starting_place!(campaign, "Finca")

    bodega =
      Repo.insert!(
        Place.changeset(%Place{}, %{
          campaign_id: campaign.id,
          place_id: "bodega",
          name: "Bodega",
          visibility: :public,
          facts: %{}
        })
      )

    insert_travel_connection!(campaign.id, finca.place_id, bodega.place_id, 40)
    player = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")
    lyra = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
    Repo.update!(Character.changeset(player, %{current_place_id: bodega.place_id}))
    Repo.update!(Character.changeset(lyra, %{current_place_id: finca.place_id}))

    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{public_state: Map.put(state.public_state, "location", "Bodega")})
    )

    remote_dialogue =
      ordinary_proposal(%{
        "dialogue" => [%{"speaker_id" => "npc:lyra", "text" => "The fermentation is steady."}],
        "activities" => [],
        "character_updates" => []
      })

    assert {:ok, %{status: :failed, failure_stage: :proposal_validation} = failed} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "remote-npc-speech",
               "Ask Lyra for an update.",
               provider: fn _request -> {:ok, Jason.encode!(remote_dialogue)} end,
               model: "test-model"
             )

    assert {:ok, events} = Play.public_timeline(campaign.id)
    refute Enum.any?(events, &(&1.turn_id == failed.id and &1.event_type == :npc_dialogue))

    arrival_and_dialogue =
      ordinary_proposal(%{
        "location_changes" => [
          %{
            "type" => "move_character",
            "speaker_id" => "npc:lyra",
            "place_id" => bodega.place_id,
            "reason" => "Lyra arrives at the bodega."
          }
        ],
        "dialogue" => [%{"speaker_id" => "npc:lyra", "text" => "The fermentation is steady."}],
        "activities" => [],
        "character_updates" => []
      })

    assert {:ok, %{status: :completed} = arrived} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "lyra-arrives-at-bodega",
               "Ask Lyra to come to the bodega before updating me.",
               provider: fn _request -> {:ok, Jason.encode!(arrival_and_dialogue)} end,
               model: "test-model"
             )

    assert Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra").current_place_id ==
             bodega.place_id

    assert {:ok, events} = Play.public_timeline(campaign.id)

    arrival =
      events
      |> Enum.flat_map(&Map.get(&1.payload, "location_changes", []))
      |> Enum.find(&(&1["speaker_id"] == "npc:lyra" and &1["place_id"] == bodega.place_id))

    assert arrival["travel_minutes"] == 40
    assert Enum.any?(events, &(&1.turn_id == arrived.id and &1.event_type == :npc_dialogue))
  end

  test "rejects narration that places an off-scene NPC in the player's current scene" do
    {campaign, session} = play_campaign("The Narrated Teleport", starting_location: "Finca")
    finca = Repo.get_by!(Place, campaign_id: campaign.id, name: "Finca")

    bodega =
      Repo.insert!(
        Place.changeset(%Place{}, %{
          campaign_id: campaign.id,
          place_id: "bodega",
          name: "Bodega",
          visibility: :public,
          facts: %{}
        })
      )

    insert_travel_connection!(campaign.id, finca.place_id, bodega.place_id, 40)
    player = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")
    lyra = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
    Repo.update!(Character.changeset(player, %{current_place_id: bodega.place_id}))

    Repo.update!(
      Character.changeset(lyra, %{name: "Lyra Bell", current_place_id: finca.place_id})
    )

    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{public_state: Map.put(state.public_state, "location", "Bodega")})
    )

    before_state = Repo.get_by!(State, campaign_id: campaign.id)
    assert {:ok, before_timeline} = Play.public_timeline(campaign.id)

    narration_only_appearance =
      ordinary_proposal(%{
        "narration" => "Lyra waves from the Bodega doorway.",
        "dialogue" => [],
        "activities" => [],
        "character_updates" => []
      })

    assert {:ok, %{status: :failed, failure_stage: :proposal_validation} = failed} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "narration-only-lyra-appearance",
               "I arrive at the Bodega and look for Lyra.",
               provider: fn _request -> {:ok, Jason.encode!(narration_only_appearance)} end,
               model: "test-model"
             )

    assert Repo.get_by!(State, campaign_id: campaign.id) == before_state

    assert Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra").current_place_id ==
             finca.place_id

    assert Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player").current_place_id ==
             bodega.place_id

    assert {:ok, ^before_timeline} = Play.public_timeline(campaign.id)

    refute Enum.any?(
             before_timeline,
             &(&1.turn_id == failed.id and &1.event_type == :gm_narration)
           )

    for {key, narration} <- [
          {"narration-only-lyra-appearance-es", "Lyra saluda desde la puerta de la Bodega."},
          {"narration-only-lyra-appearance-fr", "Lyra fait signe depuis la porte de la Bodega."}
        ] do
      translated_appearance =
        ordinary_proposal(%{
          "narration" => narration,
          "dialogue" => [],
          "activities" => [],
          "character_updates" => []
        })

      assert {:ok, %{status: :failed, failure_stage: :proposal_validation}} =
               Play.submit_turn(
                 campaign.id,
                 session.id,
                 key,
                 "I look for Lyra at the Bodega.",
                 provider: fn _request -> {:ok, Jason.encode!(translated_appearance)} end,
                 model: "test-model"
               )
    end

    remembered_reference =
      ordinary_proposal(%{
        "narration" => "You remember Lyra's advice about keeping the cellar book dry.",
        "dialogue" => [],
        "activities" => [],
        "character_updates" => []
      })

    assert {:ok, %{status: :completed} = remembered} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "remember-off-scene-lyra",
               "I think back to what Lyra told me about the cellar book.",
               provider: fn _request -> {:ok, Jason.encode!(remembered_reference)} end,
               model: "test-model"
             )

    assert {:ok, remembered_timeline} = Play.public_timeline(campaign.id)

    assert Enum.any?(remembered_timeline, fn event ->
             event.turn_id == remembered.id and event.event_type == :gm_narration
           end)

    remote_scene_reference =
      ordinary_proposal(%{
        "narration" => "At the Finca doorway, Lyra waves to a passing courier.",
        "dialogue" => [],
        "activities" => [],
        "character_updates" => []
      })

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "describe-lyra-at-her-canonical-place",
               "I wonder what Lyra might be doing back at the Finca.",
               provider: fn _request -> {:ok, Jason.encode!(remote_scene_reference)} end,
               model: "test-model"
             )

    distinctive_alias_case = fn key, narration ->
      proposal =
        ordinary_proposal(%{
          "narration" => narration,
          "dialogue" => [],
          "activities" => [],
          "character_updates" => []
        })

      Play.submit_turn(campaign.id, session.id, key, "I look around the Bodega.",
        provider: fn _request -> {:ok, Jason.encode!(proposal)} end,
        model: "test-model"
      )
    end

    # A role/title word must not be treated as a distinctive character name.
    Repo.insert!(
      Character.changeset(%Character{}, %{
        campaign_id: campaign.id,
        speaker_id: "npc:keeper-bell",
        name: "Keeper Bell",
        role: :gm,
        current_place_id: finca.place_id
      })
    )

    assert {:ok, %{status: :completed}} =
             distinctive_alias_case.(
               "generic-keeper-title-is-not-an-alias",
               "The keeper waves from the Bodega doorway."
             )

    # When two public GM characters share a first name, that short name is
    # ambiguous and must not reject a scene where one of them is present.
    Repo.insert!(
      Character.changeset(%Character{}, %{
        campaign_id: campaign.id,
        speaker_id: "npc:lyra-vale",
        name: "Lyra Vale",
        role: :gm,
        current_place_id: bodega.place_id
      })
    )

    assert {:ok, %{status: :completed}} =
             distinctive_alias_case.(
               "ambiguous-lyra-alias-is-not-rejected",
               "Lyra waves from the Bodega doorway."
             )

    # The full stored name remains a precise cue even after the first-name
    # alias became ambiguous.
    assert {:ok, %{status: :failed, failure_stage: :proposal_validation}} =
             distinctive_alias_case.(
               "full-lyra-name-still-rejected-off-scene",
               "Lyra Bell waves from the Bodega doorway."
             )

    assert Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra").current_place_id ==
             finca.place_id
  end

  test "public NPC dialogue requires an established player scene" do
    {campaign, session} = play_campaign("The Unplaced Player")
    finca = establish_starting_place!(campaign, "Finca")
    player = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")
    lyra = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")

    Repo.update!(Character.changeset(player, %{current_place_id: nil}))
    Repo.update!(Character.changeset(lyra, %{current_place_id: finca.place_id}))

    state = Repo.get_by!(State, campaign_id: campaign.id)
    before_elapsed_minutes = state.elapsed_world_minutes

    Repo.update!(
      State.changeset(state, %{public_state: Map.put(state.public_state, "location", nil)})
    )

    proposal =
      ordinary_proposal(%{
        "dialogue" => [%{"speaker_id" => "npc:lyra", "text" => "The cellar is quiet."}],
        "activities" => [%{"speaker_id" => "npc:lyra", "text" => "Lyra checks the casks."}],
        "character_updates" => []
      })

    assert {:ok, %{status: :failed, failure_stage: :proposal_validation} = failed} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "npc-without-player-scene",
               "Ask what Lyra is doing.",
               provider: fn _request -> {:ok, Jason.encode!(proposal)} end,
               model: "test-model"
             )

    assert Repo.get_by!(Character, id: player.id).current_place_id == nil
    assert Repo.get_by!(Character, id: lyra.id).current_place_id == finca.place_id

    assert Repo.get_by!(State, campaign_id: campaign.id).elapsed_world_minutes ==
             before_elapsed_minutes

    assert {:ok, events} = Play.public_timeline(campaign.id)

    refute Enum.any?(events, fn event ->
             event.turn_id == failed.id and
               event.event_type in [:npc_dialogue, :character_activity]
           end)

    assert failed.player_input == "Ask what Lyra is doing."
  end

  test "new character introduction requires accepted canonical arrival in the scene" do
    {campaign, session} = play_campaign("An Introduced Character", starting_location: nil)
    finca = establish_starting_place!(campaign, "Finca")

    proposal =
      ordinary_proposal(%{
        "character_creations" => [
          %{"speaker_id" => "npc:new", "name" => "Tomas", "visible_facts" => %{}}
        ],
        "dialogue" => [%{"speaker_id" => "npc:new", "text" => "The cellar is ready."}],
        "activities" => [],
        "character_updates" => []
      })

    assert {:ok, %{status: :failed, failure_stage: :proposal_validation}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "unplaced-new-npc",
               "Meet the cellar hand.",
               provider: fn _request -> {:ok, Jason.encode!(proposal)} end,
               model: "test-model"
             )

    arrival_proposal =
      put_in(
        proposal["location_changes"],
        [
          %{
            "type" => "move_character",
            "speaker_id" => "npc:new",
            "place_id" => finca.place_id,
            "reason" => "Tomas joins the player at the finca."
          }
        ]
      )

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(campaign.id, session.id, "placed-new-npc", "Meet the cellar hand.",
               provider: fn _request -> {:ok, Jason.encode!(arrival_proposal)} end,
               model: "test-model"
             )

    introduced = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:new")
    assert introduced.current_place_id == finca.place_id
  end

  test "places seed character presence, persist across turns, and keep private locations out of player views" do
    {campaign, session} = play_campaign("The Quiet Vineyard", starting_location: nil)
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

    lyra_record = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")

    Repo.update!(
      Character.changeset(lyra_record, %{
        visible_facts: %{"role" => "cellar keeper", "location" => "North cellar"}
      })
    )

    assert {:ok, initial} = Play.public_projection(campaign.id)
    player = Enum.find(initial.characters, &(&1.speaker_id == "player"))
    lyra = Enum.find(initial.characters, &(&1.speaker_id == "npc:lyra"))
    assert player.current_place.name == "Vineyard gate"
    assert lyra.current_place.name == "North cellar"
    assert lyra.visible_facts == %{"role" => "cellar keeper"}
    assert Enum.map(initial.places, & &1.name) |> Enum.sort() == ["North cellar", "Vineyard gate"]

    vineyard_gate = Repo.get_by!(Place, campaign_id: campaign.id, name: "Vineyard gate")
    north_cellar = Repo.get_by!(Place, campaign_id: campaign.id, name: "North cellar")

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

    travel_changes = [
      %{
        "type" => "create_connection",
        "place_a_id" => vineyard_gate.place_id,
        "place_b_id" => "press-room",
        "travel_minutes" => 5,
        "visibility" => "public",
        "reason" => "A short cellar passage links the gate and press room."
      },
      %{
        "type" => "create_connection",
        "place_a_id" => north_cellar.place_id,
        "place_b_id" => "sealed-vault",
        "travel_minutes" => 2,
        "visibility" => "gm_private",
        "reason" => "A hidden stair links the cellar and sealed vault."
      }
    ]

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "place-transition",
               "I explore the cellar.",
               provider:
                 ordinary_provider(%{
                   "location_changes" => location_changes,
                   "travel_changes" => travel_changes
                 }),
               model: "test-model"
             )

    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        public_state: Map.put(state.public_state, "location", "A stale location snapshot")
      })
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
    assert context["world"]["public"]["location"] == "Old press room"
    assert Enum.any?(context["places"]["gm_private"], &(&1["place_id"] == "sealed-vault"))
    context_lyra = Enum.find(context["characters"], &(&1["speaker_id"] == "npc:lyra"))
    assert context_lyra["current_place"]["place_id"] == "sealed-vault"
    assert context_lyra["visible_facts"]["role"] == "cellar keeper"
    refute Map.has_key?(context_lyra["visible_facts"], "location")

    assert {:ok, projection} = Play.public_projection(campaign.id)
    projected_player = Enum.find(projection.characters, &(&1.speaker_id == "player"))
    assert projected_player.current_place.name == "Old press room"
    assert projection.world["location"] == "Old press room"
    refute Enum.any?(projection.characters, &(&1.speaker_id == "npc:lyra"))
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
                 {:ok, Jason.encode!(ordinary_proposal(%{"dialogue" => [], "activities" => []}))}
               end,
               model: "test-model"
             )

    next_context = Agent.get(next_session_context, & &1)
    next_player = Enum.find(next_context["characters"], &(&1["speaker_id"] == "player"))
    assert next_player["current_place"]["name"] == "Old press room"
    assert Enum.any?(next_context["places"]["gm_private"], &(&1["place_id"] == "sealed-vault"))
  end

  test "the final player movement in one proposal determines canonical world location" do
    {campaign, session} = play_campaign("The Quiet Vineyard", starting_location: nil)
    orchard_gate = establish_starting_place!(campaign, "Orchard gate")

    location_changes =
      [
        %{
          "type" => "move_character",
          "speaker_id" => "player",
          "place_id" => orchard_gate.place_id,
          "reason" => "The player remains at the orchard gate before continuing."
        }
      ] ++ move_player_to("press-house", "Press house")

    travel_changes = [
      %{
        "type" => "create_connection",
        "place_a_id" => orchard_gate.place_id,
        "place_b_id" => "press-house",
        "travel_minutes" => 12,
        "visibility" => "public",
        "reason" => "A gravel path leads from the gate to the press house."
      }
    ]

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "cross-two-places",
               "Walk from the gate to the press house.",
               provider:
                 ordinary_provider(%{
                   "dialogue" => [],
                   "activities" => [],
                   "location_changes" => location_changes,
                   "travel_changes" => travel_changes
                 }),
               model: "test-model"
             )

    assert {:ok, projection} = Play.public_projection(campaign.id)
    player = Enum.find(projection.characters, &(&1.speaker_id == "player"))
    assert player.current_place.name == "Press house"
    assert projection.world["location"] == player.current_place.name

    assert {:ok, next_session} = Campaigns.start_session(campaign)
    observed_context = Agent.start_link(fn -> nil end) |> elem(1)

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "verify-cross-session-location",
               "Look around the press house.",
               provider: fn request ->
                 Agent.update(observed_context, fn _ -> decode_request(request) end)
                 {:ok, Jason.encode!(ordinary_proposal(%{"dialogue" => [], "activities" => []}))}
               end,
               model: "test-model"
             )

    context = Agent.get(observed_context, & &1)
    context_player = Enum.find(context["characters"], &(&1["speaker_id"] == "player"))
    assert context_player["current_place"]["name"] == "Press house"
    assert context["world"]["public"]["location"] == "Press house"
  end

  test "introduces a new GM character who can speak, act, carry an item, and be publicly present immediately" do
    {campaign, session} = play_campaign("The Amber Orchard", starting_location: nil)
    south_gate = establish_starting_place!(campaign, "South Gate")

    creation = %{
      "speaker_id" => "npc:orin",
      "name" => "Orin Vale",
      "visible_facts" => %{"role" => "orchard courier", "known_for" => "careful maps"},
      "gm_private_facts" => %{"motive" => "quietly searching for his missing sister"}
    }

    location_changes = [
      %{
        "type" => "move_character",
        "speaker_id" => "player",
        "place_id" => south_gate.place_id,
        "reason" => "The player waits at the south gate."
      },
      %{
        "type" => "move_character",
        "speaker_id" => "npc:orin",
        "place_id" => south_gate.place_id,
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
                   "dialogue" => [
                     %{
                       "speaker_id" => "npc:elira",
                       "text" => "I am hiding the silver key in the flooded passage."
                     }
                   ],
                   "activities" => [
                     %{
                       "speaker_id" => "npc:elira",
                       "text" => "Elira watches the hidden passage."
                     }
                   ],
                   "location_changes" => location_changes,
                   "character_updates" => [
                     %{
                       "speaker_id" => "npc:elira",
                       "visible_facts" => %{"met_at" => "Flooded Passage"}
                     }
                   ]
                 }),
               model: "test-model"
             )

    stored_elira = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:elira")
    assert stored_elira.visible_facts == %{}

    assert stored_elira.gm_private_facts == %{
             "trade" => "herbalist",
             "fear" => "the flooded passage",
             "plan" => "hide the silver key",
             "met_at" => "Flooded Passage"
           }

    assert {:ok, projection} = Play.public_projection(campaign.id)
    refute Enum.any?(projection.characters, &(&1.speaker_id == "npc:elira"))
    refute Enum.any?(projection.places, &(&1.place_id == "flooded-passage"))

    assert {:ok, public_events} = Play.public_timeline(campaign.id)
    public_json = Jason.encode!(public_events)
    refute public_json =~ "fear"
    refute public_json =~ "flooded-passage"
    refute public_json =~ "Flooded Passage"
    refute public_json =~ "silver key"
    refute public_json =~ "Elira Moss"
    refute public_json =~ "I am hiding"
    refute public_json =~ "watches the hidden passage"

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

    assert context_elira["visible_facts"] == %{}

    assert context_elira["gm_private_facts"] == %{
             "trade" => "herbalist",
             "fear" => "the flooded passage",
             "plan" => "hide the silver key",
             "met_at" => "Flooded Passage"
           }

    assert context_elira["current_place"]["place_id"] == "flooded-passage"
    assert context_elira["visible_activity"] == nil
    assert Enum.any?(context["places"]["gm_private"], &(&1["place_id"] == "flooded-passage"))

    assert Enum.any?(context["history"], fn event ->
             event["visibility"] == "gm_private" and event["event_type"] == "npc_dialogue" and
               event["payload"]["text"] == "I am hiding the silver key in the flooded passage."
           end)

    assert Enum.any?(context["history"], fn event ->
             event["visibility"] == "gm_private" and event["event_type"] == "character_activity" and
               event["payload"]["text"] == "Elira watches the hidden passage."
           end)

    leaking_exit = %{
      "type" => "move_character",
      "speaker_id" => "npc:elira",
      "place_id" => "orchard-road",
      "reason" => "Elira leaves the Flooded Passage."
    }

    public_road = %{
      "type" => "create_place",
      "place" => %{
        "place_id" => "orchard-road",
        "name" => "Orchard road",
        "visibility" => "public"
      },
      "reason" => "The road continues beyond the trees."
    }

    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "elira-leaks-private-exit",
               "Wait for Elira to return.",
               provider:
                 ordinary_provider(%{
                   "dialogue" => [],
                   "activities" => [],
                   "character_updates" => [],
                   "location_changes" => [public_road, leaking_exit]
                 }),
               model: "test-model"
             )

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "elira-returns-to-public-road",
               "Wait for Elira to return.",
               provider:
                 ordinary_provider(%{
                   "dialogue" => [],
                   "activities" => [],
                   "character_updates" => [],
                   "location_changes" => [
                     public_road,
                     Map.put(leaking_exit, "reason", "Elira returns to the road.")
                   ],
                   "travel_changes" => [
                     %{
                       "type" => "create_connection",
                       "place_a_id" => "flooded-passage",
                       "place_b_id" => "orchard-road",
                       "travel_minutes" => 18,
                       "visibility" => "gm_private",
                       "reason" => "A concealed drainage passage reaches the orchard road."
                     }
                   ]
                 }),
               model: "test-model"
             )

    assert {:ok, projection} = Play.public_projection(campaign.id)
    projected_elira = Enum.find(projection.characters, &(&1.speaker_id == "npc:elira"))
    assert projected_elira.visible_facts == %{}
    refute Jason.encode!(projection) =~ "Flooded Passage"
    refute Jason.encode!(projection.latest_character_changes) =~ "met_at"

    assert {:ok, public_events} = Play.public_timeline(campaign.id)
    public_json = Jason.encode!(public_events)
    refute public_json =~ "Flooded Passage"
    refute public_json =~ "met_at"

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "elira-explicitly-discloses-meeting-place",
               "Ask Elira where you met.",
               provider:
                 ordinary_provider(%{
                   "dialogue" => [],
                   "activities" => [],
                   "character_updates" => [
                     %{
                       "speaker_id" => "npc:elira",
                       "visible_facts" => %{"met_at" => "Flooded Passage"}
                     }
                   ]
                 }),
               model: "test-model"
             )

    assert {:ok, projection} = Play.public_projection(campaign.id)
    projected_elira = Enum.find(projection.characters, &(&1.speaker_id == "npc:elira"))
    assert projected_elira.visible_facts["met_at"] == "Flooded Passage"

    assert projection.latest_character_changes["npc:elira"]["after"] == %{
             "met_at" => "Flooded Passage"
           }
  end

  test "moving a character without new activity clears their stale public activity across sessions" do
    {campaign, session} = play_campaign("The Amber Orchard", starting_location: nil)
    orchard_walk = establish_starting_place!(campaign, "Orchard Walk")
    lyra = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
    Repo.update!(Character.changeset(lyra, %{current_place_id: orchard_walk.place_id}))

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "lyra-starts-work",
               "Ask Lyra what she is doing.",
               provider:
                 ordinary_provider(%{
                   "activities" => [
                     %{"speaker_id" => "npc:lyra", "text" => "She checks the irrigation gate."}
                   ],
                   "location_changes" => []
                 }),
               model: "test-model"
             )

    assert {:ok, %{characters: characters}} = Play.public_projection(campaign.id)

    assert Enum.find(characters, &(&1.speaker_id == "npc:lyra")).visible_activity ==
             "She checks the irrigation gate."

    private_place = %{
      "type" => "create_place",
      "place" => %{
        "place_id" => "hidden-cistern",
        "name" => "Hidden Cistern",
        "visibility" => "gm_private"
      },
      "reason" => "The keeper leaves for a concealed cistern."
    }

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "lyra-leaves-work",
               "Follow the track past the orchard.",
               provider:
                 ordinary_provider(%{
                   "activities" => [],
                   "dialogue" => [],
                   "location_changes" => [
                     private_place,
                     %{
                       "type" => "move_character",
                       "speaker_id" => "npc:lyra",
                       "place_id" => "hidden-cistern",
                       "reason" => "Lyra leaves the orchard walk."
                     }
                   ],
                   "travel_changes" => [
                     %{
                       "type" => "create_connection",
                       "place_a_id" => orchard_walk.place_id,
                       "place_b_id" => "hidden-cistern",
                       "travel_minutes" => 4,
                       "visibility" => "gm_private",
                       "reason" => "A hidden footpath connects the orchard walk to the cistern."
                     }
                   ]
                 }),
               model: "test-model"
             )

    assert {:ok, projection} = Play.public_projection(campaign.id)
    refute Enum.any?(projection.characters, &(&1.speaker_id == "npc:lyra"))
    refute Jason.encode!(projection) =~ "Hidden Cistern"

    assert {:ok, next_session} = Campaigns.start_session(campaign)
    captured_context = Agent.start_link(fn -> nil end) |> elem(1)

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "lyra-next-session-context",
               "Ask Lyra about the orchard.",
               provider: fn request ->
                 Agent.update(captured_context, fn _ -> decode_request(request) end)
                 {:ok, Jason.encode!(ordinary_proposal(%{"activities" => [], "dialogue" => []}))}
               end,
               model: "test-model"
             )

    context = Agent.get(captured_context, & &1)
    context_lyra = Enum.find(context["characters"], &(&1["speaker_id"] == "npc:lyra"))
    assert context_lyra["current_place"]["place_id"] == "hidden-cistern"
    assert context_lyra["visible_activity"] == nil

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "lyra-resumes-work",
               "Meet Lyra at the north trellis.",
               provider:
                 ordinary_provider(%{
                   "activities" => [
                     %{"speaker_id" => "npc:lyra", "text" => "Lyra prunes the north trellis."}
                   ],
                   "dialogue" => [],
                   "location_changes" => [
                     %{
                       "type" => "create_place",
                       "place" => %{
                         "place_id" => "north-trellis",
                         "name" => "North Trellis",
                         "visibility" => "public"
                       },
                       "reason" => "The scene establishes Lyra's new workplace."
                     },
                     %{
                       "type" => "move_character",
                       "speaker_id" => "player",
                       "place_id" => "north-trellis",
                       "reason" => "The player follows the path to meet Lyra."
                     },
                     %{
                       "type" => "move_character",
                       "speaker_id" => "npc:lyra",
                       "place_id" => "north-trellis",
                       "reason" => "Lyra moves to the north trellis."
                     }
                   ],
                   "travel_changes" => [
                     %{
                       "type" => "create_connection",
                       "place_a_id" => orchard_walk.place_id,
                       "place_b_id" => "north-trellis",
                       "travel_minutes" => 6,
                       "visibility" => "public",
                       "reason" => "A path links the orchard walk to the north trellis."
                     },
                     %{
                       "type" => "create_connection",
                       "place_a_id" => "hidden-cistern",
                       "place_b_id" => "north-trellis",
                       "travel_minutes" => 6,
                       "visibility" => "gm_private",
                       "reason" => "A concealed path returns from the cistern to the trellis."
                     }
                   ]
                 }),
               model: "test-model"
             )

    assert {:ok, %{characters: characters}} = Play.public_projection(campaign.id)
    lyra = Enum.find(characters, &(&1.speaker_id == "npc:lyra"))
    assert lyra.current_place.name == "North Trellis"
    assert lyra.visible_activity == "Lyra prunes the north trellis."
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
    {campaign, session} = play_campaign("The Quiet Vineyard", starting_location: nil)
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
    assert Enum.all?(inventory_event.payload["inventory_changes"], &is_binary(&1["reason"]))
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

  test "public inventory receipts follow add, transfer, and update on current items" do
    {campaign, session} = play_campaign("The Quiet Observatory")
    state = Repo.get_by!(State, campaign_id: campaign.id)

    inventory = [
      %{
        "id" => "field-compass",
        "name" => "Field compass",
        "quantity" => 1,
        "unit" => "compass",
        "owner_id" => "player",
        "visibility" => "public",
        "properties" => %{}
      },
      %{
        "id" => "field-journal",
        "name" => "Field journal",
        "quantity" => 1,
        "unit" => "book",
        "owner_id" => "player",
        "visibility" => "public",
        "properties" => %{"condition" => "worn"}
      }
    ]

    Repo.update!(
      State.changeset(state, %{public_state: Map.put(state.public_state, "inventory", inventory)})
    )

    complete_turn(
      campaign,
      session,
      "inventory-receipts",
      "Prepare the supplies for the crossing.",
      ordinary_provider(%{
        "inventory_changes" => [
          %{
            "type" => "transfer",
            "item_id" => "field-compass",
            "owner_id" => "npc:lyra",
            "reason" => "Lyra takes the compass to chart the western inlet."
          },
          %{
            "type" => "update",
            "item_id" => "field-journal",
            "properties" => %{"condition" => "rebound"},
            "reason" => "The journal's binding is repaired."
          },
          %{
            "type" => "add",
            "item" => %{
              "id" => "dry-rations",
              "name" => "Dry rations",
              "quantity" => 3,
              "unit" => "meals",
              "owner_id" => "party",
              "visibility" => "public",
              "category" => "Supplies",
              "properties" => %{}
            },
            "reason" => "The keeper shares three meals for the road."
          }
        ]
      })
    )

    assert {:ok, projection} = Play.public_projection(campaign.id)

    assert MapSet.new(Map.keys(projection.latest_inventory_changes)) ==
             MapSet.new(["field-compass", "field-journal", "dry-rations"])

    assert %{
             "type" => "transfer",
             "quantity" => 1,
             "owner_id" => "npc:lyra",
             "reason" => "Lyra takes the compass to chart the western inlet.",
             "game_time" => %{"time" => "First watch"}
           } = Map.fetch!(projection.latest_inventory_changes, "field-compass")

    assert %{
             "type" => "update",
             "properties" => %{"condition" => "rebound"},
             "reason" => "The journal's binding is repaired.",
             "game_time" => %{"time" => "First watch"}
           } = Map.fetch!(projection.latest_inventory_changes, "field-journal")

    assert %{
             "type" => "add",
             "item" => %{"quantity" => 3, "owner_id" => "party"},
             "reason" => "The keeper shares three meals for the road.",
             "game_time" => %{"time" => "First watch"}
           } = Map.fetch!(projection.latest_inventory_changes, "dry-rations")

    assert Enum.find(projection.inventory, &(&1["id"] == "field-compass"))["owner_id"] ==
             "npc:lyra"

    assert Enum.find(projection.inventory, &(&1["id"] == "field-journal"))["properties"] ==
             %{"condition" => "rebound"}
  end

  test "public place and character receipts come only from public state-change events" do
    {campaign, session} = play_campaign("The Beacon Road")

    old_place =
      Repo.insert!(
        Place.changeset(%Place{}, %{
          campaign_id: campaign.id,
          place_id: "old-quay",
          name: "Old quay",
          visibility: :public,
          facts: %{}
        })
      )

    lyra = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
    player = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")

    Repo.update!(Character.changeset(lyra, %{current_place_id: old_place.place_id}))
    Repo.update!(Character.changeset(player, %{current_place_id: old_place.place_id}))

    orin =
      Repo.insert!(
        Character.changeset(%Character{}, %{
          campaign_id: campaign.id,
          speaker_id: "npc:orin",
          name: "Orin Vale",
          role: :gm,
          visible_facts: %{},
          gm_private_facts: %{}
        })
      )

    Repo.update!(Character.changeset(orin, %{current_place_id: old_place.place_id}))

    complete_turn(
      campaign,
      session,
      "public-place-character-receipts",
      "Follow the road with Lyra.",
      ordinary_provider(%{
        "location_changes" => [
          %{
            "type" => "create_place",
            "place" => %{
              "place_id" => "beacon-road",
              "name" => "Beacon road",
              "visibility" => "public",
              "facts" => %{}
            },
            "reason" => "The coast path opens beyond the old quay."
          },
          %{
            "type" => "move_character",
            "speaker_id" => "player",
            "place_id" => "beacon-road",
            "reason" => "You follow the path beyond the old quay."
          },
          %{
            "type" => "move_character",
            "speaker_id" => "npc:lyra",
            "place_id" => "beacon-road",
            "reason" => "Lyra joins you on the coast path."
          },
          %{
            "type" => "create_place",
            "place" => %{
              "place_id" => "saffron-vault",
              "name" => "Saffron Vault",
              "visibility" => "gm_private",
              "facts" => %{"inscription" => "Beneath the north sill"}
            },
            "reason" => "The hidden chamber remains sealed from the party."
          },
          %{
            "type" => "move_character",
            "speaker_id" => "npc:orin",
            "place_id" => "saffron-vault",
            "reason" => "Orin slips into Saffron Vault unseen."
          }
        ],
        "travel_changes" => [
          %{
            "type" => "create_connection",
            "place_a_id" => "old-quay",
            "place_b_id" => "beacon-road",
            "travel_minutes" => 8,
            "visibility" => "public",
            "reason" => "The coast path continues from the old quay."
          },
          %{
            "type" => "create_connection",
            "place_a_id" => "old-quay",
            "place_b_id" => "saffron-vault",
            "travel_minutes" => 3,
            "visibility" => "gm_private",
            "reason" => "A concealed passage leads from the quay into the vault."
          }
        ]
      })
    )

    assert {:ok, projection} = Play.public_projection(campaign.id)

    assert %{
             "kind" => "place",
             "before" => nil,
             "after" => "Beacon road",
             "reason" => "The coast path opens beyond the old quay.",
             "game_time" => %{"time" => "First watch"}
           } = Map.fetch!(projection.latest_place_changes, "beacon-road")

    assert %{
             "kind" => "character",
             "before" => "Old quay",
             "after" => "Beacon road",
             "reason" => "You follow the path beyond the old quay.",
             "game_time" => %{"time" => "First watch"}
           } = Map.fetch!(projection.latest_character_changes, "player")

    assert %{
             "kind" => "character",
             "before" => %{"last_spoke" => nil},
             "after" => %{"last_spoke" => "The eastern star moved once."},
             "reason" => nil,
             "game_time" => %{"time" => "First watch"}
           } = Map.fetch!(projection.latest_character_changes, "npc:lyra")

    refute Map.has_key?(projection.latest_place_changes, "saffron-vault")
    refute Map.has_key?(projection.latest_character_changes, "npc:orin")

    assert {:ok, %{events: story_events}} = Play.public_story_timeline_page(campaign.id)
    refute Enum.any?(story_events, &(&1.event_type == :state_change))

    public_location_event =
      Repo.all(
        from event in Event,
          where:
            event.campaign_id == ^campaign.id and event.event_type == :state_change and
              event.visibility == :public,
          order_by: [desc: event.sequence]
      )
      |> Enum.find(&Map.has_key?(&1.payload, "location_changes"))

    assert Enum.any?(public_location_event.payload["canonical_receipts"], fn receipt ->
             receipt["id"] == "npc:lyra" and receipt["before"] == "Old quay" and
               receipt["after"] == "Beacon road" and
               receipt["reason"] == "Lyra joins you on the coast path."
           end)

    private_location_event =
      Repo.all(
        from event in Event,
          where:
            event.campaign_id == ^campaign.id and event.event_type == :state_change and
              event.visibility == :gm_private,
          order_by: [desc: event.sequence]
      )
      |> Enum.find(&Map.has_key?(&1.payload, "location_changes"))

    refute Map.has_key?(private_location_event.payload, "canonical_receipts")

    assert Enum.any?(private_location_event.payload["location_changes"], fn change ->
             change["place_name"] == "Saffron Vault" and
               change["reason"] == "Orin slips into Saffron Vault unseen."
           end)
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
               "owner_id" => "npc:lyra",
               "reason" => split["reason"]
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
    assert public_change["reason"] == public_update["reason"]
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

    assert {:ok, projection} = Play.public_projection(campaign.id)
    panels = projection.panels
    assert [%{key: "cash", value: "1250.5"}] = Enum.find(panels, &(&1.name == "Finances")).fields

    assert %{
             "before" => "1000",
             "after" => "1250.5",
             "reason" => "A patron pays for the evening's telescope viewing.",
             "game_time" => _game_time
           } = Map.fetch!(projection.latest_panel_changes, "cash")

    refute Map.has_key?(projection.latest_panel_changes, "keeper_secret")

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
    assert instructions =~ "A read-only ledger review changes nothing"

    assert {:ok, %{panels: [panel]}} = Play.public_projection(campaign.id)
    assert [%{key: "cash", value: "100"}] = panel.fields

    assert {:ok, timeline} = Play.public_timeline(campaign.id)
    refute Enum.any?(timeline, &Map.has_key?(&1.payload, "panel_changes"))
  end

  test "observation requests report only new or specifically inspected details" do
    {campaign, session} = play_campaign("The Glass Observatory")
    instructions_agent = Agent.start_link(fn -> nil end) |> elem(1)

    provider = fn request ->
      Agent.update(instructions_agent, fn _ -> request.instructions end)
      {:ok, Jason.encode!(ordinary_proposal(%{"narration" => "Nothing new catches your eye."}))}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "observe-without-recap",
               "I look around the room.",
               provider: provider,
               model: "test-model"
             )

    raw_instructions = Agent.get(instructions_agent, & &1)
    instructions = String.replace(raw_instructions, ~r/\s+/, " ")

    assert byte_size(raw_instructions) < 11_000

    assert instructions =~
             "The player alone chooses their character's actions, words, thoughts, movement"

    assert instructions =~ "Answer looks from public canon/vantage"

    assert instructions =~ "one brief, source-free ambient cue"

    assert instructions =~ "consistent with known place/time/weather"

    assert instructions =~
             "No new people, items, exits/routes, hazards, clues, services, or actionable facts"

    assert instructions =~ "accepted canon (people also need presence)"

    assert instructions =~ "If action needs untracked detail, ask or state uncertainty."

    assert instructions =~ "Preserve distinct NPC knowledge, motives, work, and voices."
    assert instructions =~ "Distinct NPC voices:"
    assert instructions =~ "never blend profiles"
    assert instructions =~ "natural word choice and rhythm, never phonetic spelling or caricature"

    assert instructions =~
             "Persisted state and approved history outrank prose and campaign instructions"

    assert instructions =~ "Propose state changes explicitly for application validation"

    assert instructions =~
             "Keep every GM-private fact, name, place, route, presence, objective, inventory value"

    assert instructions =~ "Omitted context is unknown; never infer it."

    assert instructions =~
             "For multiple matching public memories, name candidates or ask which one; do not guess."

    assert instructions =~ "Movement must use an existing route or one proposed in this response"

    assert instructions =~
             "Public NPC speech/activity requires presence in the player's final place"

    assert instructions =~ "a message needs an active public path for that sender"
    assert instructions =~ "without a matching inventory_changes operation and established cause"
    assert instructions =~ "A read-only ledger review changes nothing"
    assert instructions =~ "Request a player D20 only for an uncertain, consequential outcome"

    assert instructions =~
             "ADAPTIVE PACE: Match intent, not fixed length."

    assert instructions =~
             "montage meaningful progress at the requested scale"

    assert instructions =~ "never assume follow-through."
    assert instructions =~ "Keep dialogue proportional"
    refute instructions =~ "Use one concise, relevant utterance per character per turn"
    assert instructions =~ "combine related lines into one bubble"
    assert instructions =~ "Act describes the player's in-character action or speech"
  end

  test "in-character actions receive the adaptive scene handoff guidance" do
    {campaign, session} = play_campaign("The Glass Observatory Shared Scene")
    owner = self()

    provider = fn request ->
      send(owner, {:shared_scene_request, request})
      {:ok, Jason.encode!(ordinary_proposal(%{"dialogue" => [], "activities" => []}))}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "ask-lyra-about-the-star-chart",
               "I ask Lyra what she makes of the star chart.",
               intent: :action,
               provider: provider,
               model: "test-model"
             )

    assert_receive {:shared_scene_request, request}, 2_000
    instructions = String.replace(request.instructions, ~r/\s+/, " ")

    assert instructions =~ "ADAPTIVE PACE: Match intent, not fixed length."

    assert instructions =~
             "Don't stop at one NPC line when a natural response or consequence remains"

    assert instructions =~ "Return at the first real player-owned decision"
    assert instructions =~ "never assume follow-through."
  end

  test "a follow-up look-around question gets vantage guidance without changing the scene" do
    {campaign, session} = play_campaign("The Glass Observatory Follow-up", starting_location: nil)

    known_public_item = %{
      "id" => "field-notes",
      "name" => "Field notes",
      "quantity" => 1,
      "owner_id" => "player",
      "visibility" => "public",
      "properties" => %{}
    }

    known_private_item = %{
      "id" => "hidden-ledger-key",
      "name" => "Hidden ledger key",
      "quantity" => 1,
      "owner_id" => "npc:lyra",
      "visibility" => "gm_private",
      "properties" => %{}
    }

    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        public_state:
          state.public_state
          |> Map.delete("world_time")
          |> Map.put("time", "Late afternoon")
          |> Map.put("weather", "Overcast")
          |> Map.put("inventory", [known_public_item]),
        gm_private_state: Map.put(state.gm_private_state, "inventory", [known_private_item]),
        elapsed_world_anchor: %{"time" => "Late afternoon"}
      })
    )

    assert {:ok, opening_turn} = Play.ensure_opening_scene(campaign.id, session.id)

    opening_proposal =
      ordinary_proposal(%{
        "narration" => "You find yourself in the Glass Observatory.",
        "dialogue" => [],
        "activities" => [],
        "character_updates" => [],
        "location_changes" => move_player_to("glass-dome", "The Glass Observatory")
      })

    assert {:ok, %{status: :completed}} =
             Play.retry_turn(opening_turn.id,
               provider: fn _request -> {:ok, Jason.encode!(opening_proposal)} end,
               model: "test-model"
             )

    assert {:ok, before} = Play.public_projection(campaign.id)
    before_state = Repo.get_by!(State, campaign_id: campaign.id)
    assert {:ok, before_timeline} = Play.public_timeline(campaign.id)
    owner = self()
    question = "What can I see from here that I haven't noticed yet?"

    answer =
      "Overcast late-afternoon light leaves the room in a soft gray wash. A faint, clean scent and a low, indistinct hush lend the air a still, quiet feel. You can ask about a specific feature or choose what to do next."

    provider = fn request ->
      send(owner, {:look_around_request, request, decode_request(request)})
      {:ok, Jason.encode!(ordinary_proposal(%{"narration" => answer}))}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(campaign.id, session.id, "look-around-follow-up", question,
               intent: :question,
               provider: provider,
               model: "test-model"
             )

    assert_receive {:look_around_request, request, context}, 1_000
    instructions = String.replace(request.instructions, ~r/\s+/, " ")

    metrics = request.local_context_metrics
    assert metrics.instructions_bytes == byte_size(request.instructions)
    assert metrics.estimated_request_bytes <= metrics.budget_bytes
    assert context["interaction_mode"] == "question"
    assert context["player_action"] == question
    assert context["world"]["public"]["location"] == "The Glass Observatory"
    assert context["world"]["public"]["time"] == "Late afternoon"
    assert context["world"]["public"]["weather"] == "Overcast"
    assert instructions =~ "Treat the board and recent narration as known"

    assert instructions =~
             "answer the exact question from the character's current, public vantage"

    assert instructions =~ "For a follow-up look-around, add at most one supported new detail"

    assert instructions =~ "a source-free ambient impression is allowed under the scene rule"

    assert {:ok, after_projection} = Play.public_projection(campaign.id)
    assert after_projection.world == before.world
    assert after_projection.inventory == before.inventory

    assert Enum.map(after_projection.characters, &{&1.speaker_id, &1.current_place_id}) ==
             Enum.map(before.characters, &{&1.speaker_id, &1.current_place_id})

    after_state = Repo.get_by!(State, campaign_id: campaign.id)
    assert after_state.public_state == before_state.public_state
    assert after_state.gm_private_state == before_state.gm_private_state
    assert after_state.elapsed_world_minutes == before_state.elapsed_world_minutes
    assert after_state.elapsed_world_anchor == before_state.elapsed_world_anchor
    assert after_state.revision == before_state.revision
    assert after_state.event_sequence == before_state.event_sequence + 2

    assert {:ok, timeline} = Play.public_timeline(campaign.id)
    assert Enum.take(timeline, length(before_timeline)) == before_timeline

    new_events = Enum.drop(timeline, length(before_timeline))
    assert Enum.map(new_events, & &1.event_type) == [:player_question, :gm_narration]
    assert Enum.map(new_events, & &1.payload["text"]) == [question, answer]
  end

  test "direct and indirect observations retrieve old scene facts without off-scene decoys" do
    {campaign, first_session} = play_campaign("The Glass Observatory Observation Recall")
    old_fact = "At the Glass Observatory, a pale blue stripe crosses the star chart each morning."

    observatory = Repo.get_by!(Place, campaign_id: campaign.id, name: "The Glass Observatory")

    copper_archive =
      Repo.insert!(
        Place.changeset(%Place{}, %{
          campaign_id: campaign.id,
          place_id: "copper-archive",
          name: "The Copper Archive",
          visibility: :public
        })
      )

    insert_travel_connection!(campaign.id, observatory.place_id, copper_archive.place_id, 35)

    assert {:ok, %{status: :completed, id: seed_turn_id}} =
             Play.submit_turn(
               campaign.id,
               first_session.id,
               "record-old-observation-fact",
               "I take in the room at first light.",
               provider:
                 ordinary_provider(%{
                   "narration" => old_fact,
                   "dialogue" => [],
                   "activities" => [],
                   "character_updates" => [],
                   "private_changes" => %{}
                 }),
               model: "test-model"
             )

    {:ok, seed_timeline} = Play.public_timeline(campaign.id)
    source_event = Enum.find(seed_timeline, &(&1.payload["text"] == old_fact))
    assert source_event

    state = Repo.get_by!(State, campaign_id: campaign.id)
    first_synthetic_sequence = state.event_sequence + 1
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    unrelated_history =
      Enum.map(1..2_398, fn offset ->
        text =
          cond do
            offset <= 50 ->
              "A copied question in the Copper Archive's glass room asks what can be seen on the chart at first light."

            offset == 51 ->
              "In the Copper Archive's glass room, a hidden trapdoor opens behind the west wall."

            true ->
              "Market ledger entry #{offset} records a routine grain total."
          end

        %{
          campaign_id: campaign.id,
          session_id: first_session.id,
          turn_id: seed_turn_id,
          sequence: first_synthetic_sequence + offset - 1,
          event_type: :gm_narration,
          visibility: :public,
          payload: %{"text" => text},
          inserted_at: now
        }
      end)

    assert {2_398, nil} = Repo.insert_all(Event, unrelated_history)
    last_synthetic_sequence = first_synthetic_sequence + 2_397
    Repo.update!(State.changeset(state, %{event_sequence: last_synthetic_sequence}))

    {:ok, observation_session} = Campaigns.start_session(Campaigns.get_campaign!(campaign.id))
    owner = self()
    direct_decoy_sequences = MapSet.new(first_synthetic_sequence..(first_synthetic_sequence + 49))
    trapdoor_decoy_sequence = first_synthetic_sequence + 50
    connected_decoy_sequences = MapSet.put(direct_decoy_sequences, trapdoor_decoy_sequence)

    observations = [
      %{
        key: "direct-old-scene-observation",
        intent: :question,
        question: "What can I see on the chart at first light?",
        answer: "A pale blue stripe crosses the chart; no other specific feature stands out.",
        excluded_sequences: connected_decoy_sequences
      },
      %{
        key: "indirect-old-scene-observation",
        intent: :question,
        question: "Is there anything else in the room I might notice?",
        answer: "The pale blue stripe remains on the chart, with no other detail standing out.",
        excluded_sequences: connected_decoy_sequences
      },
      %{
        key: "spanish-old-scene-observation",
        intent: :question,
        question: "¿Qué puedo ver aquí?",
        answer: "Una franja azul pálida cruza la carta; no destaca ningún otro detalle concreto.",
        excluded_sequences: connected_decoy_sequences
      },
      %{
        key: "french-old-scene-observation",
        intent: :question,
        question: "Qu’est-ce que je peux voir ici ?",
        answer: "Une bande bleu pâle traverse la carte; aucun autre détail précis ne ressort.",
        excluded_sequences: connected_decoy_sequences
      },
      %{
        key: "unknown-observation-does-not-import-decoy",
        intent: :question,
        question: "Can I see a hidden trapdoor behind this wall?",
        answer: "There is no established trapdoor here; nothing by that description stands out.",
        excluded_sequences: connected_decoy_sequences
      }
    ]

    Enum.each(observations, fn observation ->
      before_state = Repo.get_by!(State, campaign_id: campaign.id)

      before_characters =
        Repo.all(from character in Character, where: character.campaign_id == ^campaign.id)

      before_places = Repo.all(from place in Place, where: place.campaign_id == ^campaign.id)

      provider = fn request ->
        send(
          owner,
          {:observation_context, observation.key, request, decode_request(request)}
        )

        proposal =
          ordinary_proposal(%{
            "narration" => observation.answer,
            "dialogue" => [],
            "activities" => [],
            "character_updates" => [],
            "public_changes" => %{},
            "private_changes" => %{},
            "panel_changes" => [],
            "memory_update" => %{"public_summary" => "", "gm_private_summary" => ""}
          })

        {:ok, Jason.encode!(proposal)}
      end

      assert {:ok, %{status: :completed}} =
               Play.submit_turn(
                 campaign.id,
                 observation_session.id,
                 observation.key,
                 observation.question,
                 intent: observation.intent,
                 provider: provider,
                 model: "test-model"
               )

      assert_receive {:observation_context, key, request, context}, 2_000
      assert key == observation.key
      instructions = String.replace(request.instructions, ~r/\s+/, " ")

      retained_sequences = MapSet.new(context["history"], & &1["sequence"])
      assert MapSet.member?(retained_sequences, source_event.sequence)

      refute Enum.any?(context["history"], fn event ->
               MapSet.member?(observation.excluded_sequences, event["sequence"])
             end)

      assert Enum.any?(context["history"], fn event ->
               event["sequence"] == source_event.sequence and event["payload"]["text"] == old_fact
             end)

      assert Enum.any?(context["travel_connections"]["public"], fn connection ->
               copper_archive.place_id in [connection["place_a_id"], connection["place_b_id"]] and
                 connection["travel_minutes"] == 35
             end)

      assert instructions =~
               "No new people, items, exits/routes, hazards, clues, services, or actionable facts"

      assert instructions =~ "Omitted context is unknown; never infer it."
      assert instructions =~ "If action needs untracked detail, ask or state uncertainty."
      assert request.local_context_metrics.budget_bytes == 24_000

      assert request.local_context_metrics.estimated_request_bytes <=
               request.local_context_metrics.budget_bytes

      after_state = Repo.get_by!(State, campaign_id: campaign.id)
      assert after_state.public_state == before_state.public_state
      assert after_state.gm_private_state == before_state.gm_private_state
      assert after_state.elapsed_world_minutes == before_state.elapsed_world_minutes
      assert after_state.elapsed_world_anchor_minutes == before_state.elapsed_world_anchor_minutes
      assert after_state.elapsed_world_anchor == before_state.elapsed_world_anchor
      assert after_state.revision == before_state.revision
      assert after_state.event_sequence == before_state.event_sequence + 2

      assert Repo.all(from character in Character, where: character.campaign_id == ^campaign.id) ==
               before_characters

      assert Repo.all(from place in Place, where: place.campaign_id == ^campaign.id) ==
               before_places
    end)
  end

  test "same-turn travel and look recalls destination facts but not an unvisited archive" do
    scenario = destination_observation_scenario!("Travel and Look Recall")
    %{campaign: campaign, bodega: bodega, finca: finca} = scenario
    %{session: next_session, source_event: source_event} = scenario
    old_destination_fact = scenario.old_destination_fact
    archive_decoy_text = scenario.archive_decoy_text
    owner = self()

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "ask-about-unvisited-bodega",
               "What would I see at the Bodega if I went there?",
               intent: :question,
               provider: fn request ->
                 send(owner, {:unvisited_bodega_context, decode_request(request)})

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

    assert_receive {:unvisited_bodega_context, unvisited_context}, 2_000

    refute Enum.any?(unvisited_context["history"], fn event ->
             event["sequence"] == source_event.sequence
           end)

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "wonder-about-bodega-trip",
               "I wonder what I would see at the Bodega if I went there.",
               intent: :action,
               provider: fn request ->
                 send(owner, {:hypothetical_bodega_context, decode_request(request)})

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

    assert_receive {:hypothetical_bodega_context, hypothetical_context}, 2_000

    refute Enum.any?(hypothetical_context["history"], fn event ->
             event["sequence"] == source_event.sequence
           end)

    proposal =
      ordinary_proposal(%{
        "narration" => "After the forty-minute ride, the Bodega's oak door comes into view.",
        "dialogue" => [],
        "activities" => [],
        "character_updates" => [],
        "location_changes" => [
          %{
            "type" => "move_character",
            "speaker_id" => "player",
            "place_id" => bodega.place_id,
            "reason" => "The player travels by the established route to the Bodega."
          }
        ]
      })

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "travel-to-bodega-and-look",
               "I go to the Bodega and look around.",
               provider: fn request ->
                 send(owner, {:travel_observation_context, request, decode_request(request)})
                 {:ok, Jason.encode!(proposal)}
               end,
               model: "test-model"
             )

    assert_receive {:travel_observation_context, request, context}, 2_000

    assert context["world"]["public"]["location"] == "Finca"

    assert Enum.any?(context["history"], fn event ->
             event["sequence"] == source_event.sequence and
               event["payload"]["text"] == old_destination_fact
           end)

    refute Enum.any?(context["history"], fn event ->
             event["payload"]["text"] == archive_decoy_text
           end)

    assert Enum.any?(context["travel_connections"]["public"], fn connection ->
             connection["travel_minutes"] == 40 and
               finca.place_id in [connection["place_a_id"], connection["place_b_id"]] and
               bodega.place_id in [connection["place_a_id"], connection["place_b_id"]]
           end)

    assert request.local_context_metrics.estimated_request_bytes <=
             request.local_context_metrics.budget_bytes

    player = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")
    assert player.current_place_id == bodega.place_id

    state = Repo.get_by!(State, campaign_id: campaign.id)
    assert state.elapsed_world_minutes == 40
  end

  test "same-turn travel and look recalls destination facts in Spanish and French" do
    for {title, input} <- [
          {"Spanish Travel and Look Recall", "Voy a la Bodega y miro alrededor."},
          {"French Travel and Look Recall", "Je vais à la Bodega et je regarde autour."}
        ] do
      scenario = destination_observation_scenario!(title)
      %{campaign: campaign, bodega: bodega} = scenario
      %{session: session, source_event: source_event} = scenario
      owner = self()

      proposal =
        ordinary_proposal(%{
          "narration" => "The journey ends at the Bodega's oak door.",
          "dialogue" => [],
          "activities" => [],
          "character_updates" => [],
          "location_changes" => [
            %{
              "type" => "move_character",
              "speaker_id" => "player",
              "place_id" => bodega.place_id,
              "reason" => "The player reaches the named place over the public route."
            }
          ]
        })

      assert {:ok, %{status: :completed}} =
               Play.submit_turn(
                 campaign.id,
                 session.id,
                 "localized-travel-observation",
                 input,
                 provider: fn request ->
                   send(
                     owner,
                     {:localized_travel_context, input, request, decode_request(request)}
                   )

                   {:ok, Jason.encode!(proposal)}
                 end,
                 model: "test-model"
               )

      assert_receive {:localized_travel_context, ^input, request, context}, 2_000

      assert Enum.any?(context["history"], fn event ->
               event["sequence"] == source_event.sequence and
                 event["payload"]["text"] == scenario.old_destination_fact
             end)

      refute Enum.any?(context["history"], fn event ->
               event["payload"]["text"] == scenario.archive_decoy_text
             end)

      assert request.local_context_metrics.estimated_request_bytes <=
               request.local_context_metrics.budget_bytes

      player = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")
      assert player.current_place_id == bodega.place_id
      assert Repo.get_by!(State, campaign_id: campaign.id).elapsed_world_minutes == 40
    end
  end

  test "campaign snapshots stay isolated and campaign history continues across sessions" do
    {first, first_session} = play_campaign("The Glass Observatory", starting_location: nil)
    {second, second_session} = play_campaign("The Copper Archive", starting_location: nil)
    dome = establish_starting_place!(first, "Dome")
    archive = establish_starting_place!(second, "Archive")

    complete_turn(
      first,
      first_session,
      "first",
      "Look at the map.",
      ordinary_provider(%{
        "dialogue" => [],
        "activities" => [],
        "location_changes" => [
          %{
            "type" => "move_character",
            "speaker_id" => "player",
            "place_id" => dome.place_id,
            "reason" => "The player studies the map from the dome."
          }
        ]
      })
    )

    complete_turn(
      second,
      second_session,
      "second",
      "Open the catalog.",
      ordinary_provider(%{
        "dialogue" => [],
        "activities" => [],
        "location_changes" => [
          %{
            "type" => "move_character",
            "speaker_id" => "player",
            "place_id" => archive.place_id,
            "reason" => "The player opens the catalog in the archive."
          }
        ]
      })
    )

    assert {:ok, next_session} = Campaigns.start_session(first)

    complete_turn(
      first,
      next_session,
      "third",
      "Ask about the missing page.",
      ordinary_provider(%{"dialogue" => [], "activities" => []})
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

  test "public timeline pages use the event sequence cursor without gaps or overlap" do
    {campaign, session} = play_campaign("The Sequence Archive")

    {:ok, turn} =
      Play.submit_turn(campaign.id, session.id, "timeline-pages", "Study the archive.")

    Repo.update_all(from(turn in Turn, where: turn.id == ^turn.id), set: [status: :completed])

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    events =
      Enum.map(1..7, fn sequence ->
        %{
          campaign_id: campaign.id,
          session_id: session.id,
          turn_id: turn.id,
          sequence: sequence,
          event_type: :gm_narration,
          visibility: :public,
          payload: %{"text" => "Sequence marker #{sequence}"},
          inserted_at: now
        }
      end)

    assert {7, nil} = Repo.insert_all(Event, events)

    assert {:ok, %{events: newest, has_earlier?: true}} =
             Play.public_timeline_page(campaign.id, limit: 3)

    assert Enum.map(newest, & &1.sequence) == [5, 6, 7]

    assert {:ok, %{events: middle, has_earlier?: true}} =
             Play.public_timeline_page(campaign.id, limit: 3, before_sequence: 5)

    assert Enum.map(middle, & &1.sequence) == [2, 3, 4]

    assert {:ok, %{events: oldest, has_earlier?: false}} =
             Play.public_timeline_page(campaign.id, limit: 3, before_sequence: 2)

    assert Enum.map(oldest, & &1.sequence) == [1]

    assert {:ok, %{events: [], has_earlier?: false}} =
             Play.public_timeline_page(campaign.id, limit: 3, before_sequence: 1)

    assert {:error, :invalid_cursor} =
             Play.public_timeline_page(campaign.id, before_sequence: 0)
  end

  test "production GM request recalls a named remote character through 100 sessions and 2,400 events" do
    {campaign, first_session} = play_campaign("The Quiet Observatory Long Chronicle")
    finca = establish_starting_place!(campaign, "Finca")

    bodega =
      Repo.insert!(
        Place.changeset(%Place{}, %{
          campaign_id: campaign.id,
          place_id: "bodega",
          name: "Bodega",
          visibility: :public,
          facts: %{"purpose" => "wine cellar"}
        })
      )

    insert_travel_connection!(campaign.id, finca.place_id, bodega.place_id, 40)

    player = Repo.get_by!(Character, campaign_id: campaign.id, role: :player)
    Repo.update!(Character.changeset(player, %{current_place_id: bodega.place_id}))

    marisol = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")

    Repo.update!(
      Character.changeset(marisol, %{
        name: "Marisol",
        current_place_id: finca.place_id,
        duty_name: "Finish the harvest work",
        duty_place_id: finca.place_id
      })
    )

    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{public_state: Map.put(state.public_state, "location", "Bodega")})
    )

    sessions =
      Enum.reduce(2..100, [first_session], fn _sequence, sessions ->
        {:ok, session} = Campaigns.start_session(Campaigns.get_campaign!(campaign.id))
        [session | sessions]
      end)
      |> Enum.reverse()

    assert length(sessions) == 100

    turn_ids_by_session =
      sessions
      |> Enum.with_index(1)
      |> Map.new(fn {session, session_number} ->
        input = "Synthetic Quiet Observatory session #{session_number}"
        idempotency_key = "long-history-fixture-#{session_number}"
        request_hash = :crypto.hash(:sha256, input) |> Base.encode16(case: :lower)

        turn =
          Repo.insert!(
            Turn.changeset(%Turn{}, %{
              campaign_id: campaign.id,
              session_id: session.id,
              idempotency_key: idempotency_key,
              request_hash: request_hash,
              player_input: input,
              intent: :action,
              status: :completed,
              resolution_phase: :initial,
              attempts: 0
            })
          )

        {session.id, turn.id}
      end)

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    historical_events =
      Enum.map(1..2_400, fn sequence ->
        session = Enum.at(sessions, div(sequence - 1, 24))

        text =
          cond do
            sequence == 7 ->
              "The Bodega is a forty-minute trip from Finca. Marisol and the Finca staff stay at the vineyard until harvest work is finished."

            sequence in 30..37 ->
              "At the Bodega, the village pressers demonstrate pressing grapes for passing visitors; no Finca staff are involved."

            sequence >= 2_389 ->
              "Recent observatory entry #{sequence}: Mira checks the comet chart and records a new star position."

            true ->
              "Old observatory report #{sequence}: the town council reconciles harbor fees and theater bookings. " <>
                String.duplicate("Sailors dispute the north quay tariff. ", 8)
          end

        %{
          campaign_id: campaign.id,
          session_id: session.id,
          turn_id: Map.fetch!(turn_ids_by_session, session.id),
          sequence: sequence,
          event_type: :gm_narration,
          visibility: :public,
          speaker_id: nil,
          payload: %{"text" => text},
          inserted_at: now
        }
      end)

    assert {2_400, nil} = Repo.insert_all(Event, historical_events)

    pressing_decoys = Enum.filter(historical_events, &(&1.sequence in 30..37))
    assert length(pressing_decoys) == 8

    assert Enum.all?(pressing_decoys, fn event ->
             text = event.payload["text"]
             text =~ "Bodega" and text =~ "pressing" and not (text =~ "Marisol")
           end)

    state = Repo.get_by!(State, campaign_id: campaign.id)
    Repo.update!(State.changeset(state, %{event_sequence: 2_400}))

    caller = self()

    provider = fn request ->
      context = decode_request(request)

      full_history =
        Repo.all(
          from event in Event,
            where: event.campaign_id == ^campaign.id,
            order_by: [asc: event.sequence]
        )
        |> Enum.map(fn event ->
          %{
            "sequence" => event.sequence,
            "session_id" => event.session_id,
            "event_type" => Atom.to_string(event.event_type),
            "visibility" => Atom.to_string(event.visibility),
            "speaker_id" => event.speaker_id,
            "payload" => event.payload
          }
        end)

      full_history_context = Map.put(context, "history", full_history)

      # This is a serialized full-history comparison baseline, not provider token usage.
      full_history_serialized_bytes =
        byte_size(request.instructions) + byte_size(Jason.encode!(full_history_context)) + 512

      send(
        caller,
        {:long_campaign_provider_request, request, context, full_history_serialized_bytes}
      )

      {:ok,
       Jason.encode!(
         ordinary_proposal(%{"dialogue" => [], "activities" => [], "character_updates" => []})
       )}
    end

    final_session = List.last(sessions)

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               final_session.id,
               "long-history-production-request",
               "Could Marisol join us here for the pressing?",
               intent: :question,
               provider: provider,
               model: "gpt-6-astra"
             )

    assert_receive {:long_campaign_provider_request, request, context, full_history_bytes}, 2_000

    retained_sequences = MapSet.new(context["history"], & &1["sequence"])
    newest_request_sequences = MapSet.new(2_389..2_400)
    expected_retained_sequences = MapSet.put(newest_request_sequences, 7)

    assert retained_sequences == expected_retained_sequences

    relevant_event = Enum.find(context["history"], &(&1["sequence"] == 7))
    assert relevant_event["session_id"] == Enum.at(sessions, 0).id
    assert relevant_event["payload"]["text"] =~ "forty-minute trip from Finca"

    refute Enum.any?(context["history"], fn event ->
             event["sequence"] in 30..37
           end)

    assert Enum.all?(2_389..2_400, fn sequence ->
             Enum.any?(context["history"], fn event ->
               event["sequence"] == sequence and
                 event["payload"]["text"] =~ "Recent observatory entry"
             end)
           end)

    marisol_context = Enum.find(context["characters"], &(&1["speaker_id"] == "npc:lyra"))
    player_context = Enum.find(context["characters"], &(&1["speaker_id"] == "player"))
    assert player_context["current_place_id"] == bodega.place_id
    assert marisol_context["name"] == "Marisol"
    assert marisol_context["current_place_id"] == finca.place_id
    assert marisol_context["active_duty"]["place_id"] == finca.place_id

    assert Enum.any?(context["travel_connections"]["public_routes"], fn route ->
             route["travel_minutes"] == 40 and finca.place_id in route["place_ids"]
           end)

    metrics = request.local_context_metrics

    configured_budget =
      Application.fetch_env!(:storyteller, :gm_context_byte_budgets)["gpt-6-astra"]

    compact_serialized_bytes = metrics.estimated_request_bytes

    assert metrics.budget_bytes == configured_budget
    assert compact_serialized_bytes <= configured_budget

    assert compact_serialized_bytes ==
             metrics.instructions_bytes + metrics.context_json_bytes + 512

    assert full_history_bytes >= compact_serialized_bytes * 5
    assert length(historical_events) == 2_400
  end

  test "GM context retrieves old connected-place and scene-speaker facts across sessions" do
    {campaign, first_session} = play_campaign("The Bodega Journey", starting_location: nil)
    finca = establish_starting_place!(campaign, "The Finca")

    bodega =
      Repo.insert!(
        Place.changeset(%Place{}, %{
          campaign_id: campaign.id,
          place_id: "bodega",
          name: "Bodega",
          visibility: :public,
          facts: %{"purpose" => "wine cellar"}
        })
      )

    insert_travel_connection!(campaign.id, finca.place_id, bodega.place_id, 40)

    lyra = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
    Repo.update!(Character.changeset(lyra, %{current_place_id: finca.place_id}))

    assert {:ok, %{status: :completed, id: old_turn_id}} =
             Play.submit_turn(
               campaign.id,
               first_session.id,
               "seed-old-bodega-fact",
               "We review the day's work.",
               provider:
                 ordinary_provider(%{
                   "narration" =>
                     "At the Bodega, a cask of reserve wine is held for the autumn tasting.",
                   "dialogue" => [
                     %{
                       "speaker_id" => "npc:lyra",
                       "text" => "I promised to set the reserve aside for you."
                     }
                   ]
                 }),
               model: "test-model"
             )

    {:ok, original_events} = Play.public_timeline(campaign.id)

    bodega_fact =
      Enum.find(
        original_events,
        &String.contains?(Map.get(&1.payload, "text", ""), "At the Bodega")
      )

    speaker_fact =
      Enum.find(original_events, fn event ->
        event.speaker_id == "npc:lyra" and
          String.contains?(Map.get(event.payload, "text", ""), "promised to set the reserve")
      end)

    assert bodega_fact
    assert speaker_fact

    state = Repo.get_by!(State, campaign_id: campaign.id)
    first_unrelated_sequence = state.event_sequence + 1
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    unrelated_events =
      Enum.map(1..100, fn offset ->
        %{
          campaign_id: campaign.id,
          session_id: first_session.id,
          turn_id: old_turn_id,
          sequence: first_unrelated_sequence + offset - 1,
          event_type: :gm_narration,
          visibility: :public,
          payload: %{
            "text" =>
              "The unrelated market ledger entry #{offset}. " <>
                String.duplicate("The unrelated market ledger detail. ", 16)
          },
          inserted_at: now
        }
      end)

    assert {100, nil} = Repo.insert_all(Event, unrelated_events)
    last_unrelated_sequence = first_unrelated_sequence + 99

    Repo.update!(State.changeset(state, %{event_sequence: last_unrelated_sequence}))

    {:ok, next_session} = Campaigns.start_session(Campaigns.get_campaign!(campaign.id))
    captured = Agent.start_link(fn -> nil end) |> elem(1)

    provider = fn request ->
      Agent.update(captured, fn _ -> {request, decode_request(request)} end)
      {:ok, Jason.encode!(ordinary_proposal())}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "implicit-bodega-follow-up",
               "I ask what needs doing before we close for the evening.",
               provider: provider,
               model: "test-model"
             )

    {request, context} = Agent.get(captured, & &1)
    history = context["history"]

    assert length(history) <= 20
    assert Enum.any?(history, &(&1["sequence"] == bodega_fact.sequence))
    assert Enum.any?(history, &(&1["sequence"] == speaker_fact.sequence))
    assert Enum.all?([bodega_fact, speaker_fact], &(&1.session_id == first_session.id))

    recent_start = last_unrelated_sequence - 11

    refute Enum.any?(history, fn event ->
             event["sequence"] >= first_unrelated_sequence and
               event["sequence"] < recent_start
           end)

    metrics = request.local_context_metrics
    assert metrics.compacted?
    assert metrics.estimated_request_bytes <= metrics.budget_bytes
    assert metrics.budget_bytes == 24_000
  end

  test "Spanish wine question sends matching public memory but omits unrelated note" do
    {campaign, session} = play_campaign("The Spanish Wine Ledger")

    wine_memory =
      Repo.insert!(
        ContinuityEntry.changeset(%ContinuityEntry{}, %{
          campaign_id: campaign.id,
          entry_id: "wine-reserve",
          kind: :fact,
          title: "Wine reserve for autumn",
          details: "Keep six bottles aside for the autumn tasting.",
          status: :active,
          visibility: :public
        })
      )

    unrelated_memory =
      Repo.insert!(
        ContinuityEntry.changeset(%ContinuityEntry{}, %{
          campaign_id: campaign.id,
          entry_id: "bridge-toll",
          kind: :fact,
          title: "Bridge toll agreement",
          details: "The town bridge toll is waived until summer.",
          status: :active,
          visibility: :public
        })
      )

    context_agent = Agent.start_link(fn -> nil end) |> elem(1)

    provider = fn request ->
      Agent.update(context_agent, fn _ -> decode_request(request) end)

      proposal =
        ordinary_proposal(%{
          "narration" => "The cellar is quiet as you consider the stores.",
          "dialogue" => [],
          "activities" => [],
          "character_updates" => []
        })

      {:ok, Jason.encode!(proposal)}
    end

    state_before = Repo.get_by!(State, campaign_id: campaign.id)

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "ask-wine-reserve-in-spanish",
               "¿Cuántos vinos quedan en reserva?",
               intent: :question,
               provider: provider,
               model: "test-model"
             )

    context = Agent.get(context_agent, & &1)
    public_entries = Map.new(context["continuity"]["public"], &{&1["entry_id"], &1})

    assert public_entries["wine-reserve"]["details"] == wine_memory.details
    refute Map.has_key?(public_entries["bridge-toll"], "title")
    refute Map.has_key?(public_entries["bridge-toll"], "details")

    metrics = context |> Map.fetch!("context_completeness")
    assert metrics["continuity_memory_details_omitted"]

    state_after = Repo.get_by!(State, campaign_id: campaign.id)

    assert Map.take(state_after, [
             :public_state,
             :gm_private_state,
             :elapsed_world_minutes,
             :elapsed_world_anchor_minutes,
             :elapsed_world_anchor,
             :public_history_summary,
             :gm_private_history_summary
           ]) ==
             Map.take(state_before, [
               :public_state,
               :gm_private_state,
               :elapsed_world_minutes,
               :elapsed_world_anchor_minutes,
               :elapsed_world_anchor,
               :public_history_summary,
               :gm_private_history_summary
             ])

    assert Repo.get!(ContinuityEntry, wine_memory.id) == wine_memory
    assert Repo.get!(ContinuityEntry, unrelated_memory.id) == unrelated_memory
  end

  test "later indirect tasting questions retrieve the reserve but not tasting decoys across locales" do
    {campaign, first_session} = play_campaign("The Quiet Observatory Autumn Gathering")

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               first_session.id,
               "record-autumn-gathering-facts",
               "We prepare for the observatory's autumn gathering.",
               provider:
                 ordinary_provider(%{
                   "continuity_changes" => [
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "autumn-tasting-reserve",
                         "kind" => "fact",
                         "title" => "Reserve for the autumn tasting",
                         "details" =>
                           "Six bottles of starflower cordial are kept aside for the autumn tasting.",
                         "visibility" => "public"
                       },
                       "reason" => "The group sets cordial aside for the gathering."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "autumn-tasting-schedule",
                         "kind" => "fact",
                         "title" => "Autumn tasting schedule",
                         "details" => "The autumn tasting begins at dusk when the comet returns.",
                         "visibility" => "public"
                       },
                       "reason" => "The group fixes the tasting time."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "autumn-tasting-menu",
                         "kind" => "fact",
                         "title" => "Autumn tasting menu",
                         "details" =>
                           "Pear cakes and spiced cider will be served at the autumn tasting.",
                         "visibility" => "public"
                       },
                       "reason" => "The cook plans the tasting menu."
                     }
                   ]
                 })
             )

    reserve =
      Repo.get_by!(ContinuityEntry,
        campaign_id: campaign.id,
        entry_id: "autumn-tasting-reserve"
      )

    assert reserve.source_event_id
    source_event = Repo.get!(Event, reserve.source_event_id)
    assert source_event.session_id == first_session.id

    questions = [
      "¿Qué guardamos para la cata de otoño?",
      "¿Qué apartamos para la cata de otoño?",
      "What did we save for the autumn tasting?",
      "Qu’avons-nous gardé pour la dégustation d’automne ?"
    ]

    Enum.with_index(questions)
    |> Enum.each(fn {question, index} ->
      {:ok, later_session} = Campaigns.start_session(campaign)
      captured = Agent.start_link(fn -> nil end) |> elem(1)

      provider = fn request ->
        Agent.update(captured, fn _ -> {request, decode_request(request)} end)
        {:ok, Jason.encode!(ordinary_proposal())}
      end

      assert {:ok, %{status: :completed}} =
               Play.submit_turn(
                 campaign.id,
                 later_session.id,
                 "ask-about-autumn-gathering-#{index}",
                 question,
                 intent: :question,
                 provider: provider,
                 model: "test-model"
               )

      {request, context} = Agent.get(captured, & &1)
      entries = Map.new(context["continuity"]["public"], &{&1["entry_id"], &1})

      assert entries["autumn-tasting-reserve"]["details"] == reserve.details
      assert entries["autumn-tasting-reserve"]["source_sequence"] == source_event.sequence

      for decoy_id <- ["autumn-tasting-schedule", "autumn-tasting-menu"] do
        assert entries[decoy_id]["status"] == "active"
        refute Map.has_key?(entries[decoy_id], "title")
        refute Map.has_key?(entries[decoy_id], "details")
      end

      assert request.local_context_metrics.estimated_request_bytes <= 24_000
      assert request.local_context_metrics.budget_bytes == 24_000
      assert context["context_completeness"]["continuity_memory_details_omitted"]
    end)
  end

  test "production GM request recalls a French concealed-key clue across later sessions" do
    {campaign, first_session} = play_campaign("The Cross-Language Crypt")

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               first_session.id,
               "record-french-concealed-key",
               "We preserve the crypt's old clue.",
               provider:
                 ordinary_provider(%{
                   "continuity_changes" => [
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "french-concealed-key",
                         "kind" => "fact",
                         "title" => "La clef de cuivre",
                         "details" =>
                           "La clef de cuivre a été cachée sous la pierre de la crypte.",
                         "visibility" => "public"
                       },
                       "reason" => "The French-language clue is established for later play."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "french-copper-key",
                         "kind" => "fact",
                         "title" => "La clef de cuivre",
                         "details" => "La clef de cuivre ouvre la porte nord.",
                         "visibility" => "public"
                       },
                       "reason" => "A key fact without a concealment clue is also recorded."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "french-hidden-seal",
                         "kind" => "fact",
                         "title" => "Le sceau caché",
                         "details" => "Le sceau de cire a été caché sous la table du conseil.",
                         "visibility" => "public"
                       },
                       "reason" => "A hidden object without a key clue is also recorded."
                     }
                   ]
                 }),
               model: "test-model"
             )

    target_memory =
      Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, entry_id: "french-concealed-key")

    target_source = Repo.get!(Event, target_memory.source_event_id)
    caller = self()

    questions = [
      "Where did we hide the copper key?",
      "¿Dónde escondieron la llave de cobre?",
      "Où avons-nous caché la clef de cuivre ?"
    ]

    Enum.with_index(questions)
    |> Enum.each(fn {question, index} ->
      {:ok, query_session} = Campaigns.start_session(Campaigns.get_campaign!(campaign.id))

      provider = fn request ->
        send(
          caller,
          {:concealed_key_memory_request, index, request, decode_request(request)}
        )

        {:ok, Jason.encode!(ordinary_proposal(%{"dialogue" => [], "activities" => []}))}
      end

      assert {:ok, %{status: :completed}} =
               Play.submit_turn(
                 campaign.id,
                 query_session.id,
                 "ask-for-concealed-key-#{index}",
                 question,
                 intent: :question,
                 provider: provider,
                 model: "gpt-6-astra"
               )

      assert_receive {:concealed_key_memory_request, ^index, request, context}, 2_000

      public_entries = Map.new(context["continuity"]["public"], &{&1["entry_id"], &1})
      assert public_entries["french-concealed-key"]["details"] == target_memory.details
      assert public_entries["french-concealed-key"]["source_sequence"] == target_source.sequence

      for decoy_id <- ["french-copper-key", "french-hidden-seal"] do
        assert public_entries[decoy_id]["status"] == "active"
        refute Map.has_key?(public_entries[decoy_id], "title")
        refute Map.has_key?(public_entries[decoy_id], "details")
      end

      assert request.local_context_metrics.budget_bytes == 24_000

      assert request.local_context_metrics.estimated_request_bytes <=
               request.local_context_metrics.budget_bytes
    end)
  end

  test "production GM request recalls a French-authored public star chart after 2,400 events" do
    {campaign, first_session} = play_campaign("The Quiet Observatory Star Chart Chronicle")

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               first_session.id,
               "record-french-star-chart-memory",
               "We record the observatory's old discoveries.",
               provider:
                 ordinary_provider(%{
                   "continuity_changes" => [
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "french-star-chart",
                         "kind" => "fact",
                         "title" => "La carte des étoiles",
                         "details" =>
                           "La carte des étoiles a été cachée sous la dalle de la coupole.",
                         "visibility" => "public"
                       },
                       "reason" => "The French-language campaign note records the clue."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "french-port-map",
                         "kind" => "fact",
                         "title" => "Le plan du port",
                         "details" => "Le plan du port est conservé dans le coffre de la guilde.",
                         "visibility" => "public"
                       },
                       "reason" => "A map without a star-chart clue is also recorded."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "french-north-stars",
                         "kind" => "fact",
                         "title" => "Les étoiles du Nord",
                         "details" => "Les étoiles du nord brillent au-dessus du port.",
                         "visibility" => "public"
                       },
                       "reason" => "A star observation without a chart clue is also recorded."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "private-french-star-chart",
                         "kind" => "fact",
                         "title" => "Le second relevé secret",
                         "details" =>
                           "La carte des étoiles privée est dissimulée dans le coffre fermé.",
                         "visibility" => "gm_private"
                       },
                       "reason" => "The sealed vault detail is GM-private."
                     }
                   ]
                 }),
               model: "test-model"
             )

    target_memory =
      Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, entry_id: "french-star-chart")

    target_source = Repo.get!(Event, target_memory.source_event_id)

    sessions =
      Enum.reduce(2..100, [first_session], fn _session_number, sessions ->
        {:ok, session} = Campaigns.start_session(Campaigns.get_campaign!(campaign.id))
        [session | sessions]
      end)
      |> Enum.reverse()

    turn_ids_by_session =
      sessions
      |> Enum.with_index(1)
      |> Map.new(fn {session, session_number} ->
        input = "Synthetic observatory chronicle session #{session_number}"

        turn =
          Repo.insert!(
            Turn.changeset(%Turn{}, %{
              campaign_id: campaign.id,
              session_id: session.id,
              idempotency_key: "star-chart-history-#{session_number}",
              request_hash: :crypto.hash(:sha256, input) |> Base.encode16(case: :lower),
              player_input: input,
              intent: :action,
              status: :completed,
              resolution_phase: :initial,
              attempts: 0
            })
          )

        {session.id, turn.id}
      end)

    state = Repo.get_by!(State, campaign_id: campaign.id)
    first_history_sequence = state.event_sequence + 1
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    historical_events =
      Enum.map(1..2_400, fn sequence ->
        session = Enum.at(sessions, div(sequence - 1, 24))

        text =
          if sequence >= 2_389 do
            "Recent observatory entry #{sequence}: Mira counts ordinary supply crates."
          else
            "Old observatory ledger #{sequence}: the harbor council reconciles grain accounts."
          end

        %{
          campaign_id: campaign.id,
          session_id: session.id,
          turn_id: Map.fetch!(turn_ids_by_session, session.id),
          sequence: first_history_sequence + sequence - 1,
          event_type: :gm_narration,
          visibility: :public,
          speaker_id: nil,
          payload: %{"text" => text},
          inserted_at: now
        }
      end)

    assert {2_400, nil} = Repo.insert_all(Event, historical_events)

    last_history_sequence = first_history_sequence + 2_399
    Repo.update!(State.changeset(state, %{event_sequence: last_history_sequence}))

    caller = self()

    final_session = List.last(sessions)

    questions = [
      "Where did we hide the star chart?",
      "¿Dónde escondimos el mapa de estrellas?",
      "Où avons-nous caché la carte des étoiles ?",
      "What did we mark on the constellation map?",
      "¿Dónde quedó el mapa de constelaciones?",
      "Où avons-nous caché la carte des constellations ?"
    ]

    Enum.with_index(questions)
    |> Enum.each(fn {question, index} ->
      query_session =
        if index == 0 do
          final_session
        else
          {:ok, session} = Campaigns.start_session(Campaigns.get_campaign!(campaign.id))
          session
        end

      provider = fn request ->
        send(
          caller,
          {:cross_language_memory_request, index, request, decode_request(request)}
        )

        {:ok, Jason.encode!(ordinary_proposal(%{"dialogue" => [], "activities" => []}))}
      end

      assert {:ok, %{status: :completed}} =
               Play.submit_turn(
                 campaign.id,
                 query_session.id,
                 "ask-for-star-chart-location-#{index}",
                 question,
                 intent: :question,
                 provider: provider,
                 model: "gpt-6-astra"
               )

      assert_receive {:cross_language_memory_request, ^index, request, context}, 2_000

      public_entries = Map.new(context["continuity"]["public"], &{&1["entry_id"], &1})
      private_entries = Map.new(context["continuity"]["gm_private"], &{&1["entry_id"], &1})

      assert public_entries["french-star-chart"]["details"] == target_memory.details
      assert public_entries["french-star-chart"]["source_sequence"] == target_source.sequence

      for decoy_id <- ["french-port-map", "french-north-stars"] do
        assert public_entries[decoy_id]["status"] == "active"
        refute Map.has_key?(public_entries[decoy_id], "title")
        refute Map.has_key?(public_entries[decoy_id], "details")
      end

      assert private_entries["private-french-star-chart"]["details"] =~ "coffre fermé"
      refute Map.has_key?(public_entries, "private-french-star-chart")

      if index == 0 do
        latest_sequences = MapSet.new((last_history_sequence - 11)..last_history_sequence)
        sent_sequences = MapSet.new(context["history"], & &1["sequence"])
        assert MapSet.subset?(latest_sequences, sent_sequences)
      end

      assert request.local_context_metrics.budget_bytes == 24_000

      assert request.local_context_metrics.estimated_request_bytes <=
               request.local_context_metrics.budget_bytes
    end)

    assert length(historical_events) == 2_400
  end

  test "later-session meeting and reply questions retrieve old social commitments across locales" do
    {campaign, first_session} = play_campaign("The Observatory Correspondence")

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               first_session.id,
               "record-social-commitments",
               "Mira and Nella leave the observatory after their conversation.",
               provider:
                 ordinary_provider(%{
                   "continuity_changes" => [
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "north-gate-meeting",
                         "kind" => "commitment",
                         "title" => "Nella's North Gate Promise",
                         "details" =>
                           "Nella will meet the archivist at the north gate after the comet returns.",
                         "visibility" => "public"
                       },
                       "reason" => "Nella commits to a later meeting."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "charter-reply",
                         "kind" => "commitment",
                         "title" => "Iria's Charter Promise",
                         "details" =>
                           "Iria promised to send a reply about the charter after the comet returns.",
                         "visibility" => "public"
                       },
                       "reason" => "Iria promises to send the charter decision later."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "appointment-fact",
                         "kind" => "fact",
                         "title" => "The Cartographer's Appointment",
                         "details" =>
                           "The miller expects an appointment with the cartographer after the first frost.",
                         "visibility" => "public"
                       },
                       "reason" => "The cartographer has an unrelated appointment."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "answer-fact",
                         "kind" => "fact",
                         "title" => "The Magistrate's Answer",
                         "details" =>
                           "The magistrate's answer about the river tax arrived at dawn.",
                         "visibility" => "public"
                       },
                       "reason" => "The magistrate answered a separate question."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "key-promise",
                         "kind" => "commitment",
                         "title" => "The Keeper's Key Promise",
                         "details" => "The keeper promised to return the silver key before dawn.",
                         "visibility" => "public"
                       },
                       "reason" => "The keeper promises to return a key."
                     }
                   ]
                 })
             )

    meeting =
      Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, entry_id: "north-gate-meeting")

    reply =
      Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, entry_id: "charter-reply")

    expected_details = %{meeting.entry_id => meeting.details, reply.entry_id => reply.details}

    expected_source_sequences =
      Map.new([meeting, reply], fn entry ->
        source_event = Repo.get!(Event, entry.source_event_id)
        {entry.entry_id, source_event.sequence}
      end)

    {:ok, next_session} = Campaigns.start_session(campaign)
    captured_contexts = Agent.start_link(fn -> [] end) |> elem(1)

    provider = fn request ->
      context = decode_request(request)

      Agent.update(captured_contexts, fn contexts ->
        [{context, request.local_context_metrics} | contexts]
      end)

      {:ok, Jason.encode!(ordinary_proposal())}
    end

    questions = [
      {"When is our appointment?", meeting.entry_id},
      {"¿Cuándo quedamos para vernos?", meeting.entry_id},
      {"Où devions-nous retrouver quelqu'un ?", meeting.entry_id},
      {"Où se rencontrent-ils demain ?", meeting.entry_id},
      {"Où se retrouvent-ils demain ?", meeting.entry_id},
      {"Did she answer us yet?", reply.entry_id},
      {"¿Ya nos contestó?", reply.entry_id},
      {"A-t-elle répondu ?", reply.entry_id}
    ]

    questions
    |> Enum.with_index()
    |> Enum.each(fn {{question, _expected_entry_id}, index} ->
      assert {:ok, %{status: :completed}} =
               Play.submit_turn(
                 campaign.id,
                 next_session.id,
                 "social-followup-#{index}",
                 question,
                 intent: :question,
                 provider: provider,
                 model: "test-model"
               )
    end)

    captured = Agent.get(captured_contexts, &Enum.reverse/1)
    assert length(captured) == length(questions)

    for {{question, expected_entry_id}, {context, metrics}} <- Enum.zip(questions, captured) do
      assert metrics.estimated_request_bytes <= 24_000
      assert metrics.budget_bytes == 24_000

      entries = Map.new(context["continuity"]["public"], &{&1["entry_id"], &1})
      assert entries[expected_entry_id]["details"] == expected_details[expected_entry_id]

      assert entries[expected_entry_id]["source_sequence"] ==
               expected_source_sequences[expected_entry_id]

      for decoy_id <-
            [
              "north-gate-meeting",
              "charter-reply",
              "appointment-fact",
              "answer-fact",
              "key-promise"
            ] -- [expected_entry_id] do
        assert entries[decoy_id]["entry_id"] == decoy_id
        assert entries[decoy_id]["status"] == "active"
        refute Map.has_key?(entries[decoy_id], "title"), "#{question}: #{decoy_id}"
        refute Map.has_key?(entries[decoy_id], "details"), "#{question}: #{decoy_id}"
      end

      assert context["context_completeness"]["continuity_memory_details_omitted"]
    end
  end

  test "a later-session generic agreement question receives typed commitment context" do
    {campaign, first_session} = play_campaign("The Quiet Observatory Agreements")

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               first_session.id,
               "record-two-old-facts",
               "Mira leaves the keeper's office after the conversation.",
               provider:
                 ordinary_provider(%{
                   "continuity_changes" => [
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "observatory-work-agreement",
                         "kind" => "commitment",
                         "title" => "Mira's agreement with the keeper",
                         "details" =>
                           "Mira agreed to inspect the eastern lens before the first frost.",
                         "visibility" => "public"
                       },
                       "reason" => "The keeper and Mira agree on the inspection."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "weather-proverb",
                         "kind" => "fact",
                         "title" => "The village weather proverb",
                         "details" =>
                           "The proverb promised the north wind would calm before dawn.",
                         "visibility" => "public"
                       },
                       "reason" => "Mira heard the local proverb."
                     }
                   ]
                 })
             )

    agreement =
      Repo.get_by!(ContinuityEntry,
        campaign_id: campaign.id,
        entry_id: "observatory-work-agreement"
      )

    word_match_decoy =
      Repo.get_by!(ContinuityEntry, campaign_id: campaign.id, entry_id: "weather-proverb")

    {:ok, next_session} = Campaigns.start_session(Campaigns.get_campaign!(campaign.id))
    captured_context = Agent.start_link(fn -> nil end) |> elem(1)

    provider = fn request ->
      Agent.update(captured_context, fn _ -> decode_request(request) end)

      proposal =
        ordinary_proposal(%{
          "narration" => "The keeper's agreement still stands.",
          "dialogue" => [],
          "activities" => [],
          "character_updates" => []
        })

      {:ok, Jason.encode!(proposal)}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               next_session.id,
               "ask-what-we-agreed",
               "What did we agree?",
               intent: :question,
               provider: provider,
               model: "test-model"
             )

    context = Agent.get(captured_context, & &1)
    public_entries = Map.new(context["continuity"]["public"], &{&1["entry_id"], &1})

    assert public_entries[agreement.entry_id]["details"] == agreement.details
    refute Map.has_key?(public_entries[word_match_decoy.entry_id], "title")
    refute Map.has_key?(public_entries[word_match_decoy.entry_id], "details")
    assert context["context_completeness"]["continuity_memory_details_omitted"]
  end

  test "a later-session plan question recalls an older typed public commitment without fact decoys" do
    {campaign, first_session} = play_campaign("The Quiet Observatory Plan Recall")

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               first_session.id,
               "record-observatory-plan",
               "Mira and the keeper settle what to do before the first frost.",
               provider:
                 ordinary_provider(%{
                   "continuity_changes" => [
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "eastern-lens-duty",
                         "kind" => "commitment",
                         "title" => "Eastern lens inspection",
                         "details" =>
                           "Mira will inspect the eastern glass before the first frost.",
                         "visibility" => "public"
                       },
                       "reason" => "Mira and the keeper settle on an inspection."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "lens-plan-map-fact",
                         "kind" => "fact",
                         "title" => "The eastern lens plan",
                         "details" =>
                           "A plan of the eastern lens hangs beside the keeper's workbench.",
                         "visibility" => "public"
                       },
                       "reason" => "The diagram is an ordinary fact, not an obligation."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "north-wind-proverb",
                         "kind" => "fact",
                         "title" => "The north wind proverb",
                         "details" => "The village proverb says the north wind calms by dawn.",
                         "visibility" => "public"
                       },
                       "reason" => "This proverb is unrelated to the lens duty."
                     }
                   ]
                 })
             )

    commitment =
      Repo.get_by!(ContinuityEntry,
        campaign_id: campaign.id,
        entry_id: "eastern-lens-duty"
      )

    source_event = Repo.get!(Event, commitment.source_event_id)

    {:ok, later_session} = Campaigns.start_session(Campaigns.get_campaign!(campaign.id))
    captured_request = Agent.start_link(fn -> nil end) |> elem(1)

    provider = fn request ->
      Agent.update(captured_request, fn _ -> {request, decode_request(request)} end)
      {:ok, Jason.encode!(ordinary_proposal())}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               later_session.id,
               "ask-what-was-our-plan",
               "What was our plan again?",
               intent: :question,
               provider: provider,
               model: "test-model"
             )

    {request, context} = Agent.get(captured_request, & &1)
    entries = Map.new(context["continuity"]["public"], &{&1["entry_id"], &1})

    assert entries[commitment.entry_id]["details"] == commitment.details
    assert entries[commitment.entry_id]["source_sequence"] == source_event.sequence

    for decoy_id <- ["lens-plan-map-fact", "north-wind-proverb"] do
      assert entries[decoy_id]["status"] == "active"
      refute Map.has_key?(entries[decoy_id], "title")
      refute Map.has_key?(entries[decoy_id], "details")
    end

    assert context["context_completeness"]["continuity_memory_details_omitted"]
    metrics = request.local_context_metrics
    assert metrics.budget_bytes == 24_000
    assert metrics.estimated_request_bytes <= 24_000

    assert metrics.estimated_request_bytes ==
             metrics.instructions_bytes + metrics.context_json_bytes + 512
  end

  test "later-session next-step paraphrases recall an older commitment without topic decoys" do
    {campaign, first_session} = play_campaign("The Quiet Observatory Next Steps")

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               first_session.id,
               "record-next-step-and-decoys",
               "Mira and Lyra discuss what to do at the eastern lens.",
               provider:
                 ordinary_provider(%{
                   "continuity_changes" => [
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "eastern-lens-next-step",
                         "kind" => "commitment",
                         "title" => "Inspect the eastern lens",
                         "details" =>
                           "Mira will inspect the eastern lens before the first frost.",
                         "visibility" => "public"
                       },
                       "reason" => "Mira agrees to check the lens before frost."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "lens-plan-display-fact",
                         "kind" => "fact",
                         "title" => "The lens plan on the wall",
                         "details" =>
                           "A faded plan of the eastern lens hangs beside the stairwell.",
                         "visibility" => "public"
                       },
                       "reason" => "The map is an object in the observatory, not an obligation."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "harbor-gull-fact",
                         "kind" => "fact",
                         "title" => "Gulls at the harbor",
                         "details" => "Gulls nest above the northern harbor pilings.",
                         "visibility" => "public"
                       },
                       "reason" => "This harbor detail is unrelated to the lens work."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "old-west-shutter-duty",
                         "kind" => "commitment",
                         "title" => "Repair the western shutter",
                         "details" => "Lyra repaired the western shutter last week.",
                         "visibility" => "public"
                       },
                       "reason" => "The western shutter repair is already finished."
                     }
                   ]
                 })
             )

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               first_session.id,
               "close-finished-shutter-duty",
               "Lyra confirms the western shutter was repaired last week.",
               provider:
                 ordinary_provider(%{
                   "continuity_changes" => [
                     %{
                       "type" => "update",
                       "entry_id" => "old-west-shutter-duty",
                       "status" => "resolved",
                       "reason" => "Lyra finished repairing the shutter last week."
                     }
                   ]
                 })
             )

    commitment =
      Repo.get_by!(ContinuityEntry,
        campaign_id: campaign.id,
        entry_id: "eastern-lens-next-step"
      )

    source_event = Repo.get!(Event, commitment.source_event_id)

    for {locale, action} <- [
          {"en", "What should we do next about the eastern lens?"},
          {"es", "¿Qué deberíamos hacer después con la lente oriental?"},
          {"fr", "Que devrions-nous faire ensuite pour la lentille orientale ?"},
          {"en-remaining", "What remains for us to do?"},
          {"es-remaining", "¿Qué nos queda por hacer?"},
          {"fr-remaining", "Qu’est-ce qu’il nous reste à faire ?"}
        ] do
      {:ok, later_session} = Campaigns.start_session(Campaigns.get_campaign!(campaign.id))
      captured_request = Agent.start_link(fn -> nil end) |> elem(1)

      provider = fn request ->
        Agent.update(captured_request, fn _ -> {request, decode_request(request)} end)
        {:ok, Jason.encode!(ordinary_proposal())}
      end

      assert {:ok, %{status: :completed}} =
               Play.submit_turn(
                 campaign.id,
                 later_session.id,
                 "ask-next-step-#{locale}",
                 action,
                 intent: :question,
                 provider: provider,
                 model: "test-model"
               )

      {request, context} = Agent.get(captured_request, & &1)
      entries = Map.new(context["continuity"]["public"], &{&1["entry_id"], &1})

      assert entries[commitment.entry_id]["details"] == commitment.details
      assert entries[commitment.entry_id]["source_sequence"] == source_event.sequence

      for decoy_id <- ["lens-plan-display-fact", "harbor-gull-fact"] do
        assert entries[decoy_id]["status"] == "active"
        refute Map.has_key?(entries[decoy_id], "title")
        refute Map.has_key?(entries[decoy_id], "details")
      end

      assert entries["old-west-shutter-duty"]["status"] == "resolved"
      refute Map.has_key?(entries["old-west-shutter-duty"], "title")
      refute Map.has_key?(entries["old-west-shutter-duty"], "details")

      assert context["context_completeness"]["continuity_memory_details_omitted"]
      metrics = request.local_context_metrics
      assert metrics.budget_bytes == 24_000
      assert metrics.estimated_request_bytes <= 24_000

      assert metrics.estimated_request_bytes ==
               metrics.instructions_bytes + metrics.context_json_bytes + 512
    end
  end

  test "later-session decision and agreement questions retrieve typed commitments in all supported locales" do
    {campaign, first_session} = play_campaign("The Quiet Observatory Decisions")

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               first_session.id,
               "record-observatory-decision",
               "Mira and Lyra leave the observatory after settling the lens work.",
               provider:
                 ordinary_provider(%{
                   "continuity_changes" => [
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "eastern-lens-agreement",
                         "kind" => "commitment",
                         "title" => "Eastern lens work agreement",
                         "details" =>
                           "The expedition agreed to inspect the eastern lens before the first frost.",
                         "visibility" => "public"
                       },
                       "reason" => "Mira agrees to inspect the lens."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "lens-condition-fact",
                         "kind" => "fact",
                         "title" => "The eastern lens condition",
                         "details" =>
                           "The expedition decided the eastern lens had a hairline crack before first frost.",
                         "visibility" => "public"
                       },
                       "reason" => "This records the lens condition, not a commitment."
                     },
                     %{
                       "type" => "create",
                       "entry" => %{
                         "entry_id" => "kitchen-key-fact",
                         "kind" => "fact",
                         "title" => "The kitchen key",
                         "details" => "The brass key hangs on a hook beside the kitchen door.",
                         "visibility" => "public"
                       },
                       "reason" => "This unrelated key detail remains campaign canon."
                     }
                   ]
                 })
             )

    agreement =
      Repo.get_by!(ContinuityEntry,
        campaign_id: campaign.id,
        entry_id: "eastern-lens-agreement"
      )

    for {locale, action} <- [
          {"en", "What did we decide?"},
          {"es", "¿Qué decidimos?"},
          {"fr", "Qu’avons-nous décidé ?"},
          {"es-agreement", "¿Cuál fue nuestro acuerdo?"},
          {"fr-agreement", "Quel était notre accord ?"}
        ] do
      {:ok, later_session} = Campaigns.start_session(Campaigns.get_campaign!(campaign.id))
      captured_request = Agent.start_link(fn -> nil end) |> elem(1)

      provider = fn request ->
        Agent.update(captured_request, fn _ -> {request, decode_request(request)} end)
        {:ok, Jason.encode!(ordinary_proposal())}
      end

      assert {:ok, %{status: :completed}} =
               Play.submit_turn(
                 campaign.id,
                 later_session.id,
                 "ask-what-we-decided-#{locale}",
                 action,
                 intent: :question,
                 provider: provider,
                 model: "test-model"
               )

      {request, context} = Agent.get(captured_request, & &1)
      entries = Map.new(context["continuity"]["public"], &{&1["entry_id"], &1})

      assert entries[agreement.entry_id]["details"] == agreement.details
      assert entries[agreement.entry_id]["source_sequence"]

      for decoy_id <- ["lens-condition-fact", "kitchen-key-fact"] do
        assert entries[decoy_id]["status"] == "active"
        refute Map.has_key?(entries[decoy_id], "title")
        refute Map.has_key?(entries[decoy_id], "details")
      end

      assert context["context_completeness"]["continuity_memory_details_omitted"]
      metrics = request.local_context_metrics
      assert metrics.budget_bytes == 24_000
      assert metrics.estimated_request_bytes <= metrics.budget_bytes

      assert metrics.estimated_request_bytes ==
               metrics.instructions_bytes + metrics.context_json_bytes + 512
    end
  end

  test "Ask GM reaches the provider with a modest conversation history inside the default bound" do
    {campaign, session} = play_campaign("The Lantern Observatory")
    owner = self()

    provider = fn request ->
      send(owner, {:qa_context_request, request, decode_request(request)})
      {:ok, Jason.encode!(ordinary_proposal())}
    end

    on_claim = fn turn_id, _attempt ->
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      events =
        Enum.map(1..27, fn sequence ->
          %{
            campaign_id: campaign.id,
            session_id: session.id,
            turn_id: turn_id,
            sequence: sequence,
            event_type: :gm_narration,
            visibility: :public,
            payload: %{
              "text" =>
                "At the lantern observatory, Mara checked the brass telescope and marked cloud cover on the old chart; the east stair remained locked. Note #{sequence}."
            },
            inserted_at: now
          }
        end)

      history_bytes = byte_size(Jason.encode!(events))
      assert history_bytes in 7_000..8_000
      assert {27, nil} = Repo.insert_all(Event, events)

      Repo.update_all(from(state in State, where: state.campaign_id == ^campaign.id),
        set: [event_sequence: 27]
      )
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "ask-with-modest-history",
               "What should I do next?",
               intent: :question,
               provider: provider,
               model: "gpt-6-astra",
               on_claim: on_claim
             )

    assert_receive {:qa_context_request, request, context}, 1_000
    metrics = request.local_context_metrics
    encoded_context = request.input |> hd() |> Map.fetch!(:content) |> hd() |> Map.fetch!(:text)

    assert context["interaction_mode"] == "question"
    assert metrics.budget_bytes == 24_000
    assert metrics.instructions_bytes == byte_size(request.instructions)
    assert metrics.context_json_bytes == byte_size(encoded_context)

    assert metrics.estimated_request_bytes ==
             metrics.instructions_bytes + metrics.context_json_bytes + 512

    assert metrics.estimated_request_bytes <= 24_000
  end

  test "a context-size pause keeps the submitted action available for retry" do
    {campaign, session} = play_campaign("The Quiet Cellar")
    caller = self()

    provider = fn _request ->
      send(caller, :provider_called)
      {:ok, Jason.encode!(ordinary_proposal())}
    end

    assert {:ok, %{status: :failed, failure_code: "context_budget_exceeded"} = failed} =
             Play.submit_turn(campaign.id, session.id, "context-retry", "Check the wine casks.",
               provider: provider,
               model: "test-model",
               context_input_byte_budget: 1
             )

    assert failed.player_input == "Check the wine casks."
    refute_receive :provider_called
    assert {:ok, []} = Play.public_timeline(campaign.id)

    assert {:ok, %{status: :completed} = retried} =
             Play.retry_turn(failed.id,
               provider: provider,
               model: "test-model",
               context_input_byte_budget: 24_000
             )

    assert retried.player_input == failed.player_input
    assert_receive :provider_called
    assert {:ok, timeline} = Play.public_timeline(campaign.id)
    assert Enum.count(timeline, &(&1.event_type == :player_action)) == 1
  end

  test "large canonical inventory is projected by relevance without changing saved items" do
    {campaign, session} = play_campaign("The Inventory Context Observatory")

    bulk_inventory =
      Enum.map(1..198, fn sequence ->
        %{
          "id" => "reserve-#{sequence}",
          "name" => "Reserve wine #{sequence}",
          "quantity" => sequence,
          "unit" => "bottle",
          "category" => "wine",
          "owner_id" => "player",
          "visibility" => "public",
          "description" => String.duplicate("Unrelated cellar aging notes. ", 20),
          "properties" => %{
            "vintage" => 1560 + rem(sequence, 10),
            "notes" => String.duplicate("Oak storage details. ", 15)
          }
        }
      end)

    named_item = %{
      "id" => "la-bella-2028",
      "name" => "La Bella 2028",
      "quantity" => 3,
      "unit" => "bottle",
      "category" => "wine",
      "owner_id" => "player",
      "visibility" => "public",
      "description" => "Deep plum, soft tannin, and a long finish.",
      "properties" => %{"vintage" => 2028, "condition" => "young"}
    }

    private_item = %{
      "id" => "hidden-cellar-key",
      "name" => "Cellar key",
      "quantity" => 1,
      "owner_id" => "party",
      "visibility" => "gm_private",
      "description" => "A hidden brass key behind the west cask.",
      "properties" => %{"secret" => "Do not reveal"}
    }

    original_inventory = bulk_inventory ++ [named_item]
    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        public_state: Map.put(state.public_state, "inventory", original_inventory),
        gm_private_state: Map.put(state.gm_private_state, "inventory", [private_item])
      })
    )

    caller = self()

    provider = fn request ->
      send(caller, {:inventory_context_request, request, decode_request(request)})
      {:ok, Jason.encode!(ordinary_proposal(%{"dialogue" => [], "activities" => []}))}
    end

    result =
      Play.submit_turn(
        campaign.id,
        session.id,
        "large-inventory-context",
        "I inspect the La Bella 2028 wine's color and vintage.",
        provider: provider,
        model: "gpt-6-astra"
      )

    assert {:ok, %{status: :completed}} = result

    assert_receive {:inventory_context_request, request, context}, 1_000

    selected_items = context["inventory"]["player_visible"]
    assert length(selected_items) <= 16
    assert Enum.any?(selected_items, &(&1["id"] == "la-bella-2028"))
    assert Enum.count(selected_items, &Map.has_key?(&1, "description")) <= 1
    assert context["context_completeness"]["inventory_items_omitted"]
    assert context["context_completeness"]["inventory_details_omitted"]
    refute Map.has_key?(context["world"]["public"], "inventory")
    refute Map.has_key?(context["world"]["gm_private"], "inventory")

    assert [private_item] == context["inventory"]["gm_private"]

    target = Enum.find(selected_items, &(&1["id"] == "la-bella-2028"))
    assert target["description"] == named_item["description"]
    assert target["properties"] == named_item["properties"]

    metrics = request.local_context_metrics
    assert metrics.estimated_request_bytes <= metrics.budget_bytes

    saved_state = Repo.get_by!(State, campaign_id: campaign.id)
    assert saved_state.public_state["inventory"] == original_inventory
    assert saved_state.gm_private_state["inventory"] == [private_item]
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

  test "time passage rejects player updates, movement, and rolls without committing world changes" do
    {campaign, session} = play_campaign("The Glass Observatory")
    state_before = Repo.get_by!(State, campaign_id: campaign.id)
    player_before = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")

    place_count_before =
      Repo.aggregate(from(place in Place, where: place.campaign_id == ^campaign.id), :count)

    invalid_proposals = [
      {
        "time-passage-player-update",
        %{
          "character_updates" => [
            %{
              "speaker_id" => "player",
              "visible_facts" => %{"Health" => "Well-rested"},
              "reason" => "The player waited through the night."
            }
          ]
        }
      },
      {
        "time-passage-player-movement",
        %{"location_changes" => move_player_to("unrequested-destination", "The harbor")}
      },
      {
        "time-passage-player-roll",
        %{
          "roll_request" => %{
            "test" => "Endurance",
            "difficulty" => "A long wait"
          }
        }
      }
    ]

    for {key, invalid_fields} <- invalid_proposals do
      proposal =
        ordinary_proposal(
          Map.merge(%{"public_changes" => %{"date" => "A rejected date"}}, invalid_fields)
        )

      assert {:ok, %{status: :failed, failure_code: "invalid_response"} = failed_turn} =
               Play.submit_turn(
                 campaign.id,
                 session.id,
                 key,
                 "Wait here for one day.",
                 intent: :time_passage,
                 provider: fn _request -> {:ok, Jason.encode!(proposal)} end,
                 model: "test-model"
               )

      assert Repo.get_by!(State, campaign_id: campaign.id).public_state ==
               state_before.public_state

      assert Repo.get_by!(State, campaign_id: campaign.id).gm_private_state ==
               state_before.gm_private_state

      assert Repo.get_by!(State, campaign_id: campaign.id).revision == state_before.revision

      assert Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player") ==
               player_before

      place_count_after =
        Repo.aggregate(from(place in Place, where: place.campaign_id == ^campaign.id), :count)

      assert place_count_after == place_count_before
      assert Repo.get_by(Roll, turn_id: failed_turn.id) == nil
      assert {:ok, []} = Play.public_timeline(campaign.id)
    end
  end

  test "time-passage validation logs safe rejection categories without model text" do
    {duration_campaign, duration_session} = play_campaign("Duration Diagnosis Observatory")
    output_sentinel = "UNSAFE-GM-OUTPUT-SENTINEL"

    duration_log =
      capture_log(fn ->
        assert {:ok,
                %{
                  status: :failed,
                  failure_code: "invalid_response",
                  failure_stage: :proposal_validation
                }} =
                 Play.submit_turn(
                   duration_campaign.id,
                   duration_session.id,
                   "invalid-duration-diagnostic",
                   "A day passes.",
                   intent: :time_passage,
                   provider:
                     ordinary_provider(%{
                       "narration" => output_sentinel,
                       "time_advance_minutes" => 0
                     }),
                   model: "test-model"
                 )
      end)

    assert duration_log =~ "intent=time_passage category=time_advance"
    refute duration_log =~ output_sentinel
    assert Repo.get_by!(State, campaign_id: duration_campaign.id).elapsed_world_minutes == 0
    assert {:ok, []} = Play.public_timeline(duration_campaign.id)

    {agency_campaign, agency_session} = play_campaign("Agency Diagnosis Observatory")

    agency_log =
      capture_log(fn ->
        assert {:ok,
                %{
                  status: :failed,
                  failure_code: "invalid_response",
                  failure_stage: :proposal_validation
                }} =
                 Play.submit_turn(
                   agency_campaign.id,
                   agency_session.id,
                   "player-agency-diagnostic",
                   "A day passes.",
                   intent: :time_passage,
                   provider:
                     ordinary_provider(%{
                       "dialogue" => [%{"speaker_id" => "player", "text" => output_sentinel}],
                       "time_advance_minutes" => 1_440
                     }),
                   model: "test-model"
                 )
      end)

    assert agency_log =~ "intent=time_passage category=player_agency"
    refute agency_log =~ output_sentinel
    assert Repo.get_by!(State, campaign_id: agency_campaign.id).elapsed_world_minutes == 0
    assert {:ok, []} = Play.public_timeline(agency_campaign.id)
  end

  test "time passage accepts world and NPC events and preserves an explicit multi-day duration" do
    {campaign, session} = play_campaign("The Glass Observatory")
    test_pid = self()
    requested_duration = "Wait here for 21 days until the courier reaches the observatory."

    provider = fn request ->
      context = decode_request(request)

      send(
        test_pid,
        {:time_passage_request, context["interaction_mode"], context["player_action"],
         request.instructions}
      )

      {:ok,
       Jason.encode!(
         ordinary_proposal(%{
           "narration" => "Twenty-one days pass. The courier arrives with a sealed letter.",
           "dialogue" => [%{"speaker_id" => "npc:lyra", "text" => "The courier is here."}],
           "activities" => [%{"speaker_id" => "npc:lyra", "text" => "Lyra receives the letter."}],
           "public_changes" => %{"date" => "Day 22", "time" => "Morning"},
           "time_advance_minutes" => 30_240,
           "roll_request" => nil
         })
       )}
    end

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "explicit-multi-day-wait",
               requested_duration,
               intent: :time_passage,
               provider: provider,
               model: "test-model"
             )

    assert_receive {:time_passage_request, "time_passage", ^requested_duration, instructions}
    assert instructions =~ "multi-day durations"
    assert instructions =~ "Advance NPC/world events only"
    normalized_instructions = String.replace(instructions, ~r/\s+/, " ")

    assert normalized_instructions =~
             "Resolve routine activity across the interval as a coherent montage"

    assert normalized_instructions =~ "Do not stop after each incidental action"

    state = Repo.get_by!(State, campaign_id: campaign.id)
    assert state.public_state["date"] == "Day 22"
    assert state.public_state["time"] == "Morning"
    assert state.elapsed_world_minutes == 30_240
    assert state.elapsed_world_anchor_minutes == 30_240
    assert state.elapsed_world_anchor == %{"date" => "Day 22", "time" => "Morning"}

    assert {:ok, timeline} = Play.public_timeline(campaign.id)
    assert Enum.any?(timeline, &(&1.event_type == :time_passage))
    assert Enum.any?(timeline, &(&1.event_type == :gm_narration))
    assert Enum.any?(timeline, &(&1.event_type == :npc_dialogue))
    assert Enum.any?(timeline, &(&1.event_type == :character_activity))
    refute Enum.any?(timeline, &(&1.event_type in [:player_action, :roll_request, :player_roll]))
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

  test "retry after a D20 provider failure reuses the recorded roll without duplicating events" do
    {campaign, session} = play_campaign("The Glass Observatory")
    provider_calls = :atomics.new(1, [])
    roll_source_calls = :atomics.new(1, [])
    captured_contexts = Agent.start_link(fn -> [] end) |> elem(1)

    provider = fn request ->
      context = decode_request(request)
      Agent.update(captured_contexts, &(&1 ++ [context]))

      case :atomics.add_get(provider_calls, 1, 1) do
        1 ->
          {:ok, Jason.encode!(roll_proposal())}

        2 ->
          {:error, :timeout}

        3 ->
          {:ok,
           Jason.encode!(ordinary_proposal(%{"public_changes" => %{"time" => "Second watch"}}))}
      end
    end

    assert {:ok, waiting} =
             Play.submit_turn(campaign.id, session.id, "climb-retry", "Climb the narrow ledge.",
               provider: provider,
               model: "test-model"
             )

    assert waiting.status == :awaiting_roll
    assert {:ok, before_roll_resolution} = Play.public_projection(campaign.id)
    assert before_roll_resolution.world["time"] == "First watch"

    assert {:ok, %{turn: failed, roll: %Roll{result: 17}}} =
             Play.click_player_d20(waiting.id,
               roll_source: fn ->
                 :atomics.add(roll_source_calls, 1, 1)
                 17
               end,
               provider: provider,
               model: "test-model"
             )

    assert failed.status == :failed
    assert failed.resolution_phase == :after_roll
    assert Repo.get_by!(Roll, turn_id: waiting.id).result == 17
    assert :atomics.get(provider_calls, 1) == 2
    assert :atomics.get(roll_source_calls, 1) == 1
    assert Play.public_projection(campaign.id) == {:ok, before_roll_resolution}

    assert {:ok, completed} = Play.retry_turn(failed.id, provider: provider, model: "test-model")
    assert completed.status == :completed
    assert :atomics.get(provider_calls, 1) == 3
    assert :atomics.get(roll_source_calls, 1) == 1

    [_, failed_context, retry_context] = Agent.get(captured_contexts, & &1)

    for context <- [failed_context, retry_context] do
      assert context["phase"] == "after_roll"
      assert context["player_roll"]["result"] == 17
      assert context["player_roll"]["authorized_by"] == "player_click"
    end

    assert {:ok, %{world: %{"time" => "Second watch"}}} = Play.public_projection(campaign.id)

    assert Repo.aggregate(Roll, :count) == 1
    assert {:ok, timeline} = Play.public_timeline(campaign.id)
    assert Enum.count(timeline, &(&1.event_type == :player_action)) == 1
    assert Enum.count(timeline, &(&1.event_type == :roll_request)) == 1
    assert Enum.count(timeline, &(&1.event_type == :player_roll)) == 1

    assert Enum.count(timeline, fn event ->
             event.event_type == :state_change and
               event.payload["changes"] == %{"time" => "Second watch"}
           end) == 1

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

  test "superseding a failed turn preserves its safe failure diagnosis" do
    {campaign, session} = play_campaign("The Glass Observatory")

    assert {:ok, failed} =
             Play.submit_turn(campaign.id, session.id, "lost", "Check the window.",
               provider: fn _ -> {:ok, Jason.encode!(%{"narration" => ""})} end
             )

    assert failed.status == :failed
    assert failed.failure_code == "invalid_response"
    assert failed.failure_stage == :proposal_validation

    assert {:ok, completed} =
             Play.submit_turn(campaign.id, session.id, "new-action", "Ask for tea.",
               provider: ordinary_provider(),
               model: "test-model"
             )

    assert completed.status == :completed
    superseded = Repo.get!(Turn, failed.id)
    assert superseded.status == :superseded
    assert superseded.failure_code == "invalid_response"
    assert superseded.failure_stage == :proposal_validation
    assert {:ok, events} = Play.public_timeline(campaign.id)
    assert Enum.count(events, &(&1.event_type == :player_action)) == 1
    assert Enum.at(events, 0).payload["text"] == "Ask for tea."
  end

  test "failed GM requests retain a fixed safe stage without provider content" do
    {campaign, session} = play_campaign("The Glass Observatory")
    raw_provider_text = "RAW-MODEL-OUTPUT-SENTINEL"
    error_detail = "PRIVATE-PROVIDER-ERROR-SENTINEL"

    failures = [
      {"provider-stage", fn _request -> {:error, {:provider_error, error_detail}} end, :provider},
      {"decode-stage", fn _request -> {:ok, raw_provider_text} end, :response_decoding},
      {
        "validation-stage",
        fn _request -> {:ok, Jason.encode!(%{"narration" => ""})} end,
        :proposal_validation
      }
    ]

    for {key, provider, expected_stage} <- failures do
      assert {:ok, %{status: :failed, failure_code: failure_code} = failed} =
               Play.submit_turn(campaign.id, session.id, key, "I check the observatory.",
                 provider: provider,
                 model: "test-model"
               )

      assert failed.failure_stage == expected_stage
      assert failure_code in ["provider_error", "invalid_response"]
      refute inspect(failed) =~ raw_provider_text
      refute inspect(failed) =~ error_detail
    end
  end

  test "commit failures retain only the commit stage and leave the turn retryable" do
    {campaign, session} = play_campaign("The Glass Observatory")

    Repo.query!("""
    CREATE FUNCTION storyteller_test_reject_play_event() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'test-only commit rejection';
    END;
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER storyteller_test_reject_play_event
    BEFORE INSERT ON play_events
    FOR EACH ROW EXECUTE FUNCTION storyteller_test_reject_play_event()
    """)

    on_exit(fn ->
      Repo.query!("DROP TRIGGER IF EXISTS storyteller_test_reject_play_event ON play_events")
      Repo.query!("DROP FUNCTION IF EXISTS storyteller_test_reject_play_event()")
    end)

    assert {:ok,
            %{status: :failed, failure_code: "provider_error", failure_stage: :commit} = failed} =
             Play.submit_turn(campaign.id, session.id, "commit-stage", "I inspect the lens.",
               provider: ordinary_provider(),
               model: "test-model"
             )

    assert failed.failure_stage == :commit
    assert Repo.get!(Turn, failed.id).failure_stage == :commit
    assert {:ok, []} = Play.public_timeline(campaign.id)
  end

  test "a reclaimed resolution attempt fences a late successful provider result" do
    {campaign, session} = play_campaign("The Glass Observatory", starting_location: nil)
    fresh_place = establish_starting_place!(campaign, "Fresh worker")

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
               "dialogue" => [],
               "activities" => [],
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
                   "dialogue" => [],
                   "activities" => [],
                   "location_changes" => [
                     %{
                       "type" => "move_character",
                       "speaker_id" => "player",
                       "place_id" => fresh_place.place_id,
                       "reason" => "The player remains at the fresh worker's post."
                     }
                   ]
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
           |> Map.get("location") == "The Glass Observatory"

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
           |> Map.get("location") == "The Glass Observatory"

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
    assert projection.world["location"] == "The Glass Observatory"
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

  defp destination_observation_scenario!(title) do
    {campaign, first_session} = play_campaign(title, starting_location: nil)
    finca = establish_starting_place!(campaign, "Finca")

    bodega =
      Repo.insert!(
        Place.changeset(%Place{}, %{
          campaign_id: campaign.id,
          place_id: "bodega",
          name: "Bodega",
          visibility: :public,
          facts: %{"purpose" => "wine cellar"}
        })
      )

    archive =
      Repo.insert!(
        Place.changeset(%Place{}, %{
          campaign_id: campaign.id,
          place_id: "copper-archive",
          name: "Copper Archive",
          visibility: :public
        })
      )

    insert_travel_connection!(campaign.id, finca.place_id, bodega.place_id, 40)
    insert_travel_connection!(campaign.id, bodega.place_id, archive.place_id, 25)

    old_destination_fact =
      "At the Bodega, a pale blue chalk line crosses the cellar's western oak door."

    assert {:ok, %{status: :completed, id: seed_turn_id}} =
             Play.submit_turn(
               campaign.id,
               first_session.id,
               "seed-old-bodega-observation",
               "I review the cellar ledger before setting out.",
               provider:
                 ordinary_provider(%{
                   "narration" => old_destination_fact,
                   "dialogue" => [],
                   "activities" => [],
                   "character_updates" => [],
                   "private_changes" => %{}
                 }),
               model: "test-model"
             )

    {:ok, seed_timeline} = Play.public_timeline(campaign.id)
    source_event = Enum.find(seed_timeline, &(&1.payload["text"] == old_destination_fact))
    assert source_event

    state = Repo.get_by!(State, campaign_id: campaign.id)
    first_synthetic_sequence = state.event_sequence + 1
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    archive_decoy_text =
      "At the Copper Archive, a pale blue chalk line crosses the map cabinet's side door."

    unrelated_events =
      Enum.map(1..50, fn offset ->
        text =
          if offset <= 8,
            do: archive_decoy_text,
            else: "Unrelated market ledger entry #{offset} records a routine grain total."

        %{
          campaign_id: campaign.id,
          session_id: first_session.id,
          turn_id: seed_turn_id,
          sequence: first_synthetic_sequence + offset - 1,
          event_type: :gm_narration,
          visibility: :public,
          payload: %{"text" => text},
          inserted_at: now
        }
      end)

    assert {50, nil} = Repo.insert_all(Event, unrelated_events)
    last_synthetic_sequence = first_synthetic_sequence + 49
    Repo.update!(State.changeset(state, %{event_sequence: last_synthetic_sequence}))

    {:ok, session} = Campaigns.start_session(Campaigns.get_campaign!(campaign.id))

    %{
      campaign: campaign,
      session: session,
      finca: finca,
      bodega: bodega,
      source_event: source_event,
      old_destination_fact: old_destination_fact,
      archive_decoy_text: archive_decoy_text
    }
  end

  defp establish_starting_place!(campaign, name) do
    state = Repo.get_by!(State, campaign_id: campaign.id)

    Repo.update!(
      State.changeset(state, %{
        public_state: Map.put(state.public_state, "location", name)
      })
    )

    assert {:ok, _state} =
             Play.initialize_campaign(campaign, %{public_state: %{"location" => name}})

    Repo.get_by!(Place, campaign_id: campaign.id, name: name)
  end

  defp insert_travel_connection!(campaign_id, place_a_id, place_b_id, travel_minutes) do
    [place_a_id, place_b_id] = Enum.sort([place_a_id, place_b_id])

    Repo.insert!(
      PlaceConnection.changeset(%PlaceConnection{}, %{
        campaign_id: campaign_id,
        place_a_id: place_a_id,
        place_b_id: place_b_id,
        travel_minutes: travel_minutes,
        visibility: :public
      })
    )
  end

  defp play_campaign(title, opts \\ []) do
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
                 elapsed_world_anchor: %{"time" => "First watch"},
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

    case Keyword.get(opts, :starting_location, "The Glass Observatory") do
      nil ->
        :ok

      starting_location ->
        place = establish_starting_place!(campaign, starting_location)
        lyra = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:lyra")
        Repo.update!(Character.changeset(lyra, %{current_place_id: place.place_id}))
    end

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

  defp continuity_entry_count(campaign_id) do
    Repo.aggregate(
      from(entry in ContinuityEntry, where: entry.campaign_id == ^campaign_id),
      :count,
      :id
    )
  end

  defp complete_turn(campaign, session, key, action, provider) do
    assert {:ok, %{status: :completed}} =
             Play.submit_turn(campaign.id, session.id, key, action,
               provider: provider,
               model: "test-model"
             )
  end

  defp assert_provider_latency(campaign, session, key, provider, successful_calls) do
    provider_handler_id = {__MODULE__, make_ref()}
    resolution_handler_id = {__MODULE__, make_ref()}
    parent = self()
    expected_status = if successful_calls == 1, do: :completed, else: :failed

    :ok =
      :telemetry.attach(
        provider_handler_id,
        [:storyteller, :gm, :provider, :stop],
        fn event, measurements, metadata, _config ->
          send(parent, {:gm_latency, :provider, event, measurements, metadata})
        end,
        nil
      )

    :ok =
      :telemetry.attach(
        resolution_handler_id,
        [:storyteller, :gm, :resolution, :stop],
        fn event, measurements, metadata, _config ->
          send(parent, {:gm_latency, :resolution, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn ->
      :telemetry.detach(provider_handler_id)
      :telemetry.detach(resolution_handler_id)
    end)

    assert {:ok, %{status: ^expected_status}} =
             Play.submit_turn(campaign.id, session.id, key, "Look around.",
               provider: provider,
               model: "test-model"
             )

    assert_receive {:gm_latency, :provider, [:storyteller, :gm, :provider, :stop],
                    provider_metrics, %{}}

    assert_receive {:gm_latency, :resolution, [:storyteller, :gm, :resolution, :stop],
                    resolution_metrics, %{}}

    assert_numeric_latency_measurements(provider_metrics, successful_calls)
    assert_numeric_latency_measurements(resolution_metrics, successful_calls)
    assert provider_metrics.duration <= resolution_metrics.duration
  end

  defp assert_numeric_latency_measurements(measurements, successful_calls) do
    assert is_integer(measurements.duration) and measurements.duration >= 0
    assert measurements.success == successful_calls
    assert measurements.failure == 1 - successful_calls
    assert Enum.all?(Map.values(measurements), &(is_integer(&1) and &1 >= 0))
    refute Map.has_key?(measurements, :campaign_id)
    refute Map.has_key?(measurements, :prompt)
  end

  defp assert_private_text_rejected(campaign, session, key, overrides) do
    assert {:ok, %{status: :failed, failure_code: "invalid_response"}} =
             Play.submit_turn(campaign.id, session.id, key, "Look around carefully.",
               provider: ordinary_provider(overrides),
               model: "test-model"
             )

    assert {:ok, []} = Play.public_timeline(campaign.id)
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
        "time_advance_minutes" => 0,
        "character_updates" => [
          %{
            "speaker_id" => "npc:lyra",
            "visible_facts" => %{"last_spoke" => "The eastern star moved once."},
            "gm_private_facts" => %{"still_hidden" => true}
          }
        ],
        "location_changes" => [],
        "continuity_changes" => [],
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
      "continuity_changes" => [],
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
