defmodule StorytellerWeb.CampaignLiveTest do
  use StorytellerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyteller.CampaignFixtures

  alias Storyteller.Campaigns
  alias Storyteller.Panels
  alias Storyteller.Play

  test "campaign list keeps two stories in separate cards and links to the right sessions", %{
    conn: conn
  } do
    first =
      campaign_fixture(%{
        title: "Lantern Coast",
        premise: "A ferry light vanishes in a storm.",
        player_character_name: "Sera Vale",
        player_character: "A ferry keeper who reads storm clouds."
      })

    second =
      campaign_fixture(%{
        title: "Copper Archive",
        premise: "A map is missing from the city collection.",
        player_character_name: "Niko Reed",
        player_character: "An archivist with a perfect memory."
      })

    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Campaigns"
    assert html =~ "Lantern Coast"
    assert html =~ "Copper Archive"

    first_card =
      html |> Floki.parse_document!() |> Floki.find("#campaign-#{first.id}") |> Floki.text()

    second_card =
      html |> Floki.parse_document!() |> Floki.find("#campaign-#{second.id}") |> Floki.text()

    assert first_card =~ "A ferry light vanishes in a storm."
    assert first_card =~ "Character: Sera Vale"
    refute first_card =~ "A ferry keeper who reads storm clouds."
    refute first_card =~ "A map is missing from the city collection."
    assert second_card =~ "A map is missing from the city collection."
    assert second_card =~ "Character: Niko Reed"
    refute second_card =~ "A ferry light vanishes in a storm."

    first_session = hd(first.sessions)
    second_session = hd(second.sessions)

    document = Floki.parse_document!(html)
    first_links = document |> Floki.find("#campaign-#{first.id} a") |> Floki.attribute("href")
    second_links = document |> Floki.find("#campaign-#{second.id} a") |> Floki.attribute("href")

    assert ~p"/campaigns/#{first.id}/sessions/#{first_session.id}" in first_links
    assert ~p"/campaigns/#{second.id}/sessions/#{second_session.id}" in second_links
  end

  test "campaign setup is reviewed before creation and its first session is resumable", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    attrs = %{
      title: "The Blue Lantern",
      premise: "A signal appears on the cliffs after a century of silence.",
      setting: "A fictional coastal city",
      tone: "Patient and hopeful",
      narration_language: "French",
      player_character_name: "Noa Marin",
      player_character: "A lighthouse keeper who listens for bells in fog."
    }

    review_html = view |> form("#campaign-form", campaign: attrs) |> render_submit()
    assert review_html =~ "Review your campaign"
    assert review_html =~ "The Blue Lantern"
    assert review_html =~ "Noa Marin"
    assert review_html =~ "Character description"
    assert review_html =~ "A lighthouse keeper who listens for bells in fog."
    assert Campaigns.list_campaigns() == []

    view |> element("button[phx-click=create]") |> render_click()
    campaign = hd(Campaigns.list_campaigns())
    assert campaign.title == "The Blue Lantern"
    assert campaign.player_character_name == "Noa Marin"
    assert campaign.player_character == "A lighthouse keeper who listens for bells in fog."
    assert [%{title: "Session 1", status: :active}] = campaign.sessions

    assert {:ok, projection} = Play.public_projection(campaign.id)
    player = Enum.find(projection.characters, &(&1.speaker_id == "player"))
    assert player.name == "Noa Marin"
    assert player.visible_facts["description"] == campaign.player_character

    assert_redirect(view, ~p"/campaigns/#{campaign.id}")
  end

  test "optional setup sections stay collapsed until they contain rows", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/campaigns/new")

    section_ids = [
      "player-character-details",
      "starting-inventory",
      "gm-characters",
      "campaign-panels"
    ]

    for section_id <- section_ids do
      assert has_element?(view, "details##{section_id}")
      refute has_element?(view, "details##{section_id}[open]")
    end

    assert html =~ "Optional"

    view |> element("button[phx-click=add-player-detail]") |> render_click()
    view |> element("button[phx-click=add-starting-item]") |> render_click()
    view |> element("button[phx-click=add-character]") |> render_click()
    view |> element("button[phx-click=add-panel-field]") |> render_click()

    for section_id <- section_ids do
      assert has_element?(view, "details##{section_id}[open]")
    end

    view |> element("button[phx-click=remove-player-detail]") |> render_click()
    view |> element("button[phx-click=remove-starting-item]") |> render_click()
    view |> element("button[phx-click=remove-character]") |> render_click()
    view |> element("button[phx-click=remove-panel-field]") |> render_click()

    for section_id <- section_ids do
      refute has_element?(view, "details##{section_id}[open]")
    end
  end

  test "GM character setup creates stable identities from names without showing internal IDs", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    view |> element("button[phx-click=add-character]") |> render_click()
    view |> element("button[phx-click=add-character]") |> render_click()
    view |> element("button[phx-click=add-character]") |> render_click()

    refute has_element?(view, "input[name='campaign[gm_characters][0][speaker_id]']")
    assert has_element?(view, "input[name='campaign[gm_characters][0][name]']")

    attrs = %{
      title: "The Lantern Watch",
      premise: "A signal has returned to the empty harbor.",
      setting: "A quiet coastal town",
      tone: "Grounded and mysterious",
      narration_language: "English",
      player_character_name: "Ilya",
      player_character: "A patient courier",
      gm_characters: %{
        "0" => %{name: "Captain Ren"},
        "1" => %{name: "Captain Ren"},
        "2" => %{name: "Player"}
      }
    }

    review_html = view |> form("#campaign-form", campaign: attrs) |> render_submit()
    assert review_html =~ "Captain Ren"
    assert review_html =~ "Player"
    refute review_html =~ "captain_ren"
    refute review_html =~ "gm_player"

    view |> element("button[phx-click=create]") |> render_click()
    campaign = hd(Campaigns.list_campaigns())
    assert {:ok, projection} = Play.public_projection(campaign.id)

    gm_speakers =
      projection.characters
      |> Enum.filter(&(&1.role == :gm))
      |> MapSet.new(&{&1.name, &1.speaker_id})

    assert gm_speakers ==
             MapSet.new([
               {"Captain Ren", "captain_ren"},
               {"Captain Ren", "captain_ren_2"},
               {"Player", "gm_player"}
             ])
  end

  test "starting inventory is editable in setup, reviewed, and visible on the play board", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")
    view |> element("button[phx-click=add-starting-item]") |> render_click()
    assert has_element?(view, "input[name='campaign[inventory][0][name]']")

    attrs = %{
      title: "The Quiet Observatory",
      premise: "A sealed cabinet waits beneath the star charts.",
      setting: "Asterfall Island",
      tone: "Quiet wonder",
      narration_language: "English",
      player_character_name: "Mira Vale",
      player_character: "A careful apprentice astronomer.",
      inventory: %{
        "0" => %{
          name: "Healing potion",
          quantity: "2",
          unit: "vials",
          category: "Potion",
          description: "A restorative tonic in green glass."
        }
      }
    }

    review_html = view |> form("#campaign-form", campaign: attrs) |> render_submit()
    assert review_html =~ "Review your campaign"
    assert review_html =~ "Starting inventory"
    assert review_html =~ "Healing potion"
    assert review_html =~ "2 vials"
    assert Campaigns.list_campaigns() == []

    view |> element("button[phx-click=create]") |> render_click()
    campaign = hd(Campaigns.list_campaigns())
    session = hd(campaign.sessions)
    {:ok, play_view, play_html} = live(conn, ~p"/campaigns/#{campaign.id}/sessions/#{session.id}")

    assert has_element?(play_view, "#character-inventory")
    assert play_html =~ "Healing potion"
    assert play_html =~ "2 vials"
    assert play_html =~ "A restorative tonic in green glass."
  end

  test "optional player details can be reviewed and appear on the player board", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")
    view |> element("button[phx-click=add-player-detail]") |> render_click()
    view |> element("button[phx-click=add-player-detail]") |> render_click()

    assert has_element?(view, "input[name='campaign[player_character_details][0][label]']")
    assert has_element?(view, "input[name='campaign[player_character_details][0][value]']")
    assert has_element?(view, "input[name='campaign[player_character_details][1][label]']")
    assert has_element?(view, "input[name='campaign[player_character_details][1][value]']")

    attrs = %{
      title: "The Quiet Orchard",
      premise: "A final harvest is approaching.",
      setting: "A coastal orchard",
      tone: "Grounded and reflective",
      narration_language: "English",
      player_character_name: "Mira Vale",
      player_character: "An orchard keeper with a gentle patience.",
      player_character_details: %{
        "0" => %{label: "Health", value: "Recovering well"},
        "1" => %{label: "Responsibilities", value: "Cares for the northern rows"}
      }
    }

    review_html = view |> form("#campaign-form", campaign: attrs) |> render_submit()
    assert review_html =~ "Review your campaign"
    assert review_html =~ "Player character details"
    assert review_html =~ "Health"
    assert review_html =~ "Recovering well"
    assert review_html =~ "Responsibilities"
    assert review_html =~ "Cares for the northern rows"
    assert Campaigns.list_campaigns() == []

    view |> element("button[phx-click=create]") |> render_click()
    campaign = hd(Campaigns.list_campaigns())
    session = hd(campaign.sessions)

    {:ok, _play_view, play_html} =
      live(conn, ~p"/campaigns/#{campaign.id}/sessions/#{session.id}")

    assert play_html =~ "Known details"
    assert play_html =~ "Health"
    assert play_html =~ "Recovering well"
    assert play_html =~ "Responsibilities"
    assert play_html =~ "Cares for the northern rows"
  end

  test "campaign setup accepts nested character and panel rows and only displays public panel values",
       %{
         conn: conn
       } do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")
    view |> element("button[phx-click=add-character]") |> render_click()
    view |> element("button[phx-click=add-panel-field]") |> render_click()
    view |> element("button[phx-click=add-panel-field]") |> render_click()

    attrs = %{
      title: "The Quiet Relay",
      premise: "A remote signal starts again.",
      setting: "An invented mountain pass",
      tone: "Curious and restrained",
      narration_language: "English",
      player_character_name: "Ilya",
      player_character: "A patient courier",
      starting_location: "The east relay station",
      starting_date: "The last day of autumn",
      world_time: "Near midnight",
      weather: "Dry snow",
      gm_characters: %{
        "0" => %{
          name: "Warden Eli",
          visible_facts_text: "The station's night keeper.",
          private_notes: "Knows why the signal stopped."
        }
      },
      panel_fields: %{
        "0" => %{
          key: "lamp_oil",
          panel: "Supplies",
          label: "Lamp oil",
          value_type: "quantity",
          unit: "flasks",
          visibility: "public",
          initial_value: "2"
        },
        "1" => %{
          key: "relay_cause",
          panel: "GM notes",
          label: "Relay cause",
          value_type: "text",
          visibility: "gm_private",
          initial_value: "A damaged receiver."
        }
      }
    }

    review_html = view |> form("#campaign-form", campaign: attrs) |> render_submit()
    assert review_html =~ "Review your campaign"
    assert review_html =~ "Warden Eli"
    assert review_html =~ "Lamp oil"

    view |> element("button[phx-click=create]") |> render_click()
    campaign = hd(Campaigns.list_campaigns())
    assert {:ok, state} = Play.public_projection(campaign.id)
    assert state.world["date"] == "The last day of autumn"
    assert state.world["time"] == "Near midnight"
    assert [%{speaker_id: "warden_eli"}] = Enum.filter(state.characters, &(&1.role == :gm))

    assert {:ok, %{panels: panels}} = Panels.public_projection(campaign.id)
    assert [%{name: "Supplies", fields: [%{key: "lamp_oil", value: 2}]}] = panels

    {:ok, _detail, detail_html} = live(conn, ~p"/campaigns/#{campaign.id}")
    assert detail_html =~ "Lamp oil"
    refute detail_html =~ "relay_cause"
    refute detail_html =~ "A damaged receiver"
  end

  test "campaign detail resumes history and starts a later session", %{conn: conn} do
    campaign =
      campaign_fixture(%{
        player_character_name: "Rin Ashford",
        player_character: "A careful guide who carries a hand-drawn map."
      })

    [first_session] = campaign.sessions

    {:ok, view, html} = live(conn, ~p"/campaigns/#{campaign.id}")
    assert html =~ first_session.title
    assert html =~ "Character name"
    assert html =~ "Rin Ashford"
    assert html =~ "Character description"
    assert html =~ "A careful guide who carries a hand-drawn map."

    assert html =~
             "Starting another session completes the active session. Its full story stays saved."

    assert has_element?(
             view,
             "a[href='/campaigns/#{campaign.id}/sessions/#{first_session.id}']",
             "Resume current session"
           )

    assert has_element?(view, "button", "Start another session")

    assert has_element?(
             view,
             "a[href='/campaigns/#{campaign.id}/sessions/#{first_session.id}']",
             "Resume session"
           )

    view
    |> form("form[phx-submit=start-session]", session: %{title: "A Clear Night"})
    |> render_submit()

    refreshed = Campaigns.get_campaign!(campaign.id)
    assert Enum.find(refreshed.sessions, &(&1.id == first_session.id)).status == :completed
    assert Enum.count(refreshed.sessions, &(&1.status == :active)) == 1
    assert Enum.any?(refreshed.sessions, &(&1.title == "A Clear Night" and &1.status == :active))
    new_session = Enum.find(refreshed.sessions, &(&1.title == "A Clear Night"))
    assert_redirect(view, ~p"/campaigns/#{campaign.id}/sessions/#{new_session.id}")
  end

  test "archive and restore update the campaign list without deleting its history", %{conn: conn} do
    campaign = campaign_fixture(%{title: "The Paper Moon"})
    [session] = campaign.sessions

    {:ok, view, _html} = live(conn, ~p"/")

    archived_html =
      view |> element("#campaign-#{campaign.id} button[phx-click=archive]") |> render_click()

    assert archived_html =~ "Archived"
    archived = Campaigns.get_campaign!(campaign.id)
    assert archived.status == :archived
    assert Enum.any?(archived.sessions, &(&1.id == session.id))
    assert has_element?(view, "#campaign-#{campaign.id} button[phx-click=restore]")

    restored_html =
      view |> element("#campaign-#{campaign.id} button[phx-click=restore]") |> render_click()

    assert restored_html =~ "Active"
    assert Campaigns.get_campaign!(campaign.id).status == :active
  end

  test "a resumed session stays scoped to its campaign", %{conn: conn} do
    campaign = campaign_fixture(%{title: "The Glass Observatory"})
    [session] = campaign.sessions

    {:ok, _view, html} = live(conn, ~p"/campaigns/#{campaign.id}/sessions/#{session.id}")
    assert html =~ campaign.title
    assert html =~ session.title
    assert html =~ campaign.player_character_name
    assert html =~ "Campaign story"
    assert html =~ "What do you do or say?"
  end

  test "invalid campaign setup shows errors and saves nothing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    html = view |> form("#campaign-form", campaign: %{title: "x"}) |> render_submit()
    html_text = html |> Floki.parse_document!() |> Floki.text()
    assert html_text =~ "can't be blank"
    assert Campaigns.list_campaigns() == []
  end
end
