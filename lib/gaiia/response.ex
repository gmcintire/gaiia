defmodule Gaiia.Response do
  @moduledoc """
  A successful GraphQL response, with the transport metadata kept.

  `Gaiia.Client.query/4` unwraps this to `{:ok, data}` because that is what
  most call sites want. Use `Gaiia.Client.request/4` instead when you need the
  rate-limit budget or the raw headers, for example to throttle a bulk job.
  """

  alias Gaiia.RateLimit

  @type t :: %__MODULE__{
          data: map(),
          status: pos_integer(),
          rate_limit: RateLimit.t() | nil,
          headers: map()
        }

  @enforce_keys [:data, :status]
  defstruct data: nil, status: nil, rate_limit: nil, headers: %{}
end
