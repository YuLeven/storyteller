defmodule StorytellerWeb.CampaignAuthoringLiveTest do
  use StorytellerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyteller.CampaignFixtures
  import Ecto.Query, only: [from: 2]

  alias Storyteller.Campaigns
  alias Storyteller.Campaigns.AuthoringCorrection
  alias Storyteller.Play
  alias Storyteller.Play.Character
  alias Storyteller.Play.Event
  alias Storyteller.Play.State
  alias Storyteller.Repo

  test "campaign editor adds an unplaced GM character with private voice guidance", %{conn: conn} do
    campaign =
      campaign_fixture(%{
        starting_location: "Quiet Observatory",
        player_character_name: "Ilya",
        player_character: "A patient courier.",
        gm_characters: [%{speaker_id: "mara_voss", name: "Existing Mara"}]
      })

    [session] = campaign.sessions
    {:ok, initial_projection} = Play.public_projection(campaign.id)
    [public_place | _] = initial_projection.places
    state_before = Repo.get_by!(State, campaign_id: campaign.id)

    event_count_before =
      Repo.aggregate(from(event in Event, where: event.campaign_id == ^campaign.id), :count)

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")

    assert has_element?(
             view,
             "#new-gm-character:not([open]) summary",
             "Add a GM-controlled character"
           )

    assert has_element?(
             view,
             "#new-gm-character option[value='#{public_place.place_id}']",
             "Quiet Observatory"
           )

    new_character = %{
      "name" => "Mara Voss",
      "visible_facts_text" => "A patient keeper who tends the observatory lamps.",
      "private_notes" => "She hid the original star chart beneath the west stair.",
      "place_id" => "",
      "voice_guidance" => %{
        "quirks" => "Counts each lens before dusk.",
        "accent_dialect" => "Soft island vowels.",
        "cadence" => "Measured pauses.",
        "vocabulary" => "Calls the telescope a skyglass.",
        "mannerisms" => "Touches the brass ring when thinking."
      }
    }

    render_change(view, "validate", %{"campaign" => %{"new_gm_character" => new_character}})
    render_change(view, "validate", %{"campaign" => %{"title" => campaign.title}})

    html =
      render_submit(view, "save", %{"campaign" => %{"title" => campaign.title}})

    assert html =~ "Campaign changes saved."
    assert has_element?(view, "#new-gm-character:not([open]) summary")

    character = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "mara_voss_2")
    assert character.role == :gm
    assert character.name == "Mara Voss"
    assert is_nil(character.current_place_id)

    assert character.visible_facts["description"] ==
             "A patient keeper who tends the observatory lamps."

    assert character.gm_private_facts["notes"] ==
             "She hid the original star chart beneath the west stair."

    assert character.voice_guidance == %{
             "quirks" => "Counts each lens before dusk.",
             "accent_dialect" => "Soft island vowels.",
             "cadence" => "Measured pauses.",
             "vocabulary" => "Calls the telescope a skyglass.",
             "mannerisms" => "Touches the brass ring when thinking."
           }

    correction = Repo.get_by!(AuthoringCorrection, campaign_id: campaign.id)
    assert correction.contains_private_changes

    assert correction.after_state["gm_characters"][character.speaker_id]["voice_guidance"] ==
             character.voice_guidance

    assert Campaigns.list_public_authoring_corrections(campaign.id) == []

    assert {:ok, projection} = Play.public_projection(campaign.id)
    public_character = Enum.find(projection.characters, &(&1.speaker_id == character.speaker_id))
    assert is_nil(public_character.current_place_id)
    refute Jason.encode!(projection) =~ "west stair"
    refute Jason.encode!(projection) =~ "Soft island vowels"

    state_after = Repo.get_by!(State, campaign_id: campaign.id)
    assert state_after.elapsed_world_minutes == state_before.elapsed_world_minutes
    assert state_after.event_sequence == state_before.event_sequence

    assert Repo.aggregate(from(event in Event, where: event.campaign_id == ^campaign.id), :count) ==
             event_count_before

    {:ok, reopened_view, reopened_html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")
    assert has_element?(reopened_view, "#facts-mara_voss_2")
    assert reopened_html =~ "She hid the original star chart beneath the west stair."
    assert reopened_html =~ "Counts each lens before dusk."
    assert reopened_html =~ "Touches the brass ring when thinking."

    captured_context = Agent.start_link(fn -> nil end) |> elem(1)

    proposal = %{
      "narration" => "Mara studies the lamps beside the telescope.",
      "dialogue" => [],
      "activities" => [],
      "public_changes" => %{},
      "private_changes" => %{},
      "panel_changes" => [],
      "memory_update" => %{"public_summary" => "", "gm_private_summary" => ""},
      "time_advance_minutes" => 0,
      "character_updates" => [],
      "character_creations" => [],
      "location_changes" => [],
      "inventory_changes" => [],
      "objective_changes" => [],
      "continuity_changes" => [],
      "roll_request" => nil
    }

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "new-gm-character-voice-context",
               "Ask Mara Voss what she noticed at the lamps.",
               provider: fn request ->
                 context = decode_provider_request(request)
                 Agent.update(captured_context, fn _ -> context end)
                 {:ok, Jason.encode!(proposal)}
               end,
               model: "test-model"
             )

    context_character =
      captured_context
      |> Agent.get(& &1)
      |> Map.fetch!("characters")
      |> Enum.find(&(&1["speaker_id"] == "mara_voss_2"))

    assert context_character["voice_guidance"] == character.voice_guidance
  end

  test "campaign editor rejects an invalid new character without partial writes", %{conn: conn} do
    campaign = campaign_fixture(%{starting_location: "Quiet Observatory"})
    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")

    draft = %{
      "name" => "Mara Voss",
      "visible_facts_text" => "A keeper.",
      "private_notes" => "A private secret.",
      "place_id" => "not-a-canonical-place",
      "voice_guidance" => %{"accent_dialect" => "A soft island lilt."}
    }

    render_change(view, "validate", %{"campaign" => %{"new_gm_character" => draft}})

    changed_title = "Must remain unchanged on rejected addition"

    html =
      render_submit(view, "save", %{"campaign" => %{"title" => changed_title}})

    assert html =~
             "Character details must use the listed fields and stay within the length limits."

    assert has_element?(view, "input[name='campaign[new_gm_character][name]'][value='Mara Voss']")
    assert has_element?(view, "#new-gm-character[open]")
    assert Campaigns.get_campaign!(campaign.id).title == campaign.title
    assert Repo.get_by(Character, campaign_id: campaign.id, speaker_id: "mara_voss") == nil

    assert Repo.aggregate(
             from(correction in AuthoringCorrection,
               where: correction.campaign_id == ^campaign.id
             ),
             :count
           ) == 0

    {:ok, projection} = Play.public_projection(campaign.id)

    over_limit_draft = %{
      "name" => "Mara Voss",
      "visible_facts_text" => "A keeper.",
      "private_notes" => "A private secret.",
      "place_id" => hd(projection.places).place_id,
      "voice_guidance" => %{"accent_dialect" => String.duplicate("x", 281)}
    }

    render_change(view, "validate", %{"campaign" => %{"new_gm_character" => over_limit_draft}})

    html =
      render_submit(view, "save", %{"campaign" => %{"title" => campaign.title}})

    assert html =~
             "Voice notes must be 280 characters or fewer per field and 1200 characters total."

    assert has_element?(view, "#new-gm-character[open]")

    assert has_element?(
             view,
             "textarea[name='campaign[new_gm_character][voice_guidance][accent_dialect]']"
           )

    assert Campaigns.get_campaign!(campaign.id).title == campaign.title
    assert Repo.get_by(Character, campaign_id: campaign.id, speaker_id: "mara_voss") == nil
  end

  test "blank add-character controls do not block other campaign edits", %{conn: conn} do
    campaign = campaign_fixture()
    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")

    blank_character = %{
      "name" => "",
      "visible_facts_text" => "",
      "private_notes" => "",
      "place_id" => "",
      "voice_guidance" => %{
        "quirks" => "",
        "accent_dialect" => "",
        "cadence" => "",
        "vocabulary" => "",
        "mannerisms" => ""
      }
    }

    html =
      render_submit(view, "save", %{
        "campaign" => %{
          "title" => "Edited with blank add-character controls",
          "new_gm_character" => blank_character
        }
      })

    assert html =~ "Campaign changes saved."
    assert Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")

    assert Repo.get_by(Character,
             campaign_id: campaign.id,
             speaker_id: "edited_with_blank_add_character_controls"
           ) == nil
  end

  test "campaign editor places a new GM character only at the selected public place", %{
    conn: conn
  } do
    campaign = campaign_fixture(%{starting_location: "Quiet Observatory"})
    {:ok, projection} = Play.public_projection(campaign.id)
    public_place = hd(projection.places)
    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")

    view
    |> form("#campaign-edit-form",
      campaign: %{
        title: campaign.title,
        new_gm_character: %{
          name: "Tern Vale",
          place_id: public_place.place_id
        }
      }
    )
    |> render_submit()

    character = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "tern_vale")
    assert character.current_place_id == public_place.place_id
  end

  test "campaign editor uses only an explicitly selected public place for a new character", %{
    conn: conn
  } do
    campaign = campaign_fixture(%{starting_location: "Quiet Observatory"})
    {:ok, projection} = Play.public_projection(campaign.id)
    public_place = hd(projection.places)
    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")

    assert has_element?(view, "#new-gm-character option[value='#{public_place.place_id}']")

    view
    |> form("#campaign-edit-form",
      campaign: %{
        title: campaign.title,
        new_gm_character: %{
          name: "Tern Vale",
          place_id: public_place.place_id
        }
      }
    )
    |> render_submit()

    character = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "tern_vale")
    assert character.current_place_id == public_place.place_id
  end

  test "campaign editor rejects adding a character while a turn is unresolved", %{conn: conn} do
    campaign = campaign_fixture()
    [session] = campaign.sessions

    assert {:ok, %{status: :pending}} =
             Play.submit_turn(campaign.id, session.id, "pending-edit-turn", "Look around.")

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")

    html =
      render_submit(view, "save", %{
        "campaign" => %{
          "title" => "Should wait until the turn finishes",
          "new_gm_character" => %{"name" => "New Arrival"}
        }
      })

    assert html =~ "Wait for the game master to finish the turn"
    assert Campaigns.get_campaign!(campaign.id).title == campaign.title
    assert Repo.get_by(Character, campaign_id: campaign.id, speaker_id: "new_arrival") == nil
  end

  test "campaign setup captures bounded GM-only character voice guidance", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    view |> element("button[phx-click='add-character']") |> render_click()

    assert has_element?(view, "#gm-character-0 details > summary", "Character voice guidance")

    attrs = %{
      title: "The Lantern Watch",
      premise: "A signal has returned to the empty harbor.",
      setting: "A quiet coastal town",
      tone: "Grounded and mysterious",
      narration_language: "English",
      player_character_name: "Ilya",
      player_character: "A patient courier",
      gm_characters: %{
        "0" => %{
          name: "Captain Ren",
          visible_facts_text: "A careful harbor officer.",
          voice_guidance: %{
            quirks: "Taps the compass twice.",
            accent_dialect: "Soft coastal vowels.",
            cadence: "Measured pauses.",
            vocabulary: "Uses harbor terms.",
            mannerisms: "Checks the tide before answering."
          }
        }
      }
    }

    review_html = view |> form("#campaign-form", campaign: attrs) |> render_submit()
    assert review_html =~ "Captain Ren"
    assert Campaigns.list_campaigns() == []

    view |> element("button[phx-click=create]") |> render_click()
    campaign = hd(Campaigns.list_campaigns())
    character = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "captain_ren")
    assert character.voice_guidance["accent_dialect"] == "Soft coastal vowels."
    assert character.visible_facts["description"] == "A careful harbor officer."

    assert {:ok, projection} = Play.public_projection(campaign.id)
    refute Jason.encode!(projection) =~ "Soft coastal vowels"
  end

  test "campaign setup displays the combined voice-note character count", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")
    view |> element("button[phx-click='add-character']") |> render_click()

    voice =
      Map.new(Storyteller.Play.VoiceGuidance.fields(), fn field ->
        {field, String.duplicate("x", 250)}
      end)

    render_change(view, "validate", %{
      "campaign" => %{
        "gm_characters" => %{
          "0" => %{"name" => "Captain Ren", "voice_guidance" => voice}
        }
      }
    })

    html = render(view)
    assert html =~ "1250 of 1200 characters used"
    assert html =~ "These notes exceed the combined limit. Shorten them to continue."
  end

  test "campaign setup routes opening-scene field errors to the opening-scene step", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    attrs = %{
      title: "The Lantern Watch",
      premise: "A signal has returned to the empty harbor.",
      setting: "A quiet coastal town",
      tone: "Grounded and mysterious",
      narration_language: "English",
      player_character_name: "Ilya",
      player_character: "A patient courier.",
      weather: String.duplicate("w", 501)
    }

    for step <- 1..3 do
      view
      |> form("#campaign-form", campaign: attrs)
      |> put_submitter("button[name=direction][value=continue]")
      |> render_submit()

      if step < 3 do
        assert has_element?(view, "#campaign-setup-step-#{step + 1}:not([hidden])")
      end
    end

    html =
      view
      |> form("#campaign-form", campaign: attrs)
      |> put_submitter("button[name=direction][value=continue]")
      |> render_submit()

    assert has_element?(view, "#campaign-setup-step-3:not([hidden])")
    refute has_element?(view, "#campaign-setup-step-4:not([hidden])")
    assert html =~ "should be at most 500 character(s)"
    assert Campaigns.list_campaigns() == []
  end

  test "campaign editor saves story setup and known character voices", %{conn: conn} do
    campaign =
      campaign_fixture(%{
        player_character_name: "Ilya",
        player_character: "A patient harbor courier who studies the tides.",
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

    [session] = campaign.sessions
    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")

    assert has_element?(view, "#campaign-edit-form")
    assert has_element?(view, "input[name='campaign[player_character_name]']")
    assert has_element?(view, "textarea[name='campaign[player_character]']")

    assert has_element?(view, "#facts-keeper-elin details > summary", "Voice and mannerisms")
    refute has_element?(view, "h2", "Character voice guidance")

    assert has_element?(
             view,
             "textarea[name='campaign[character_voice_guidance][keeper-elin][cadence]']"
           )

    assert has_element?(view, "textarea[name='campaign[player_character]']")

    assert has_element?(
             view,
             "textarea[name='campaign[gm_character_setup][keeper-elin][private_notes]']"
           )

    attrs = %{
      correction_reason: "Clarify the lighthouse setup and private signal.",
      title: "The Beacon at Low Tide",
      premise: "A new signal arrives from the outer reef.",
      setting: "A fictional island harbor",
      tone: "Warm and quietly suspenseful",
      narration_language: "French",
      player_character_name: "Ilya Venn",
      player_character: "A patient harbor courier who knows every island path.",
      gm_character_setup: %{
        "keeper-elin" => %{
          visible_facts_text: "Maintains the lighthouse and studies the reef lights.",
          private_notes: "She has found a second private signal beneath the lower lens."
        }
      },
      character_voice_guidance: %{
        "keeper-elin" => %{
          quirks: "Counts the shutters before opening them.",
          accent_dialect: "Gentle island lilt.",
          cadence: "Slow and deliberate.",
          vocabulary: "Calls storms squalls.",
          mannerisms: "Touches the brass key at her belt."
        }
      }
    }

    html = view |> form("#campaign-edit-form", campaign: attrs) |> render_submit()
    assert html =~ "Setup correction history"
    refute html =~ "Clarify the lighthouse setup and private signal."

    correction = Repo.get_by!(AuthoringCorrection, campaign_id: campaign.id)
    assert correction.contains_private_changes

    updated = Campaigns.get_campaign!(campaign.id)
    assert updated.title == "The Beacon at Low Tide"
    assert updated.premise == "A new signal arrives from the outer reef."
    assert updated.narration_language == "French"
    assert updated.player_character_name == "Ilya Venn"
    assert updated.player_character == "A patient harbor courier who knows every island path."
    assert [%{id: session_id}] = updated.sessions
    assert session_id == session.id

    character = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "keeper-elin")
    assert character.voice_guidance["mannerisms"] == "Touches the brass key at her belt."

    assert character.visible_facts["description"] ==
             "Maintains the lighthouse and studies the reef lights."

    assert character.visible_facts["role"] == "Keeps the western beacon lit."

    assert character.gm_private_facts["notes"] ==
             "She has found a second private signal beneath the lower lens."

    player = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")
    assert player.name == "Ilya Venn"

    assert player.visible_facts["description"] ==
             "A patient harbor courier who knows every island path."

    {:ok, _detail_view, detail_html} = live(conn, ~p"/campaigns/#{campaign.id}")
    assert detail_html =~ "Character name"
    assert detail_html =~ "Ilya Venn"
    assert detail_html =~ "Character description"
    assert detail_html =~ "A patient harbor courier who knows every island path."
  end

  test "campaign editor keeps voice edits through validation and reload", %{
    conn: conn
  } do
    campaign =
      campaign_fixture(%{
        starting_location: "Quiet Observatory",
        player_character_name: "Ilya",
        player_character: "A patient courier.",
        gm_characters: [
          %{
            speaker_id: "keeper-elin",
            name: "Keeper Elin",
            starting_place: "Quiet Observatory",
            voice_guidance: %{}
          }
        ]
      })

    [session] = campaign.sessions
    {:ok, view, initial_html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")
    refute has_element?(view, "#facts-keeper-elin details[open]")
    refute has_element?(view, "#campaign-correction-reason[required]")

    reason_position =
      initial_html |> :binary.match("id=\"campaign-correction-reason\"") |> elem(0)

    voice_position =
      initial_html
      |> :binary.match("name=\"campaign[character_voice_guidance][keeper-elin][mannerisms]\"")
      |> elem(0)

    assert reason_position < voice_position

    attrs = %{
      title: campaign.title,
      premise: campaign.premise,
      setting: campaign.setting,
      tone: campaign.tone,
      narration_language: campaign.narration_language,
      player_character_name: campaign.player_character_name,
      player_character: campaign.player_character,
      character_voice_guidance: %{
        "keeper-elin" => %{
          quirks: "Counts the shutters twice.",
          accent_dialect: "A gentle island lilt.",
          cadence: "Pauses before every answer.",
          vocabulary: "Calls storms squalls.",
          mannerisms: "Turns the brass key while she thinks."
        }
      }
    }

    view |> form("#campaign-edit-form", campaign: attrs) |> render_change()

    assert render(view) =~ "Counts the shutters twice."
    assert render(view) =~ "A gentle island lilt."
    assert render(view) =~ "Pauses before every answer."
    assert render(view) =~ "Calls storms squalls."
    assert render(view) =~ "Turns the brass key while she thinks."
    assert has_element?(view, "#facts-keeper-elin details[open]")

    html = view |> form("#campaign-edit-form") |> render_submit()
    assert html =~ "Campaign changes saved."

    assert has_element?(
             view,
             "#campaign-edit-save-feedback[role='status']",
             "Campaign changes saved."
           )

    assert has_element?(view, "#facts-keeper-elin details[open]")

    correction = Repo.get_by!(AuthoringCorrection, campaign_id: campaign.id)
    assert correction.reason == "Campaign setup updated"

    saved_character =
      Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "keeper-elin")

    assert saved_character.voice_guidance["quirks"] == "Counts the shutters twice."
    assert saved_character.voice_guidance["accent_dialect"] == "A gentle island lilt."
    assert saved_character.voice_guidance["cadence"] == "Pauses before every answer."
    assert saved_character.voice_guidance["vocabulary"] == "Calls storms squalls."
    assert saved_character.voice_guidance["mannerisms"] == "Turns the brass key while she thinks."

    {:ok, reopened_view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")
    reopened_html = render(reopened_view)
    assert has_element?(reopened_view, "#facts-keeper-elin details[open]")
    assert reopened_html =~ "Counts the shutters twice."
    assert reopened_html =~ "A gentle island lilt."
    assert reopened_html =~ "Pauses before every answer."
    assert reopened_html =~ "Calls storms squalls."
    assert reopened_html =~ "Turns the brass key while she thinks."

    captured_context = Agent.start_link(fn -> nil end) |> elem(1)

    proposal = %{
      "narration" => "The keeper studies the late stars over the quiet observatory.",
      "dialogue" => [],
      "activities" => [],
      "public_changes" => %{},
      "private_changes" => %{},
      "panel_changes" => [],
      "memory_update" => %{"public_summary" => "", "gm_private_summary" => ""},
      "time_advance_minutes" => 0,
      "character_updates" => [],
      "character_creations" => [],
      "location_changes" => [],
      "inventory_changes" => [],
      "objective_changes" => [],
      "continuity_changes" => [],
      "roll_request" => nil
    }

    assert {:ok, %{status: :completed}} =
             Play.submit_turn(
               campaign.id,
               session.id,
               "edited-voice-provider-context",
               "Ask Keeper Elin about the star charts.",
               provider: fn request ->
                 context = decode_provider_request(request)
                 Agent.update(captured_context, fn _ -> context end)
                 {:ok, Jason.encode!(proposal)}
               end,
               model: "test-model"
             )

    request_context = Agent.get(captured_context, & &1)
    keeper = Enum.find(request_context["characters"], &(&1["speaker_id"] == "keeper-elin"))

    assert keeper["current_place"]["name"] == "Quiet Observatory"

    assert keeper["voice_guidance"] == %{
             "quirks" => "Counts the shutters twice.",
             "accent_dialect" => "A gentle island lilt.",
             "cadence" => "Pauses before every answer.",
             "vocabulary" => "Calls storms squalls.",
             "mannerisms" => "Turns the brass key while she thinks."
           }
  end

  test "campaign editor strips unused input markers and retains voice drafts", %{conn: conn} do
    campaign =
      campaign_fixture(%{
        gm_characters: [
          %{speaker_id: "npc:cellar-keeper", name: "Marcel", voice_guidance: %{}}
        ]
      })

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")

    # Phoenix adds `_unused_*` metadata for untouched controls during
    # phx-change. A later partial submit must not pass those UI markers to
    # the strict campaign authoring validators.
    validated_attrs = %{
      "correction_reason" => "Clarify how Marcel speaks and moves.",
      "gm_character_setup" => %{
        "npc:cellar-keeper" => %{
          "_unused_visible_facts_text" => "",
          "_unused_private_notes" => "",
          "visible_facts_text" => "",
          "private_notes" => ""
        }
      },
      "character_active_duties" => %{
        "npc:cellar-keeper" => %{
          "_unused_duty_name" => "",
          "_unused_duty_duration_minutes" => "",
          "duty_name" => "",
          "duty_duration_minutes" => ""
        }
      },
      "character_voice_guidance" => %{
        "npc:cellar-keeper" => %{
          "_unused_accent_dialect" => "",
          "_unused_mannerisms" => "",
          "_unused_cadence" => "",
          "_unused_quirks" => "",
          "_unused_vocabulary" => "",
          "accent_dialect" => "Warm French vowels.",
          "mannerisms" => "Taps the wine thief against the barrel before speaking."
        }
      }
    }

    render_change(view, "validate", %{"campaign" => validated_attrs})

    # A later validation and submit may carry only fields that changed. They
    # must not discard voice notes or the correction reason from earlier events.
    render_change(view, "validate", %{"campaign" => %{"title" => campaign.title}})

    html =
      render_submit(view, "save", %{"campaign" => %{"title" => campaign.title}})

    assert html =~ "Campaign changes saved."

    character = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "npc:cellar-keeper")

    assert character.voice_guidance == %{
             "accent_dialect" => "Warm French vowels.",
             "mannerisms" => "Taps the wine thief against the barrel before speaking."
           }

    {:ok, reopened_view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")
    reopened_html = render(reopened_view)
    assert reopened_html =~ "Warm French vowels."
    assert reopened_html =~ "Taps the wine thief against the barrel before speaking."
  end

  test "campaign editor saves voice changes across multiple characters after partial validation",
       %{
         conn: conn
       } do
    campaign =
      campaign_fixture(%{
        gm_characters: [
          %{
            speaker_id: "keeper-elin",
            name: "Keeper Elin",
            voice_guidance: %{
              "quirks" => "Counts the shutters.",
              "accent_dialect" => "Old harbor vowels.",
              "cadence" => "Slow and deliberate.",
              "vocabulary" => "Uses lighthouse terms.",
              "mannerisms" => "Touches a brass key."
            }
          },
          %{
            speaker_id: "captain-ren",
            name: "Captain Ren",
            voice_guidance: %{
              "quirks" => "Taps the compass twice.",
              "accent_dialect" => "North-coast lilt.",
              "cadence" => "Short measured phrases.",
              "vocabulary" => "Uses sailing terms.",
              "mannerisms" => "Checks the tide chart."
            }
          }
        ]
      })

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")

    voice_edits = %{
      "keeper-elin" => %{
        quirks: "Counts the windows before opening them.",
        accent_dialect: "A gentle island lilt.",
        cadence: "Pauses before every answer.",
        vocabulary: "Calls storms squalls.",
        mannerisms: "Turns the brass key while she thinks."
      },
      "captain-ren" => %{
        accent_dialect: "A clipped, formal harbor accent.",
        mannerisms: ""
      }
    }

    render_change(view, "validate", %{
      "campaign" => %{"character_voice_guidance" => voice_edits}
    })

    assert has_element?(view, "#facts-keeper-elin details[open]")
    assert has_element?(view, "#facts-captain-ren details[open]")
    assert render(view) =~ "Turns the brass key while she thinks."
    assert render(view) =~ "A clipped, formal harbor accent."

    # A subsequent partial validation must not discard the nested voice draft.
    render_change(view, "validate", %{"campaign" => %{"title" => campaign.title}})

    # Submit the rendered form without replaying the voice values in test params,
    # as a player does after making changes in the editor.
    html = view |> form("#campaign-edit-form") |> render_submit()
    assert html =~ "Campaign changes saved."

    assert has_element?(
             view,
             "#campaign-edit-save-feedback[role='status']",
             "Campaign changes saved."
           )

    keeper = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "keeper-elin")

    assert keeper.voice_guidance == %{
             "quirks" => "Counts the windows before opening them.",
             "accent_dialect" => "A gentle island lilt.",
             "cadence" => "Pauses before every answer.",
             "vocabulary" => "Calls storms squalls.",
             "mannerisms" => "Turns the brass key while she thinks."
           }

    captain = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "captain-ren")

    assert captain.voice_guidance == %{
             "quirks" => "Taps the compass twice.",
             "accent_dialect" => "A clipped, formal harbor accent.",
             "cadence" => "Short measured phrases.",
             "vocabulary" => "Uses sailing terms."
           }

    {:ok, reopened_view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")

    for {speaker_id, field, value} <- [
          {"keeper-elin", "quirks", "Counts the windows before opening them."},
          {"keeper-elin", "accent_dialect", "A gentle island lilt."},
          {"keeper-elin", "cadence", "Pauses before every answer."},
          {"keeper-elin", "vocabulary", "Calls storms squalls."},
          {"keeper-elin", "mannerisms", "Turns the brass key while she thinks."},
          {"captain-ren", "quirks", "Taps the compass twice."},
          {"captain-ren", "accent_dialect", "A clipped, formal harbor accent."},
          {"captain-ren", "cadence", "Short measured phrases."},
          {"captain-ren", "vocabulary", "Uses sailing terms."}
        ] do
      assert has_element?(
               reopened_view,
               "textarea[name='campaign[character_voice_guidance][#{speaker_id}][#{field}]']",
               value
             )
    end

    cleared_mannerisms =
      reopened_view
      |> element("textarea[name='campaign[character_voice_guidance][captain-ren][mannerisms]']")
      |> render()

    refute cleared_mannerisms =~ "Checks the tide chart."
  end

  test "campaign editor explains and preserves voice notes over the combined limit", %{
    conn: conn
  } do
    campaign =
      campaign_fixture(%{
        player_character_name: "Ilya",
        player_character: "A patient courier.",
        gm_characters: [%{speaker_id: "keeper-elin", name: "Keeper Elin", voice_guidance: %{}}]
      })

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")

    voice =
      Map.new(Storyteller.Play.VoiceGuidance.fields(), fn field ->
        {field, String.duplicate("x", 250)}
      end)

    params = %{
      "correction_reason" => "Clarify the keeper's voice.",
      "character_voice_guidance" => %{"keeper-elin" => voice}
    }

    render_change(view, "validate", %{"campaign" => params})
    html = render(view)
    assert html =~ "1250 of 1200 characters used"
    assert html =~ "These notes exceed the combined limit. Shorten them to continue."

    html = render_submit(view, "save", %{"campaign" => params})

    assert html =~
             "Voice notes must be 280 characters or fewer per field and 1200 characters total."

    assert has_element?(
             view,
             "#campaign-edit-save-feedback[role='alert']",
             "Voice notes must be 280 characters or fewer per field and 1200 characters total."
           )

    assert html =~ "1250 of 1200 characters used"

    saved = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "keeper-elin")
    assert saved.voice_guidance == %{}
  end

  test "campaign editor rejects stale voice edits from another tab and preserves them for review",
       %{
         conn: conn
       } do
    campaign =
      campaign_fixture(%{
        gm_characters: [
          %{
            speaker_id: "keeper-elin",
            name: "Keeper Elin",
            voice_guidance: %{"mannerisms" => "Turns a brass key."}
          }
        ]
      })

    {:ok, first_view, _first_html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")
    {:ok, stale_view, _stale_html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")

    first_html =
      first_view
      |> form("#campaign-edit-form",
        campaign: %{
          expected_authoring_revision: "0",
          character_voice_guidance: %{
            "keeper-elin" => %{mannerisms: "Turns the brass key while she thinks."}
          }
        }
      )
      |> render_submit()

    assert first_html =~ "Campaign changes saved."

    stale_html =
      stale_view
      |> form("#campaign-edit-form",
        campaign: %{
          expected_authoring_revision: "0",
          character_voice_guidance: %{
            "keeper-elin" => %{
              accent_dialect: "A soft coastal lilt.",
              mannerisms: "Turns a brass key."
            }
          }
        }
      )
      |> render_submit()

    assert stale_html =~ "campaign changed while this setup was open"
    assert stale_html =~ "A soft coastal lilt."
    assert stale_html =~ "Turns a brass key."

    character = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "keeper-elin")

    assert character.voice_guidance == %{
             "mannerisms" => "Turns the brass key while she thinks."
           }

    retry_html =
      stale_view
      |> form("#campaign-edit-form",
        campaign: %{
          expected_authoring_revision: "1",
          character_voice_guidance: %{
            "keeper-elin" => %{
              accent_dialect: "A soft coastal lilt.",
              mannerisms: "Turns the brass key while she thinks."
            }
          }
        }
      )
      |> render_submit()

    assert retry_html =~ "Campaign changes saved."

    character = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "keeper-elin")

    assert character.voice_guidance == %{
             "accent_dialect" => "A soft coastal lilt.",
             "mannerisms" => "Turns the brass key while she thinks."
           }
  end

  test "campaign editor saves voice guidance when world time advances without changing a duty", %{
    conn: conn
  } do
    campaign =
      campaign_fixture(%{
        starting_location: "The Observatory",
        gm_characters: [
          %{
            speaker_id: "keeper-elin",
            name: "Keeper Elin",
            starting_place: "The Observatory"
          }
        ]
      })

    assert {:ok, _campaign} =
             Campaigns.update_campaign_authoring(campaign, %{
               "correction_reason" => "Assign Elin to the observatory watch.",
               "expected_revision" => "0",
               "character_active_duties" => %{
                 "keeper-elin" => %{
                   "duty_name" => "Watch the western lens",
                   "duty_duration_minutes" => "90"
                 }
               }
             })

    character = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "keeper-elin")
    assert character.duty_release_at_world_minute == 90

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")

    state = Repo.get_by!(State, campaign_id: campaign.id)

    assert {:ok, _advanced_state} =
             state
             |> State.changeset(%{
               revision: state.revision + 1,
               elapsed_world_minutes: 10,
               elapsed_world_anchor_minutes: 10
             })
             |> Repo.update()

    html =
      view
      |> form("#campaign-edit-form",
        campaign: %{
          correction_reason: "Give Elin a distinct delivery.",
          expected_revision: "1",
          character_active_duties: %{
            "keeper-elin" => %{
              duty_name: "Watch the western lens",
              duty_duration_minutes: "90"
            }
          },
          character_voice_guidance: %{
            "keeper-elin" => %{
              accent_dialect: "A soft coastal lilt.",
              mannerisms: "Turns the brass key while she thinks."
            }
          }
        }
      )
      |> render_submit()

    assert html =~ "Campaign changes saved."

    character = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "keeper-elin")
    assert character.voice_guidance["accent_dialect"] == "A soft coastal lilt."
    assert character.voice_guidance["mannerisms"] == "Turns the brass key while she thinks."
    assert character.duty_release_at_world_minute == 90
  end

  test "campaign editor authors a private active duty and rejects stale or in-flight changes", %{
    conn: conn
  } do
    campaign =
      campaign_fixture(%{
        starting_location: "The Finca",
        gm_characters: [
          %{
            speaker_id: "keeper-elin",
            name: "Keeper Elin",
            starting_place: "The Finca"
          }
        ]
      })

    [session] = campaign.sessions
    {:ok, view, html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")
    {:ok, stale_view, _stale_html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")
    assert html =~ "Active duty (GM only, optional)"
    assert html =~ "Minutes until available (in-world)"
    assert has_element?(view, "input[name='campaign[expected_revision]']")

    assignment_attrs = %{
      correction_reason: "Elin is responsible for the evening beacon checks.",
      expected_revision: "0",
      character_active_duties: %{
        "keeper-elin" => %{
          duty_name: "Check the evening beacon",
          duty_duration_minutes: "90"
        }
      }
    }

    html = view |> form("#campaign-edit-form", campaign: assignment_attrs) |> render_submit()
    refute html =~ "Elin is responsible for the evening beacon checks."
    character = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "keeper-elin")
    assert character.duty_name == "Check the evening beacon"
    assert character.duty_place_id == character.current_place_id
    assert character.duty_release_at_world_minute == 90
    correction = Repo.get_by!(AuthoringCorrection, campaign_id: campaign.id)
    assert correction.contains_private_changes

    stale_attrs = %{
      correction_reason: "Try to replace the duty from an older editor tab.",
      character_active_duties: %{
        "keeper-elin" => %{duty_name: "Check the press room"}
      }
    }

    stale_html =
      stale_view |> form("#campaign-edit-form", campaign: stale_attrs) |> render_submit()

    assert stale_html =~ "campaign changed while this setup was open"
    assert Repo.get_by!(Character, id: character.id).duty_name == "Check the evening beacon"

    assert {:ok, pending} =
             Play.submit_turn(campaign.id, session.id, "edit-duty-open-turn", "Look around.")

    assert pending.status == :pending

    in_flight_attrs = %{
      correction_reason: "Elin has finished the evening checks.",
      character_active_duties: %{"keeper-elin" => %{duty_name: ""}}
    }

    in_flight_html =
      view |> form("#campaign-edit-form", campaign: in_flight_attrs) |> render_submit()

    assert in_flight_html =~ "Wait for the game master to finish the turn"
    assert Repo.get_by!(Character, id: character.id).duty_name == "Check the evening beacon"
  end

  test "editor shows public correction receipts and omits corrections with private changes", %{
    conn: conn
  } do
    campaign =
      campaign_fixture(%{
        gm_characters: [
          %{
            speaker_id: "keeper-elin",
            name: "Keeper Elin",
            visible_facts: %{"description" => "Maintains the lighthouse."},
            gm_private_facts: %{"notes" => "Knows the lower lens is cracked."}
          }
        ]
      })

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")

    public_attrs = %{
      correction_reason: "Clarify the keeper's public duties.",
      title: campaign.title,
      premise: campaign.premise,
      setting: campaign.setting,
      tone: campaign.tone,
      narration_language: campaign.narration_language,
      player_character_name: campaign.player_character_name,
      player_character: campaign.player_character,
      gm_character_setup: %{
        "keeper-elin" => %{
          visible_facts_text: "Maintains the lighthouse and charts the reefs.",
          private_notes: "Knows the lower lens is cracked."
        }
      }
    }

    view |> form("#campaign-edit-form", campaign: public_attrs) |> render_submit()

    assert has_element?(
             view,
             "#authoring-correction-history li",
             "Clarify the keeper's public duties."
           )

    assert has_element?(view, "#authoring-correction-history li", "Character details")

    private_attrs = %{
      correction_reason: "Sensitive correction reason sentinel.",
      title: campaign.title,
      premise: campaign.premise,
      setting: campaign.setting,
      tone: campaign.tone,
      narration_language: campaign.narration_language,
      player_character_name: campaign.player_character_name,
      player_character: campaign.player_character,
      gm_character_setup: %{
        "keeper-elin" => %{
          visible_facts_text: "Maintains the lighthouse and charts the reefs.",
          private_notes: "A hidden stair leads into the old harbor tunnel."
        }
      }
    }

    view |> form("#campaign-edit-form", campaign: private_attrs) |> render_submit()

    assert has_element?(
             view,
             "#authoring-correction-history li",
             "Clarify the keeper's public duties."
           )

    refute has_element?(
             view,
             "#authoring-correction-history li",
             "Sensitive correction reason sentinel."
           )

    assert [public_correction] = Campaigns.list_public_authoring_corrections(campaign.id)
    assert public_correction.reason == "Clarify the keeper's public duties."

    private_correction =
      Repo.get_by!(AuthoringCorrection,
        campaign_id: campaign.id,
        reason: "Sensitive correction reason sentinel."
      )

    assert private_correction.contains_private_changes
  end

  defp decode_provider_request(request) do
    text = request.input |> hd() |> Map.fetch!(:content) |> hd() |> Map.fetch!(:text)
    Jason.decode!(text)
  end
end
