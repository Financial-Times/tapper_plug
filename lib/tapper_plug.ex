defmodule Tapper.Plug do
  @moduledoc """
  [Plug](https://github.com/elixir-lang/plug) integration for [Tapper](https://github.com/Financial-Times/tapper).

  * `Tapper.Plug.Trace` - intercepts [B3](https://github.com/openzipkin/b3-propagation) headers and joins or samples trace.
  * `Tapper.Plug.Filter` - disables tracing entirely for matching URLs.
  """

  import Plug.Conn

  @doc "store Tapper trace id in connection"
  @spec store(conn :: Plug.Conn.t, id :: Tapper.Id.t | :ignore) :: Plug.Conn.t
  def store(conn, id)
  def store(conn = %Plug.Conn{}, :ignore), do: put_private(conn, :tapper_plug, :ignore)
  def store(conn = %Plug.Conn{}, id = %Tapper.Id{}), do: put_private(conn, :tapper_plug, id)

  @doc "fetch Tapper trace id from connection "
  @spec fetch(conn :: Plug.Conn.t | map()) :: Tapper.Id.t | :ignore
  def fetch(conn)
  def fetch(conn = %Plug.Conn{}), do: conn.private[:tapper_plug]
  def fetch(%{tapper_plug: id}), do: id
  def fetch(_), do: :ignore

  defmodule Trace do
    @moduledoc """
    Intercept [B3](https://github.com/openzipkin/b3-propagation) headers and join a sampled trace, or run a sampler to determine whether to start a new trace.

    If starting a trace, a 'server receive' (`sr`) annotation will be added to the root span, as well
    as details about the request. A call-back is installed to finish the trace at the end of the request,
    adding additional `http.status_code` and a 'server send' (`ss`) annotations.

    ```
    plug Tapper.Plug.Trace, sampler: Tapper.Plug.Sampler.Simple, percent: 25
    ```
    or e.g.
    ```
    plug Tapper.Plug.Trace, sampler: fn(conn, _config) -> String.starts_with?(conn.request_path, ["/foo", "/bar"]) end
    ```

    ## Options

    * `sampler` - name of module with `sample?/2`, or a fun with arity 2, to call to determine whether to sample a request; see `Tapper.Plug.Sampler`.
    * `debug` - if set to `true` all requests, joined or started, will be sampled.
    * `tapper` - keyword list passed on to `Tapper.start/1` or `Tapper.join/6` (useful for testing/debugging, but use with caution
      since overrides options set by this module).

    All options, including custom ones, will be passed to the `sampler` function (as a map), which means it can be configured here too.

    ## Annotations
    `Tapper.Plug` sets the following annotations:
    * `sr` - server receive on starting or joining a trace.
    * `ca` - client address, from `conn.remote_ip`.
    * `http.host`, `http.method`, `http.path` - from corresponding `Plug.Conn` fields.
    * `ss` - server send when finishing a trace.
    """

    @behaviour Plug

    def init(opts) do
      config = %{
        sampler: Keyword.get(opts, :sampler, Tapper.Plug.Sampler.Simple),
        debug: Keyword.get(opts, :debug, false),
        tapper: Keyword.get(opts, :tapper, [])
      }
      Enum.into(Keyword.drop(opts, [:sampler, :debug, :tapper]), config)
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
      |> register_before_send(&Tapper.Plug.Trace.Finish.annotate/1)

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
      tapper_opts = Keyword.merge([
          type: :server,
          annotations: annotations(conn, config)
        ],
        config[:tapper])

      id = Tapper.join(trace_id, span_id, parent_id, sample, debug || config[:debug], tapper_opts)

      Tapper.Plug.store(conn, id)
    end

    @doc "start a trace, running the sampler"
    def start(conn, config) do
      sample = sample_request(conn, config)

      tapper_opts = Keyword.merge(
        [
          type: :server,
          sample: sample,
          debug: config[:debug],
          annotations: annotations(conn, config)
        ],
        config[:tapper]
      )

      id = Tapper.start(tapper_opts)

      Tapper.Plug.store(conn, id)
    end

    @doc false
    def annotations(conn, _config) do
      [
        Tapper.client_address(%Tapper.Endpoint{ip: conn.remote_ip}),
        Tapper.http_host(conn.host),
        Tapper.http_method(conn.method),
        Tapper.http_path(conn.request_path)
      ]
    end

    @doc false
    def sample_request(conn, config = %{sampler: sampler}) do
      case sampler do
        fun when is_function(fun, 2) -> fun.(conn, config)
        mod when is_atom(mod) -> apply(mod, :sample?, [conn, config])
      end
    end

  end

  defmodule Trace.Finish do
    @moduledoc """
    Finishes a trace, if tracing, attaching a 'server send' (`ss`) annotation to the root span.
    Called as call-back function registered with the `Plug.Conn`.
    """

    @doc """
    annotates the trace with a 'server send' (`ss`) and tags with status code.
    """
    def annotate(conn) do
      id = Tapper.Plug.fetch(conn)

      Tapper.finish(id, annotations: [
        Tapper.server_send(),
        Tapper.http_status_code(conn.status),
      ])

      conn
    end
  end

end
