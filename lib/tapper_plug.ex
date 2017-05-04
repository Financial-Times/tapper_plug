defmodule Tapper.Plug do
  @moduledoc """
  [Plug](https://github.com/elixir-lang/plug) integration for [Tapper](https://github.com/Financial-Times/tapper).

     * `Tapper.Plug.Filter` - disables tracing entirely for matching URLs.
     * `Tapper.Plug.Trace` - intercepts B3 headers and joins or samples trace.
  """

  import Plug.Conn

  @spec store(Plug.Conn.t, Tapper.Id.t | :ignore) :: Plug.Conn.t
  def store(conn = %Plug.Conn{}, :ignore), do: put_private(conn, :tapper_plug, :ignore)
  def store(conn = %Plug.Conn{}, id = %Tapper.Id{}), do: put_private(conn, :tapper_plug, id)

  @spec fetch(Plug.Conn.t | map()) :: Tapper.Id.t | :ignore
  def fetch(conn = %Plug.Conn{}), do: conn.private[:tapper_plug]
  def fetch(%{tapper_plug: id}), do: id
  def fetch(_), do: :ignore

  defmodule Trace do
    @moduledoc """
    Intercept B3 headers and join a trace, or run a sampler to determine whether to start a new trace.

    If starting a trace, a 'server receive' (sr) annotation will be added to the root span, as well
    as details about the request.

    ```
    plug Tapper.Plug.Trace, sampler: Tapper.Plug.Sampler.Simple
    ```
    or e.g.
    ```
    plug Tapper.Plug.Trace, sampler: fn(conn, _config) -> String.starts_with?(conn.request_path, ["/foo", "/bar"]) end
    ```

    ## Options

       * sampler - name of module with `sample?/2`, or a fun with arity 2, to call to determine whether to sample a request; see `Tapper.Plug.Sampler`.
       * debug - if set to `true` all requests, joined or started, will be sampled.

    Other options will be passed to the sampler function, which allows you to configure it here too.
    """
    def init(opts) do
      config = %{
        sampler: Keyword.get(opts, :sampler, Tapper.Plug.Sampler.Simple),
        debug: Keyword.get(opts, :debug, false)
      }
      Enum.into(Keyword.drop(opts, [:sampler, :debug]), config)
    end

    def call(conn = %Plug.Conn{private: %{tapper_plug: :ignore}}, _), do: conn

    def call(conn, config) do
      conn = case Tapper.Plug.HeaderPropagation.decode(conn.req_headers) do
        {:join, trace_id, span_id, parent_id, sample, debug} ->
          join(conn, config, trace_id, span_id, parent_id, sample, debug)

        :start ->
          start(conn, config)
      end

      conn
      |> register_before_send(&Tapper.Plug.Finish.annotate/1)

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
        fun when is_function(fun, 2) -> fun.(conn, config)
        mod when is_atom(mod) -> apply(mod, :sample?, [conn, config])
      end
    end

  end

  defmodule Finish do
    @moduledoc """
    Finish a trace, if tracing, attaching a 'server send' (ss) annotation to the root span.
    Called from registered call-back function.
    """
    def annotate(conn) do
      id = Tapper.Plug.fetch(conn)

      id
      |> Tapper.server_send()
      |> Tapper.http_status_code(conn.status)

      conn
    end
  end

end