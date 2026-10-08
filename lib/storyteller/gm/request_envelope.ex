defmodule Storyteller.GM.RequestEnvelope do
  @moduledoc false

  # The model catalog can be automatic. Keep the compiler's envelope estimate
  # conservative for any slug the adapter accepts from the account catalog.
  @max_model_slug_bytes 255
  @automatic_model_slug String.duplicate("m", @max_model_slug_bytes)

  def body(model, instructions, input)
      when is_binary(model) and is_binary(instructions) and is_list(input) do
    body = %{
      "model" => model,
      "instructions" => instructions,
      "input" => input,
      "text" => %{"format" => %{"type" => "json_object"}},
      "store" => false,
      "stream" => true
    }

    if reasoning_model?(model) or model == @automatic_model_slug,
      do: Map.put(body, "reasoning", %{"effort" => "low"}),
      else: body
  end

  def encoded_size(model, instructions, input) do
    model = envelope_model(model)
    model |> body(instructions, input) |> Jason.encode!() |> byte_size()
  end

  def maximum_model_slug_bytes, do: @max_model_slug_bytes

  defp reasoning_model?(model) do
    Regex.match?(~r/\A(?:gpt-[56](?:[.-]|$)|o[1-9](?:[.-]|$))/i, model)
  end

  defp envelope_model(model) when is_binary(model) and model != "", do: model
  defp envelope_model(_model), do: @automatic_model_slug
end
