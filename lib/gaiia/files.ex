defmodule Gaiia.Files do
  @moduledoc """
  Transfers files through the signed URLs returned by the Gaiia API.

  File metadata and signed URLs still come from normal GraphQL operations.
  Downloads first select a file's URL, then fetch it directly:

      {:ok, %{"pdf" => %{"url" => url}}} =
        Gaiia.Queries.invoice(client, %{"id" => invoice_id}, "pdf { url }")

      {:ok, contents} = Gaiia.Files.download(url)
      # Or, without holding the file in memory:
      {:ok, path} = Gaiia.Files.download_to(url, "invoice.pdf")

  Signed URLs expire. Re-run the GraphQL query to obtain a fresh URL rather
  than retrying an expired URL.

  Uploads use two GraphQL mutations around one raw file transfer:

      upload_input = %{"name" => "invoice.pdf", "contentType" => "application/pdf"}

      {:ok, %{"uploadUrl" => %{"url" => url, "fileKey" => file_key}}} =
        Gaiia.Mutations.create_document_upload_url(
          client,
          %{"input" => upload_input},
          "uploadUrl { url fileKey }"
        )

      :ok = Gaiia.Files.upload(url, {:file, "invoice.pdf"}, "application/pdf")

      document_input = %{
        "fileKey" => file_key,
        "name" => "Invoice",
        "accountId" => account_id
      }

      {:ok, document} =
        Gaiia.Mutations.create_document(
          client,
          %{"input" => document_input},
          "document { id name }"
        )

  The signed file host receives neither the Gaiia API key nor a GraphQL
  request. Contract and ticket-comment attachment uploads follow the same
  three stages with their corresponding generated mutations.
  """

  alias Gaiia.Error

  @api_key_header "x-gaiia-api-key"
  @file_chunk_size 64 * 1024

  @type opts :: [req_options: keyword()]
  @type upload_body :: binary() | {:file, Path.t()}

  @doc "Download all bytes from a signed URL, following redirects."
  @spec download(String.t(), opts()) :: {:ok, binary()} | {:error, Error.t()}
  def download(url, opts \\ []) do
    opts
    |> request(method: :get, url: url, redirect: true, decode_body: false)
    |> handle_download()
  end

  @doc "Stream a signed URL to `path`, following redirects."
  @spec download_to(String.t(), Path.t(), opts()) :: {:ok, Path.t()} | {:error, Error.t()}
  def download_to(url, path, opts \\ []) do
    opts
    |> request(method: :get, url: url, redirect: true, into: File.stream!(path), decode_body: false)
    |> handle_download_to(path)
  end

  @doc "Upload raw bytes or a file to a signed URL with `content_type`."
  @spec upload(String.t(), upload_body(), String.t(), opts()) :: :ok | {:error, Error.t()}
  def upload(upload_url, body, content_type, opts \\ []) do
    with {:ok, request_body, extra_headers} <- upload_body(body) do
      opts
      |> request(
        method: :put,
        url: upload_url,
        body: request_body,
        headers: [{"content-type", content_type} | extra_headers]
      )
      |> handle_upload()
    end
  end

  defp request(opts, request_options) do
    opts = Keyword.validate!(opts, req_options: [])

    opts
    |> Keyword.fetch!(:req_options)
    |> Req.new()
    |> Req.Request.delete_header(@api_key_header)
    |> Req.request(request_options)
  rescue
    exception -> {:error, Error.network(exception)}
  end

  defp upload_body(body) when is_binary(body), do: {:ok, body, []}

  defp upload_body({:file, path}) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, size: size}} ->
        {:ok, File.stream!(path, @file_chunk_size), [{"content-length", Integer.to_string(size)}]}

      {:ok, %File.Stat{}} ->
        {:error, Error.network(File.Error.exception(reason: :eisdir, action: "stream", path: path))}

      {:error, reason} ->
        {:error, Error.network(File.Error.exception(reason: reason, action: "stream", path: path))}
    end
  end

  defp handle_download({:ok, %Req.Response{status: status, body: body}}) when status in 200..299, do: {:ok, body}

  defp handle_download({:ok, %Req.Response{status: status, body: body}}), do: {:error, Error.http(status, body)}

  defp handle_download({:error, %Error{} = error}), do: {:error, error}
  defp handle_download({:error, exception}), do: {:error, Error.network(exception)}

  defp handle_download_to({:ok, %Req.Response{status: status, body: body}}, path) when status in 200..299 do
    case body do
      # The built-in Finch adapter already streamed the body into the collectable.
      "" ->
        {:ok, path}

      # A custom adapter module returned the accumulated body without streaming.
      data ->
        File.write!(path, data)
        {:ok, path}
    end
  end

  defp handle_download_to({:ok, %Req.Response{status: status, body: body}}, _path), do: {:error, Error.http(status, body)}

  defp handle_download_to({:error, %Error{} = error}, _path), do: {:error, error}
  defp handle_download_to({:error, exception}, _path), do: {:error, Error.network(exception)}

  defp handle_upload({:ok, %Req.Response{status: status}}) when status in 200..299, do: :ok

  defp handle_upload({:ok, %Req.Response{status: status, body: body}}), do: {:error, Error.http(status, body)}

  defp handle_upload({:error, %Error{} = error}), do: {:error, error}
  defp handle_upload({:error, exception}), do: {:error, Error.network(exception)}
end
