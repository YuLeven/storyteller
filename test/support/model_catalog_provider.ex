defmodule Storyteller.TestGMModelCatalog do
  @moduledoc false

  def models do
    {:ok,
     [
       %{slug: "fixture-model", display_name: "Fixture Model"},
       %{slug: "second-fixture-model", display_name: "Second Fixture Model"}
     ]}
  end
end
