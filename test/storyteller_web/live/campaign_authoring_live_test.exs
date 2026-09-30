defmodule StorytellerWeb.CampaignAuthoringLiveTest do
  use StorytellerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyteller.CampaignFixtures

  alias Storyteller.Campaigns
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
      player_character: "Ilya, a patient courier",
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
      title: "The Beacon at Low Tide",
      premise: "A new signal arrives from the outer reef.",
      setting: "A fictional island harbor",
      tone: "Warm and quietly suspenseful",
      narration_language: "French",
      player_character: "Ilya, a patient harbor courier",
      gm_character_setup: %{
        "keeper-elin" => %{
          visible_facts_text: "Maintains the lighthouse and studies the reef lights.",
          private_notes: "She has found a second signal beneath the lower lens."
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

    view |> form("#campaign-edit-form", campaign: attrs) |> render_submit()
    assert_redirect(view, ~p"/campaigns/#{campaign.id}")

    updated = Campaigns.get_campaign!(campaign.id)
    assert updated.title == "The Beacon at Low Tide"
    assert updated.premise == "A new signal arrives from the outer reef."
    assert updated.narration_language == "French"
    assert updated.player_character == "Ilya, a patient harbor courier"
    assert [%{id: session_id}] = updated.sessions
    assert session_id == session.id

    character = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "keeper-elin")
    assert character.voice_guidance["mannerisms"] == "Touches the brass key at her belt."

    assert character.visible_facts["description"] ==
             "Maintains the lighthouse and studies the reef lights."

    assert character.visible_facts["role"] == "Keeps the western beacon lit."

    assert character.gm_private_facts["notes"] ==
             "She has found a second signal beneath the lower lens."

    player = Repo.get_by!(Character, campaign_id: campaign.id, speaker_id: "player")
    assert player.name == "Ilya, a patient harbor courier"
    assert player.visible_facts["description"] == "Ilya, a patient harbor courier"
  end
end
