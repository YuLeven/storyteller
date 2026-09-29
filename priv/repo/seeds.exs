# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Storyteller.Repo.insert!(%Storyteller.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.
alias Storyteller.Campaigns
alias Storyteller.Campaigns.Campaign
alias Storyteller.Repo

qa_title = "QA Campaign: The Quiet Observatory"

unless Repo.get_by(Campaign, title: qa_title) do
  {:ok, _campaign} =
    Campaigns.create_campaign(%{
      title: qa_title,
      premise:
        "A brass star lens has gone dark on the night a new constellation appears over the island. Apprentice astronomer Mira Vale asks the player to help compare the sky charts before the observatory closes for winter.",
      setting: "A wind-swept island observatory in a fictional northern sea",
      tone: "Curious, grounded, and quietly adventurous",
      narration_language: "English",
      player_character: "Rowan Thorne, a traveling mapmaker with a good eye for detail"
    })
end
