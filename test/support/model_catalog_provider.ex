defmodule Storyteller.TestGMModelCatalog do
  @moduledoc false

  def models do
    {:ok,
     [
       %{slug: "gpt-6-luna", display_name: "GPT-6 Luna"},
       %{slug: "fixture-model", display_name: "Fixture Model"},
       %{slug: "second-fixture-model", display_name: "Second Fixture Model"}
     ]}
  end
end
