defmodule StorytellerWeb.SessionLiveTest.FakeProvider do
  @behaviour Storyteller.Play.Provider

  @impl true
  def stream_response(request) do
    Application.fetch_env!(:storyteller, :session_live_test_handler).(request)
  end
end

defmodule StorytellerWeb.SessionLiveTest do
  use StorytellerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query
  import Storyteller.CampaignFixtures

  alias Storyteller.Play
  alias Storyteller.Play.{Event, Turn}
  alias Storyteller.Repo
  alias StorytellerWeb.SessionLiveTest.FakeProvider

  setup do
    previous_provider = Application.get_env(:storyteller, :gm_provider, :not_configured)

    previous_handler =
      Application.get_env(:storyteller, :session_live_test_handler, :not_configured)

    previous_roll_source = Application.get_env(:storyteller, :d20_roll_source, :not_configured)

    Application.put_env(:storyteller, :gm_provider, FakeProvider)

    on_exit(fn ->
      restore_env(:gm_provider, previous_provider)
      restore_env(:session_live_test_handler, previous_handler)
      restore_env(:d20_roll_source, previous_roll_source)
    end)

    :ok
  end

  test "submitting an action updates the public world, NPC activity, and attributed timeline", %{
    conn: conn
  } do
    campaign = campaign_fixture(%{title: "The Amber Road"})
    [session] = campaign.sessions

    {:ok, _state} =
      Play.initialize_campaign(campaign, %{
        public_state: %{"date" => "Day 3, June 10", "time" => "09:15", "weather" => "Cloudy"},
        characters: [%{speaker_id: "rhea", name: "Rhea Vale"}]
      })

    test_pid = self()

    set_handler(fn request ->
      context = provider_context(request)
      send(test_pid, {:fake_gm_call, context})

      {:ok,
       %{
         narration: "The stone archway opens onto a quiet road.",
         dialogue: [%{speaker_id: "rhea", text: "The western path is clear."}],
         activities: [%{speaker_id: "rhea", text: "Rhea checks the gate latch."}],
         public_changes: %{
           "date" => "Day 3, June 10",
           "time" => "09:20",
           "weather" => "A light rain begins",
           "location" => "The western road"
         },
         private_changes: %{"unseen_clue" => "This stays private"},
         character_updates: [
           %{speaker_id: "rhea", visible_facts: %{"trust" => "She trusts your judgment."}}
         ],
         memory_update: %{public_summary: "", gm_private_summary: ""},
         roll_request: nil
       }}
    end)

    {:ok, view, _html} = live(conn, session_path(campaign, session))
    refute has_element?(view, "#roll-panel")

    view
    |> form("#turn-composer",
      turn: %{
        input: "I test the latch and ask Rhea about the road."
      }
    )
    |> render_submit()

    assert_receive {:fake_gm_call, %{"phase" => "initial"}}, 1_000
    assert wait_until(fn -> render(view) =~ "The western path is clear." end)
    html = render(view)

    assert html =~ "The stone archway opens onto a quiet road."
    assert html =~ "Rhea Vale"
    assert html =~ "Rhea checks the gate latch."
    assert html =~ "The western road"
    assert html =~ "09:20"
    assert html =~ "A light rain begins"
    assert html =~ "Day 3, June 10"
    refute html =~ "This stays private"

    {:ok, projection} = Play.public_projection(campaign.id)
    rhea = Enum.find(projection.characters, &(&1.speaker_id == "rhea"))
    assert rhea.visible_activity == "Rhea checks the gate latch."
    assert rhea.visible_facts["trust"] == "She trusts your judgment."
    assert projection.world["location"] == "The western road"
  end

  test "D20 is only generated after the validated roll request is clicked", %{conn: conn} do
    campaign = campaign_fixture()
    [session] = campaign.sessions
    test_pid = self()

    set_handler(fn request ->
      context = provider_context(request)
      send(test_pid, {:fake_gm_call, context})

      if context["phase"] == "initial" do
        {:ok,
         %{
           narration: "The narrow bridge sways over the ravine.",
           dialogue: [],
           activities: [],
           public_changes: %{},
           private_changes: %{},
           character_updates: [],
           memory_update: %{public_summary: "", gm_private_summary: ""},
           roll_request: %{test: "Agility", difficulty: "Hard"}
         }}
      else
        {:ok,
         %{
           narration: "You steady your footing and reach the far side.",
           dialogue: [],
           activities: [],
           public_changes: %{"weather" => "Clear"},
           private_changes: %{},
           character_updates: [],
           memory_update: %{public_summary: "", gm_private_summary: ""},
           roll_request: nil
         }}
      end
    end)

    Application.put_env(:storyteller, :d20_roll_source, fn ->
      send(test_pid, :d20_source_used)
      17
    end)

    {:ok, view, _html} = live(conn, session_path(campaign, session))
    refute has_element?(view, "button[phx-click='roll-d20']")

    view
    |> form("#turn-composer",
      turn: %{input: "I cross the bridge carefully."}
    )
    |> render_submit()

    assert_receive {:fake_gm_call, %{"phase" => "initial"}}, 1_000
    assert wait_until(fn -> has_element?(view, "#roll-panel", "Agility") end)
    refute_receive :d20_source_used, 100

    view |> element("#roll-panel button[phx-click='roll-d20']") |> render_click()
    assert_receive :d20_source_used, 1_000
    assert_receive {:fake_gm_call, %{"phase" => "after_roll"}}, 1_000
    assert wait_until(fn -> render(view) =~ "You steady your footing and reach the far side." end)

    html = render(view)
    assert html =~ "D20 result: 17"
    assert html =~ "You steady your footing and reach the far side."
  end

  test "failed turn and reconnect guidance survive a new LiveView connection", %{conn: conn} do
    campaign = campaign_fixture()
    [session] = campaign.sessions
    {:ok, agent} = Agent.start_link(fn -> 0 end)
    test_pid = self()

    set_handler(fn request ->
      context = provider_context(request)
      attempt = Agent.get_and_update(agent, fn attempt -> {attempt, attempt + 1} end)
      send(test_pid, {:fake_gm_attempt, attempt, context["phase"]})

      if attempt == 0 do
        {:error, :reauth_required}
      else
        {:ok,
         %{
           narration: "The saved action now moves the story forward.",
           dialogue: [],
           activities: [],
           public_changes: %{},
           private_changes: %{},
           character_updates: [],
           memory_update: %{public_summary: "", gm_private_summary: ""},
           roll_request: nil
         }}
      end
    end)

    {:ok, view, _html} = live(conn, session_path(campaign, session))

    view
    |> form("#turn-composer",
      turn: %{input: "I light the old signal beacon."}
    )
    |> render_submit()

    assert_receive {:fake_gm_attempt, 0, "initial"}, 1_000
    assert wait_until(fn -> has_element?(view, "#turn-error", "needs attention") end)
    assert has_element?(view, "#turn-error a[href='/auth/connect']", "Reconnect account")
    assert render(view) =~ "I light the old signal beacon."

    {:ok, resumed, resumed_html} = live(conn, session_path(campaign, session))
    assert resumed_html =~ "needs you to reconnect"
    assert resumed_html =~ "I light the old signal beacon."
    assert has_element?(resumed, "#turn-error a[href='/auth/connect']", "Reconnect account")

    resumed |> element("#turn-error button[phx-click='retry-turn']") |> render_click()
    assert_receive {:fake_gm_attempt, 1, "initial"}, 1_000

    assert wait_until(fn ->
             render(resumed) =~ "The saved action now moves the story forward."
           end)

    assert render(resumed) =~ "The saved action now moves the story forward."
  end

  test "the timeline window keeps recent campaign events in chronological order", %{conn: conn} do
    campaign = campaign_fixture()
    [session] = campaign.sessions
    {:ok, _state} = Play.initialize_campaign(campaign)

    {:ok, turn} =
      Play.submit_turn(campaign.id, session.id, "history-window-turn", "Seed long history")

    Repo.update_all(from(turn in Turn, where: turn.id == ^turn.id), set: [status: :completed])

    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    events =
      Enum.map(1..501, fn sequence ->
        %{
          campaign_id: campaign.id,
          session_id: session.id,
          turn_id: turn.id,
          sequence: sequence,
          event_type: :gm_narration,
          visibility: :public,
          payload: %{"text" => "History marker #{sequence}"},
          inserted_at: now
        }
      end)

    assert {501, nil} = Repo.insert_all(Event, events)

    {:ok, timeline} = Play.public_timeline(campaign.id)
    assert length(timeline) == 500
    assert hd(timeline).payload["text"] == "History marker 2"
    assert List.last(timeline).payload["text"] == "History marker 501"

    {:ok, _view, html} = live(conn, session_path(campaign, session))
    document = Floki.parse_document!(html)
    first_event = document |> Floki.find("#event-1") |> Floki.text()
    last_event = document |> Floki.find("#event-500") |> Floki.text()

    event_texts =
      document
      |> Floki.find("#story-timeline .story-entry > p")
      |> Enum.map(&Floki.text/1)

    assert first_event =~ "History marker 2"
    assert last_event =~ "History marker 501"
    refute "History marker 1" in event_texts
  end

  defp session_path(campaign, session),
    do: ~p"/campaigns/#{campaign.id}/sessions/#{session.id}"

  defp set_handler(handler) do
    Application.put_env(:storyteller, :session_live_test_handler, handler)
  end

  defp provider_context(request) do
    request.input
    |> hd()
    |> Map.fetch!(:content)
    |> hd()
    |> Map.fetch!(:text)
    |> Jason.decode!()
  end

  defp wait_until(fun, attempts \\ 60)
  defp wait_until(fun, 0), do: fun.()

  defp wait_until(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(25)
      wait_until(fun, attempts - 1)
    end
  end

  defp restore_env(key, :not_configured), do: Application.delete_env(:storyteller, key)
  defp restore_env(key, value), do: Application.put_env(:storyteller, key, value)
end
