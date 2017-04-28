defmodule Tapper.Plug.Sampler do
  @callback sample(conn :: Plug.Conn.t, config :: Map.t) :: boolean()
end

defmodule Tapper.Plug.Sampler.Simple do
  @behaviour Tapper.Plug.Sampler

  def sample(_conn = %Plug.Conn{}, _config) do
    # sample 10%
    :rand.uniform(10) == 1
  end
end
