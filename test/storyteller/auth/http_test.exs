defmodule Storyteller.Auth.HTTPTest do
  use ExUnit.Case, async: true

  alias Storyteller.Auth.HTTP

  test "a nil adapter uses Req and accepts its test plug option" do
    stub = make_ref()

    Req.Test.stub(stub, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/.well-known/openid-configuration"
      Req.Test.json(conn, %{"issuer" => "https://provider.example"})
    end)

    assert {:ok, %{status: 200, body: %{"issuer" => "https://provider.example"}}} =
             HTTP.request(
               :get,
               "https://provider.example/.well-known/openid-configuration",
               plug: {Req.Test, stub}
             )
  end
end
