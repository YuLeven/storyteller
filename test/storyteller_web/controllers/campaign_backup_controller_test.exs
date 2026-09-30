defmodule StorytellerWeb.CampaignBackupControllerTest do
  use StorytellerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Storyteller.CampaignFixtures

  test "serves the campaign backup as a private, no-store attachment", %{conn: conn} do
    campaign = campaign_fixture()

    conn = get(conn, ~p"/campaigns/#{campaign.id}/backup")
    content_disposition = conn |> get_resp_header("content-disposition") |> hd()

    assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert content_disposition =~ "attachment"
    assert content_disposition =~ "sensitive-backup.json"
    assert Jason.decode!(conn.resp_body)["campaign"]["title"] == campaign.title

    {:ok, view, html} = live(build_conn(), ~p"/campaigns/#{campaign.id}")
    assert html =~ "full event history"

    assert has_element?(
             view,
             "a[href='/campaigns/#{campaign.id}/backup']",
             "Download sensitive backup"
           )
  end

  test "imports an uploaded backup as a separate campaign without replacing its source", %{
    conn: conn
  } do
    source = campaign_fixture(%{title: "The Backed-up Vineyard"})
    {:ok, backup} = Storyteller.CampaignBackup.export(source.id)

    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "Import creates a separate campaign"

    upload =
      file_input(view, "#campaign-backup-form", :campaign_backup, [
        %{name: "vineyard-backup.json", content: backup}
      ])

    render_upload(upload, "vineyard-backup.json")
    view |> form("#campaign-backup-form") |> render_submit()

    imported =
      Storyteller.Campaigns.list_campaigns()
      |> Enum.find(&(&1.id != source.id))

    assert imported
    refute imported.id == source.id
    assert imported.title == source.title
    assert Storyteller.Campaigns.get_campaign!(source.id).title == source.title
    assert_redirect(view, ~p"/campaigns/#{imported.id}")
  end
end
