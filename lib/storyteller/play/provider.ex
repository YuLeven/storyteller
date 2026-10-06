defmodule Storyteller.Play.Provider do
  @moduledoc """
  Callback contract for an injectable GM provider.

  The request follows the Responses API shape and may include provider-specific
  options. Implementations may return a decoded proposal map, JSON text, or a
  response map containing that text. `Storyteller.Play` validates every
  proposal before it can become canonical campaign state.
  """

  @callback stream_response(map()) ::
              {:ok, map() | binary()}
              | {:ok, %{required(:text) => binary(), optional(:response_id) => binary() | nil}}
              | {:error, atom()}
end
