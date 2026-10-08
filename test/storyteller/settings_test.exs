defmodule Storyteller.SettingsTest do
  use Storyteller.DataCase

  alias Storyteller.Settings

  test "GM model defaults to Luna and Automatic remains an explicit local choice" do
    assert Settings.preferred_gm_model() == "gpt-6-luna"

    assert {:ok, _preference} = Settings.set_preferred_gm_model("fixture-model")
    assert Settings.preferred_gm_model() == "fixture-model"

    assert {:ok, _preference} = Settings.set_preferred_gm_model(nil)
    assert is_nil(Settings.preferred_gm_model())
  end
end
