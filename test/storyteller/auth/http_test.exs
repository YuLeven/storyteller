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

  test "distinguishes fast stream connection timeouts from elapsed receive timeouts" do
    for reason <- [:econnrefused, :closed] do
      stub = make_ref()

      Req.Test.stub(stub, fn conn ->
        Req.Test.transport_error(conn, reason)
      end)

      assert {:error, :network_error} =
               HTTP.request(:post, "https://provider.example/responses", plug: {Req.Test, stub})
    end

    fast_timeout_stub = make_ref()

    Req.Test.stub(fast_timeout_stub, fn conn ->
      Req.Test.transport_error(conn, :timeout)
    end)

    assert {:error, :network_error} =
             HTTP.request(:post, "https://provider.example/responses",
               receive_timeout: 90_000,
               timeout_classification: :stream_receive_timeout,
               plug: {Req.Test, fast_timeout_stub}
             )

    slow_timeout_stub = make_ref()

    Req.Test.stub(slow_timeout_stub, fn conn ->
      Process.sleep(150)
      Req.Test.transport_error(conn, :timeout)
    end)

    assert {:error, :timeout} =
             HTTP.request(:post, "https://provider.example/responses",
               receive_timeout: 150,
               timeout_classification: :stream_receive_timeout,
               plug: {Req.Test, slow_timeout_stub}
             )

    generic_timeout_stub = make_ref()

    Req.Test.stub(generic_timeout_stub, fn conn ->
      Req.Test.transport_error(conn, :timeout)
    end)

    assert {:error, :timeout} =
             HTTP.request(:post, "https://provider.example/responses",
               plug: {Req.Test, generic_timeout_stub}
             )
  end
end
