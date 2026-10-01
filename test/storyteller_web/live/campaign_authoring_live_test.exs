defmodule StorytellerWeb.CampaignAuthoringLiveTest do
  use StorytellerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyteller.CampaignFixtures

  alias Storyteller.Campaigns
  alias Storyteller.Campaigns.AuthoringCorrection
  alias Storyteller.Play
  alias Storyteller.Play.Character
  alias Storyteller.Repo

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
        player_character_name: "Ilya",
        player_character: "A patient courier.",
        gm_characters: [
          %{
            speaker_id: "keeper-elin",
            name: "Keeper Elin",
            voice_guidance: %{}
          }
        ]
      })

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")
    refute has_element?(view, "#facts-keeper-elin details[open]")

    attrs = %{
      correction_reason: "Clarify Elin's delivery.",
      title: campaign.title,
      premise: campaign.premise,
      setting: campaign.setting,
      tone: campaign.tone,
      narration_language: campaign.narration_language,
      player_character_name: campaign.player_character_name,
      player_character: campaign.player_character,
      character_voice_guidance: %{
        "keeper-elin" => %{
          cadence: "Pauses before every answer.",
          mannerisms: "Turns the brass key while she thinks."
        }
      }
    }

    view |> form("#campaign-edit-form", campaign: attrs) |> render_change()

    assert render(view) =~ "Pauses before every answer."
    assert render(view) =~ "Turns the brass key while she thinks."
    assert has_element?(view, "#facts-keeper-elin details[open]")

    html = view |> form("#campaign-edit-form", campaign: attrs) |> render_submit()
    assert html =~ "Campaign changes saved."
    assert has_element?(view, "#facts-keeper-elin details[open]")

    {:ok, reopened_view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")
    reopened_html = render(reopened_view)
    assert has_element?(reopened_view, "#facts-keeper-elin details[open]")
    assert reopened_html =~ "Pauses before every answer."
    assert reopened_html =~ "Turns the brass key while she thinks."
  end

  test "campaign editor saves voice guidance retained from change events", %{conn: conn} do
    campaign =
      campaign_fixture(%{
        gm_characters: [
          %{speaker_id: "npc:cellar-keeper", name: "Marcel", voice_guidance: %{}}
        ]
      })

    {:ok, view, _html} = live(conn, ~p"/campaigns/#{campaign.id}/edit")

    validated_attrs = %{
      "correction_reason" => "Clarify how Marcel speaks and moves.",
      "character_voice_guidance" => %{
        "npc:cellar-keeper" => %{
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
end
