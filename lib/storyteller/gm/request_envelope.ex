defmodule Storyteller.GM.RequestEnvelope do
  @moduledoc false

  # The model catalog can be automatic. Keep the compiler's envelope estimate
  # conservative for any slug the adapter accepts from the account catalog.
  @max_model_slug_bytes 255
  @automatic_model_slug String.duplicate("m", @max_model_slug_bytes)

  def body(model, instructions, input)
      when is_binary(model) and is_binary(instructions) and is_list(input) do
    %{
      "model" => model,
      "instructions" => instructions,
      "input" => input,
      "store" => false,
      "stream" => true
    }
  end

  def encoded_size(model, instructions, input) do
    model = envelope_model(model)
    model |> body(instructions, input) |> Jason.encode!() |> byte_size()
  end

  def maximum_model_slug_bytes, do: @max_model_slug_bytes

  defp envelope_model(model) when is_binary(model) and model != "", do: model
  defp envelope_model(_model), do: @automatic_model_slug
end
