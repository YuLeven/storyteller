defmodule Storyteller.PanelsTest do
  use Storyteller.DataCase, async: true

  import Storyteller.CampaignFixtures

  alias Storyteller.Campaigns
  alias Storyteller.Panels
  alias Storyteller.Panels.Field

  test "typed panel values normalize valid input and reject invalid or formula-like input" do
    assert {:ok, 12} = Panels.validate_value(:quantity, "12")
    assert {:error, _} = Panels.validate_value(:quantity, "1.5")
    assert {:error, _} = Panels.validate_value(:quantity, "-1")
    assert {:ok, "12.5"} = Panels.validate_value(:money, "12.50")
    assert {:error, _} = Panels.validate_value(:money, "-0.01")
    assert {:ok, "A sealed gate"} = Panels.validate_value(:text, "A sealed gate")
    assert {:error, _} = Panels.validate_value(:text, "=1+1")
    assert {:ok, "2026-09-29"} = Panels.validate_value(:date, "2026-09-29")
    assert {:error, _} = Panels.validate_value(:date, "not a date")
  end

  test "numeric resource deltas use exact typed arithmetic and reject zero or negative balances" do
    quantity = %Field{value_type: :quantity}
    money = %Field{value_type: :money}

    assert {:ok, 8, -3, 5} = Panels.apply_delta(quantity, "8", -3)
    assert {:error, :invalid_result} = Panels.apply_delta(quantity, 2, -3)
    assert {:error, :zero_delta} = Panels.apply_delta(quantity, 2, 0)

    assert {:ok, "18.5", "6.25", "24.75"} = Panels.apply_delta(money, "18.50", "6.25")
    assert {:error, :invalid_result} = Panels.apply_delta(money, "1.25", "-1.26")
    assert {:error, :zero_delta} = Panels.apply_delta(money, "1.25", "0.00")
    assert {:error, :invalid_result} = Panels.apply_delta(money, "1.25", "NaN")
    assert {:error, :invalid_result} = Panels.apply_delta(money, "1.25", "1e999999999")
    assert {:error, :invalid_result} = Panels.apply_delta(money, "1.25", "1e-999999999")

    assert {:error, :invalid_result} =
             Panels.apply_delta(money, "1.25", "0.00000000000000000000000000000000000000001")
  end

  test "public panel projection omits private fields and their values" do
    attrs =
      valid_campaign_attrs()
      |> Map.put(:panel_fields, [
        %{
          key: "rations",
          panel: "Supplies",
          label: "Rations",
          value_type: "quantity",
          unit: "days",
          visibility: "public",
          initial_value: "4"
        },
        %{
          key: "secret_contact",
          panel: "GM notes",
          label: "Secret contact",
          value_type: "text",
          visibility: "gm_private",
          initial_value: "The lighthouse keeper"
        }
      ])

    assert {:ok, campaign} = Campaigns.create_campaign(attrs)
    assert {:ok, %{panels: [panel]}} = Panels.public_projection(campaign.id)

    assert panel.name == "Supplies"
    assert [%{key: "rations", value: 4, unit: "days"}] = panel.fields
    refute inspect(panel) =~ "secret_contact"
    refute inspect(panel) =~ "The lighthouse keeper"

    assert [%Field{visibility: :public}, %Field{visibility: :gm_private}] =
             Panels.list_fields(campaign.id)
  end

  test "value updates are typed and scoped to the owning campaign and field key" do
    attrs =
      valid_campaign_attrs()
      |> Map.put(:panel_fields, [
        %{
          key: "rations",
          panel: "Supplies",
          label: "Rations",
          value_type: "quantity",
          visibility: "public",
          initial_value: "4"
        }
      ])

    assert {:ok, first} = Campaigns.create_campaign(attrs)
    second = campaign_fixture()

    assert {:error, :not_found} = Panels.update_value(second.id, "rations", 9)
    assert {:error, changeset} = Panels.update_value(first.id, "rations", "-3")
    assert errors_on(changeset).initial_value == ["must be a whole number of zero or greater"]

    assert {:ok, %Field{value: %{"value" => 9}}} =
             Panels.update_value(first.id, "rations", "9")

    assert {:ok, %{panels: [panel]}} = Panels.public_projection(first.id)
    assert hd(panel.fields).value == 9
    assert {:ok, %{panels: []}} = Panels.public_projection(second.id)
  end
end
