defmodule Tapper.Plug.Sampler do
  @moduledoc "Behavior for Trace Samplers"

  @callback sample?(conn :: Plug.Conn.t(), config :: map) :: boolean()
end

defmodule Tapper.Plug.Sampler.Simple do
  @moduledoc """
  Simple sampler; sample x percent of traces.

  Specify `:percent` option in `Tapper.Plug.Trace` config.

  ## Example
  ```
  plug Tapper.Plug.Trace, sampler: Tapper.Plug.Sampler.Simple, percent: 25
  ```
  """

  @behaviour Tapper.Plug.Sampler

  def sample?(%Plug.Conn{}, config) do
    # sample X%
    percentage = max(0, min(100, config[:percent] || 10))
    :rand.uniform(100) - 1 < percentage
  end
end
