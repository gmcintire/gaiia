defmodule Gaiia.ReqStub do
  @moduledoc """
  Test transport for `Gaiia.Client`.

  Req v0.7 deprecated function adapters (`adapter: fun`) in favour of adapter
  modules, so a stub is this module plus a per-process response function. The
  function and the last request it saw live in the process dictionary, which
  keeps `async: true` tests isolated and needs no cleanup.

  Requests that arrive with no stub installed raise, so a test that forgets to
  stub the transport fails immediately instead of hitting the network.
  """

  @doc """
  Installs `fun` as the response function for the calling process and returns
  the `req_options` that route requests to it.

  `fun` receives the `%Req.Request{}` and returns a `%Req.Response{}`, an
  exception, or a `{request, response_or_exception}` tuple.
  """
  @spec install((Req.Request.t() -> term())) :: keyword()
  def install(fun) when is_function(fun, 1) do
    _ = Process.put(__MODULE__, {fun, nil})
    options()
  end

  @doc """
  Installs a stub that captures requests and replies with `body` under a 200.
  """
  @spec install_ok(term()) :: keyword()
  def install_ok(body \\ %{"data" => %{}}) do
    install(fn _req -> ok_response(body) end)
  end

  @doc "A 200 response carrying an already-decoded JSON `body`."
  @spec ok_response(term()) :: Req.Response.t()
  def ok_response(body) do
    %Req.Response{status: 200, body: body, headers: %{"content-type" => ["application/json"]}}
  end

  @doc "Req options routing requests to this adapter."
  @spec options() :: keyword()
  def options, do: [adapter: __MODULE__, retry: false]

  @doc "The most recent `%Req.Request{}` seen by the stub, or `nil`."
  @spec captured() :: Req.Request.t() | nil
  def captured do
    case Process.get(__MODULE__) do
      {_fun, request} -> request
      nil -> nil
    end
  end

  @doc "The JSON-decoded body of the most recent request."
  @spec captured_body() :: map()
  def captured_body do
    %Req.Request{body: body} = captured()
    Jason.decode!(body)
  end

  @doc "The GraphQL document of the most recent request."
  @spec captured_query() :: String.t()
  def captured_query do
    %{"query" => query} = captured_body()
    query
  end

  @doc "The headers of the most recent request."
  @spec captured_headers() :: map()
  def captured_headers do
    %Req.Request{headers: headers} = captured()
    headers
  end

  @doc """
  Req adapter callback. Records the request, then delegates to the installed
  response function.
  """
  @spec run(Req.Request.t()) :: {Req.Request.t(), Req.Response.t() | Exception.t()}
  def run(%Req.Request{} = request) do
    case Process.get(__MODULE__) do
      {fun, _previous} ->
        _ = Process.put(__MODULE__, {fun, request})
        normalize(request, fun.(request))

      nil ->
        raise "Gaiia test attempted to hit the real network. Install a stub with Gaiia.ReqStub.install/1."
    end
  end

  defp normalize(_request, {%Req.Request{} = request, result}), do: {request, result}
  defp normalize(request, result), do: {request, result}
end
