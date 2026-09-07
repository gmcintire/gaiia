defmodule Gaiia.FilesTest do
  use ExUnit.Case, async: true

  alias Gaiia.Files
  alias Gaiia.ReqStub

  @signed_url "https://files.example.com/invoice.pdf?signature=abc"

  defp stub(fun) do
    [req_options: ReqStub.install(fun)]
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

  test "upload/4 maps a 403 to an :http error" do
    opts = stub(fn _req -> Req.Response.new(status: 403, body: "denied") end)

    assert {:error, %Gaiia.Error{kind: :http, status: 403, details: "denied"}} =
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
