defmodule Storyteller.PlayTest.LazyModuleProvider do
  def stream_response(_request) do
    :persistent_term.put({__MODULE__, :called}, true)

    proposal = %{
      "narration" => "The observatory settles into the quiet of the watch.",
      "dialogue" => [],
      "activities" => [],
      "public_changes" => %{},
      "private_changes" => %{},
      "panel_changes" => [],
      "memory_update" => %{"public_summary" => "", "gm_private_summary" => ""},
      "character_updates" => [],
      "location_changes" => [],
      "inventory_changes" => [],
      "objective_changes" => [],
      "roll_request" => nil
    }

    {:ok, %{text: Jason.encode!(proposal)}}
  end
end
