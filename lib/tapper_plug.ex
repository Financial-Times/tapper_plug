defmodule Tapper.Plug do

  import Plug.Conn

  @spec store(Plug.Conn.t, Tapper.Id.t | :ignore) :: Plug.Conn.t
  def store(conn = %Plug.Conn{}, :ignore), do: put_private(conn, :tapper_plug, :ignore)
  def store(conn = %Plug.Conn{}, id = %Tapper.Id{}), do: put_private(conn, :tapper_plug, id)

  @spec fetch(Plug.Conn.t | map()) :: Tapper.Id.t | :ignore
  def fetch(conn = %Plug.Conn{}), do: conn.private[:tapper_plug]
  def fetch(%{tapper_plug: id}), do: id
  def fetch(_), do: :ignore

  defmodule Start do
    def init(opts) do
      %{
        sampler: Keyword.get(opts, :sampler, Tapper.Plug.Sampler.Simple),
        debug: Keyword.get(opts, :debug, false)
      }
    end

    def call(conn = %Plug.Conn{private: %{tapper_plug: :ignore}}, _), do: conn

    def call(conn, config) do
      case Tapper.Plug.HeaderPropagation.decode(conn.req_headers) do
        {:join, trace_id, span_id, parent_id, sample, debug} ->
          join(conn, config, trace_id, span_id, parent_id, sample, debug)

        :start ->
          start(conn, config)
      end
    end

    @doc "join a trace, running the sampler if 'sampled' not expicitly sent"
    def join(conn, config, trace_id, span_id, parent_id, sample, debug)

    def join(conn, config, trace_id, span_id, parent_id, :absent, true) do
      join(conn, config, trace_id, span_id, parent_id, false, true)
    end

    def join(conn, config, trace_id, span_id, parent_id, :absent, false) do
      sample = sample_request(conn, config)
      join(conn, config, trace_id, span_id, parent_id, sample, false)
    end

    def join(conn, config, trace_id, span_id, parent_id, sample, debug) do
      id = Tapper.join(trace_id, span_id, parent_id, sample, debug || config[:debug])

      annotate(id, conn, config)

      Tapper.Plug.store(conn, id)
    end

    @doc "start a trace, running the sampler"
    def start(conn, config) do
      sample = sample_request(conn, config)

      id = Tapper.start(type: :server, sample: sample, debug: config[:debug])

      annotate(id, conn, config)

      Tapper.Plug.store(conn, id)
    end

    def annotate(id, conn, _config) do
      id
      |> Tapper.client_address(%Tapper.Endpoint{ipv4: conn.remote_ip})
      |> Tapper.http_host(conn.host)
      |> Tapper.http_method(conn.method)
      |> Tapper.http_path(conn.request_path)
    end

    def sample_request(conn, config = %{sampler: sampler}) do
      case sampler do
        fun when is_function(fun,2) -> fun.(conn, config)
        mod when is_atom(mod) -> apply(mod, :sample, [conn, config])
      end
    end

  end

  defmodule Finish do
    def init(_) do
      []
    end

    def call(conn = %Plug.Conn{private: %{tapper_plug: :ignore}}, _), do: conn

    def call(conn, config) do
      id = Tapper.Plug.fetch(conn)
      annotate(id, config, conn)

      # TODO support async
      Tapper.finish(id)
    end

    def annotate(id, _conn, _config) do
      Tapper.server_send(id)
    end

  end

end