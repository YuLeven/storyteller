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

location_qa_title = "QA Playtest: The Amber Orchard"

unless Repo.get_by(Campaign, title: location_qa_title) do
  {:ok, _campaign} =
    Campaigns.create_campaign(%{
      title: location_qa_title,
      premise:
        "A late frost threatens the hillside orchard and its small press house. Caretaker Mara Vale must find out whether a missing copper weather vane can be repaired before the next cold night.",
      setting: "A fictional orchard valley above a foggy river",
      tone: "Warm, grounded, and quietly adventurous",
      narration_language: "English",
      player_character: "Mara Vale, an observant orchard caretaker",
      starting_location: "North orchard gate",
      starting_date: "Harvest Day 1",
      world_time: "Early morning",
      weather: "Cool mist over the river",
      gm_characters: [
        %{
          speaker_id: "npc:ines",
          name: "Inés Mar",
          visible_facts: %{
            "role" => "Press keeper",
            "location" => "Old press house",
            "manner" => "Careful and wry"
          },
          gm_private_facts: %{"concern" => "The missing vane was deliberately removed."}
        }
      ],
      inventory: [
        %{
          id: "harvest-basket",
          name: "Woven harvest basket",
          quantity: 1,
          unit: "basket",
          category: "Tools",
          description: "A deep willow basket with a leather shoulder strap.",
          owner_id: "player",
          visibility: "public"
        }
      ],
      panel_fields: [
        %{
          key: "orchard_crates",
          panel: "Orchard stores",
          label: "Empty crates",
          value_type: "quantity",
          unit: "crates",
          visibility: "public",
          initial_value: "18"
        },
        %{
          key: "cider_casks",
          panel: "Orchard stores",
          label: "Cider",
          value_type: "quantity",
          unit: "casks",
          visibility: "public",
          initial_value: "4"
        },
        %{
          key: "keeper_concern",
          panel: "GM notes",
          label: "Keeper's concern",
          value_type: "text",
          visibility: "gm_private",
          initial_value: "The missing weather vane was taken on purpose."
        }
      ]
    })
end
