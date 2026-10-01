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

    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "Campaigns"
    assert html =~ "Lantern Coast"
    assert html =~ "Copper Archive"
    assert has_element?(view, "#campaign-persistence-import summary", "Campaign persistence")
    refute has_element?(view, "#campaign-persistence-import[open]")
    assert has_element?(view, "#campaign-backup-form")

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

  test "empty campaign library keeps backup restore available in its collapsed persistence section",
       %{
         conn: conn
       } do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Your next story starts here"
    assert has_element?(view, "#campaign-persistence-import summary", "Campaign persistence")
    refute has_element?(view, "#campaign-persistence-import[open]")
    assert has_element?(view, "#campaign-backup-form")
    refute html =~ "Download sensitive backup"
  end

  test "campaign setup is reviewed before creation and its first session is resumable", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    story = %{
      title: "The Blue Lantern",
      premise: "A signal appears on the cliffs after a century of silence.",
      setting: "A fictional coastal city",
      tone: "Patient and hopeful",
      narration_language: "French"
    }

    character = %{
      player_character_name: "Noa Marin",
      player_character: "A lighthouse keeper who listens for bells in fog."
    }

    submit_wizard_step(view, story, "continue")
    submit_wizard_step(view, Map.merge(story, character), "continue")
    submit_wizard_step(view, Map.merge(story, character), "continue")
    review_html = submit_wizard_step(view, Map.merge(story, character), "continue")

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

  test "campaign review shows every GM character field before persistence and keeps private guidance off the board",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    story = %{
      title: "The Saffron Kitchen",
      premise: "A sealed recipe arrives with a warning.",
      setting: "A riverside vineyard in southern France",
      tone: "Warm, intimate, and mysterious",
      narration_language: "English"
    }

    player_character = %{
      player_character_name: "Luc Moreau",
      player_character: "A patient cellar keeper."
    }

    opening = %{
      starting_location: "The west cellar",
      starting_date: "Second day of harvest",
      world_time: "Late evening",
      weather: "Cool mist from the river"
    }

    starting_inventory = %{
      inventory: %{
        "0" => %{
          name: "Reserve bottles",
          quantity: "3",
          unit: "bottles",
          category: "wine",
          description: "Kept for the autumn gathering."
        }
      }
    }

    gm_character = %{
      gm_characters: %{
        "0" => %{
          name: "Marcel",
          visible_facts_text: "A warm, observant beaver cook from Lyon.",
          private_notes: "Secret: he altered the cellar ledger.",
          voice_guidance: %{
            quirks: "Counts each ingredient twice.",
            accent_dialect: "A soft French accent from Lyon.",
            cadence: "Quick phrases that slow before a confession.",
            vocabulary: "Uses kitchen and river words.",
            mannerisms: "Taps the spoon when thinking."
          }
        }
      }
    }

    submit_wizard_step(view, story, "continue")
    submit_wizard_step(view, Map.merge(story, player_character), "continue")

    view |> element("button[phx-click=add-starting-item]") |> render_click()

    world_and_inventory =
      Map.merge(Map.merge(Map.merge(story, player_character), opening), starting_inventory)

    submit_wizard_step(view, world_and_inventory, "continue")

    view |> element("button[phx-click=add-character]") |> render_click()

    attrs = Map.merge(world_and_inventory, gm_character)
    submit_wizard_step(view, attrs, "continue")

    review_html = render(view)
    assert review_html =~ "Marcel"
    assert review_html =~ "The west cellar"
    assert review_html =~ "Second day of harvest"
    assert review_html =~ "Late evening"
    assert review_html =~ "Cool mist from the river"
    assert review_html =~ "Reserve bottles"
    assert review_html =~ "· 3 bottles"
    assert review_html =~ "· wine"
    assert review_html =~ "Kept for the autumn gathering."
    assert review_html =~ "Player-visible facts"
    assert review_html =~ "A warm, observant beaver cook from Lyon."
    assert review_html =~ "GM-only notes"
    assert review_html =~ "Secret: he altered the cellar ledger."
    assert review_html =~ "Character voice guidance"
    assert review_html =~ "Quirks"
    assert review_html =~ "Counts each ingredient twice."
    assert review_html =~ "Accent or dialect"
    assert review_html =~ "A soft French accent from Lyon."
    assert review_html =~ "Cadence"
    assert review_html =~ "Quick phrases that slow before a confession."
    assert review_html =~ "Vocabulary"
    assert review_html =~ "Uses kitchen and river words."
    assert review_html =~ "Mannerisms"
    assert review_html =~ "Taps the spoon when thinking."
    assert Campaigns.list_campaigns() == []

    view |> element("button[phx-click=create]") |> render_click()
    campaign = hd(Campaigns.list_campaigns())
    assert_redirect(view, ~p"/campaigns/#{campaign.id}")
    [session] = campaign.sessions

    {:ok, _campaign_view, campaign_html} = live(conn, ~p"/campaigns/#{campaign.id}")

    {:ok, _session_view, session_html} =
      live(conn, ~p"/campaigns/#{campaign.id}/sessions/#{session.id}")

    for private_text <- [
          "Secret: he altered the cellar ledger.",
          "Counts each ingredient twice.",
          "A soft French accent from Lyon.",
          "Quick phrases that slow before a confession.",
          "Uses kitchen and river words.",
          "Taps the spoon when thinking."
        ] do
      refute campaign_html =~ private_text
      refute session_html =~ private_text
    end
  end

  test "campaign setup moves through grouped steps and backtracking preserves entered values", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, ~p"/campaigns/new")
    assert html =~ "Step 1 of 4"
    refute has_element?(view, "#campaign-setup-step-1[hidden]")
    assert has_element?(view, "#campaign-setup-step-2[hidden]")

    story = %{
      title: "The Quiet Beacon",
      premise: "A lighthouse answers a signal no one sent.",
      setting: "The northern coast",
      tone: "Quiet and curious",
      narration_language: "English"
    }

    view |> submit_wizard_step(story, "continue")
    assert has_element?(view, "#campaign-setup-step-2:not([hidden])")

    character = %{
      player_character_name: "Iris",
      player_character: "A keeper who remembers every ship."
    }

    view |> submit_wizard_step(Map.merge(story, character), "continue")
    assert has_element?(view, "#campaign-setup-step-3:not([hidden])")

    submit_wizard_step(view, Map.merge(story, character), "previous")
    assert has_element?(view, "#campaign-setup-step-2:not([hidden])")
    assert render(view) =~ "value=\"Iris\""
    assert render(view) =~ "A keeper who remembers every ship."

    submit_wizard_step(view, Map.merge(story, character), "previous")
    assert has_element?(view, "#campaign-setup-step-1:not([hidden])")
    assert render(view) =~ "value=\"The Quiet Beacon\""
    assert render(view) =~ "The northern coast"
  end

  test "review validation returns the player to the step containing invalid fields", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    attrs = %{
      title: "x",
      premise: "A signal appears.",
      setting: "A coastal town",
      tone: "Thoughtful",
      narration_language: "English",
      player_character_name: "Mira",
      player_character: "A keeper who watches the sea."
    }

    submit_wizard_step(view, attrs, "continue")
    submit_wizard_step(view, attrs, "continue")
    submit_wizard_step(view, attrs, "continue")
    html = submit_wizard_step(view, attrs, "continue")

    assert has_element?(view, "#campaign-setup-step-1:not([hidden])")
    assert html =~ "should be at least 2 character(s)"
    assert Campaigns.list_campaigns() == []
  end

  test "review validation returns the player to the character step when required details are missing",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/campaigns/new")

    story = %{
      title: "The Quiet Beacon",
      premise: "A signal appears.",
      setting: "A coastal town",
      tone: "Thoughtful",
      narration_language: "English"
    }

    submit_wizard_step(view, story, "continue")
    submit_wizard_step(view, story, "continue")
    submit_wizard_step(view, story, "continue")
    html = submit_wizard_step(view, story, "continue")

    assert has_element?(view, "#campaign-setup-step-2:not([hidden])")
    html_text = html |> Floki.parse_document!() |> Floki.text()
    assert html_text =~ "can't be blank"
    assert Campaigns.list_campaigns() == []
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
    assert has_element?(view, "a", "Edit campaign")
    refute has_element?(view, "a", "Edit setup and character voices")
    assert has_element?(view, "#campaign-persistence summary", "Campaign persistence")
    refute has_element?(view, "#campaign-persistence[open]")
    refute has_element?(view, "#campaign-backup-form")

    assert has_element?(
             view,
             "#campaign-persistence a[href='/campaigns/#{campaign.id}/backup']"
           )

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

  defp submit_wizard_step(view, attrs, direction) do
    view
    |> form("#campaign-form", campaign: attrs)
    |> put_submitter("button[name=direction][value=#{direction}]")
    |> render_submit()
  end
end
