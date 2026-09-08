defmodule Gaiia.FilesTest do
  use ExUnit.Case, async: true

  alias Gaiia.Files
  alias Gaiia.ReqStub

  @signed_url "http://127.0.0.1:1/invoice.pdf?signature=abc"

  # With `opts` omitted the module builds a bare `Req.new([])`, so the request
  # really is executed against a live transport. An unsupported scheme makes
  # that transport fail in milliseconds; a refused loopback port would work too
  # but Req retries transport errors on idempotent methods, costing ~7s each.
  @unsupported_scheme_url "gopher://127.0.0.1/invoice.pdf"

  defp stub(fun) do
    [req_options: ReqStub.install(fun)]
  end

  test "download/1 accepts omitted options and reports a transport failure as a network error" do
    assert {:error, %Gaiia.Error{kind: :network}} = Files.download(@unsupported_scheme_url)
  end

  test "download_to/2 accepts omitted options and writes no file when the transport fails" do
    path = Path.join(System.tmp_dir!(), "gaiia-files-unsupported-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm(path) end)

    assert {:error, %Gaiia.Error{kind: :network}} = Files.download_to(@unsupported_scheme_url, path)
    refute File.exists?(path)
  end

  test "upload/3 accepts omitted options and reports a transport failure as a network error" do
    assert {:error, %Gaiia.Error{kind: :network}} =
             Files.upload(@unsupported_scheme_url, "body", "text/plain")
  end

  test "download/2 rejects an unknown option" do
    assert {:error, %Gaiia.Error{kind: :network, details: %ArgumentError{} = details}} =
             Files.download(@signed_url, bogus: 1)

    assert Exception.message(details) =~ "bogus"
  end

  test "download_to/3 rejects an unknown option" do
    path = Path.join(System.tmp_dir!(), "gaiia-files-invalid-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm(path) end)

    assert {:error, %Gaiia.Error{kind: :network, details: %ArgumentError{} = details}} =
             Files.download_to(@signed_url, path, bogus: 1)

    assert Exception.message(details) =~ "bogus"
  end

  test "upload/4 rejects an unknown option" do
    assert {:error, %Gaiia.Error{kind: :network, details: %ArgumentError{} = details}} =
             Files.upload(@signed_url, "body", "text/plain", bogus: 1)

    assert Exception.message(details) =~ "bogus"
  end

  test "download/2 returns the bytes of a 200 response" do
    opts = stub(fn _req -> ReqStub.ok_response("PDFBYTES") end)

    assert {:ok, "PDFBYTES"} = Files.download(@signed_url, opts)

    request = ReqStub.captured()
    assert request.method == :get
    assert URI.to_string(request.url) == @signed_url
  end

  test "download/2 never sends the Gaiia API key" do
    opts = stub(fn _req -> ReqStub.ok_response("x") end)

    {:ok, _} = Files.download(@signed_url, opts)

    refute header(ReqStub.captured_headers(), "x-gaiia-api-key")
  end

  test "download/2 maps a 404 to an :http error" do
    opts = stub(fn _req -> Req.Response.new(status: 404, body: "gone") end)

    assert {:error, %Gaiia.Error{kind: :http, status: 404, details: "gone"}} =
             Files.download(@signed_url, opts)
  end

  test "download/2 maps a transport exception to a :network error" do
    opts = stub(fn _req -> %Req.TransportError{reason: :nxdomain} end)

    assert {:error, %Gaiia.Error{kind: :network}} = Files.download(@signed_url, opts)
  end

  test "download_to/3 writes the bytes to disk" do
    opts = stub(fn _req -> ReqStub.ok_response("STREAMED PDF") end)
    path = Path.join(System.tmp_dir!(), "gaiia-files-test-#{System.unique_integer()}.pdf")

    on_exit(fn -> File.rm(path) end)

    assert {:ok, ^path} = Files.download_to(@signed_url, path, opts)
    assert File.read!(path) == "STREAMED PDF"
  end

  test "download_to/3 preserves bytes already streamed by the adapter" do
    opts = stub(fn _req -> ReqStub.ok_response("") end)
    path = Path.join(System.tmp_dir!(), "gaiia-files-streamed-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm(path) end)
    File.write!(path, "ALREADY STREAMED")

    assert {:ok, ^path} = Files.download_to(@signed_url, path, opts)
    assert File.read!(path) == "ALREADY STREAMED"
  end

  test "download_to/3 maps a non-success response to an HTTP error without writing a file" do
    opts = stub(fn _req -> Req.Response.new(status: 503, body: "unavailable") end)
    path = Path.join(System.tmp_dir!(), "gaiia-files-http-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm(path) end)

    assert {:error, %Gaiia.Error{kind: :http, status: 503, details: "unavailable"}} =
             Files.download_to(@signed_url, path, opts)

    refute File.exists?(path)
  end

  test "download_to/3 maps a transport exception to a network error" do
    opts = stub(fn _req -> %Req.TransportError{reason: :closed} end)
    path = Path.join(System.tmp_dir!(), "gaiia-files-closed-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm(path) end)

    assert {:error, %Gaiia.Error{kind: :network}} =
             Files.download_to(@signed_url, path, opts)
  end

  test "upload/4 PUTs the raw body with the given content type and no API key" do
    opts = stub(fn _req -> Req.Response.new(status: 200) end)

    assert :ok = Files.upload(@signed_url, "RAWPDF", "application/pdf", opts)

    request = ReqStub.captured()
    assert request.method == :put
    assert URI.to_string(request.url) == @signed_url
    assert request.body == "RAWPDF"

    headers = ReqStub.captured_headers()
    assert header(headers, "content-type") == "application/pdf"
    refute header(headers, "x-gaiia-api-key")
  end

  test "upload/4 streams a file body without reading it into memory" do
    opts = stub(fn _req -> Req.Response.new(status: 200) end)
    path = Path.join(System.tmp_dir!(), "gaiia-files-upload-#{System.unique_integer()}.pdf")

    on_exit(fn -> File.rm(path) end)

    File.write!(path, "FILEPDF")

    assert :ok = Files.upload(@signed_url, {:file, path}, "application/pdf", opts)

    request = ReqStub.captured()
    assert %File.Stream{} = request.body
    assert header(ReqStub.captured_headers(), "content-length") == "7"
  end

  test "upload/4 rejects a directory file body with a path-specific network error" do
    path = System.tmp_dir!()

    assert {:error,
            %Gaiia.Error{
              kind: :network,
              message: message,
              details: %File.Error{reason: :eisdir}
            }} = Files.upload(@signed_url, {:file, path}, "application/pdf")

    assert message =~ path
  end

  test "upload/4 maps a missing file body to a path-specific network error" do
    path = Path.join(System.tmp_dir!(), "gaiia-files-missing-#{System.unique_integer([:positive])}")

    assert {:error,
            %Gaiia.Error{
              kind: :network,
              message: message,
              details: %File.Error{reason: :enoent}
            }} = Files.upload(@signed_url, {:file, path}, "application/pdf")

    assert message =~ path
  end

  test "upload/4 maps a 403 to an :http error" do
    opts = stub(fn _req -> Req.Response.new(status: 403, body: "denied") end)

    assert {:error, %Gaiia.Error{kind: :http, status: 403, details: "denied"}} =
             Files.upload(@signed_url, "RAWPDF", "application/pdf", opts)
  end

  test "upload/4 maps a transport exception to a network error" do
    opts = stub(fn _req -> %Req.TransportError{reason: :closed} end)

    assert {:error, %Gaiia.Error{kind: :network}} =
             Files.upload(@signed_url, "RAWPDF", "application/pdf", opts)
  end

  defp header(headers, name) do
    headers
    |> Enum.find(fn {key, _} -> String.downcase(key) == name end)
    |> case do
      {_, [value | _]} -> value
      nil -> nil
    end
  end
end
