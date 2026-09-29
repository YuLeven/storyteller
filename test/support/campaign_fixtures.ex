defmodule Storyteller.CampaignFixtures do
  @moduledoc false

  alias Storyteller.Campaigns

  @valid_attrs %{
    title: "The Glass Observatory",
    premise: "A star map has appeared on the observatory's sealed dome.",
    setting: "The remote island of Asterfall",
    tone: "Quiet wonder and discovery",
    narration_language: "English",
    player_character: "Mira Vale, a patient apprentice astronomer"
  }

  def campaign_fixture(attrs \\ %{}) do
    {:ok, campaign} = Campaigns.create_campaign(Map.merge(@valid_attrs, attrs))
    campaign
  end

  def valid_campaign_attrs, do: @valid_attrs
end
