defmodule StorytellerWeb.AuthHTML do
  @moduledoc "Connection settings pages rendered by `AuthController`."

  use StorytellerWeb, :html

  embed_templates "auth_html/*"
end
