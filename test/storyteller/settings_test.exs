defmodule Storyteller.SettingsTest do
  use Storyteller.DataCase

  alias Storyteller.Settings

  test "GM model preference stays automatic until a local choice is saved" do
    assert is_nil(Settings.preferred_gm_model())

    assert {:ok, _preference} = Settings.set_preferred_gm_model("fixture-model")
    assert Settings.preferred_gm_model() == "fixture-model"

    assert {:ok, _preference} = Settings.set_preferred_gm_model(nil)
    assert is_nil(Settings.preferred_gm_model())
  end
end
