defmodule Gaiia.ReqStubTest do
  use ExUnit.Case, async: true

  alias Gaiia.ReqStub

  test "captured/0 returns nil before a stub is installed" do
    assert ReqStub.captured() == nil
  end

  test "run/1 refuses an unstubbed request rather than using the network" do
    assert_raise RuntimeError, ~r/attempted to hit the real network/, fn ->
      ReqStub.run(%Req.Request{})
    end
  end

  test "run/1 records the request before normalizing a tuple result" do
    request = %Req.Request{method: :get}
    returned_request = %{request | method: :head}
    response = %Req.Response{status: 204, body: ""}

    ReqStub.install(fn _request -> {returned_request, response} end)

    _ = ReqStub.run(request)

    assert ReqStub.captured().method == :get
  end
end
