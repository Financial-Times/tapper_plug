# Tapper.Plug

[Plug](https://github.com/elixir-lang/plug) integration for the [Tapper](https://github.com/Financial-Times/tapper) Zipkin client.

## Synopsis

Add plugs to your pipeline to add Tapper tracing to each request, e.g. in your Phoenix `Endpoint`:

```elixir
plug Tapper.Plug.Filter, prefixes: ["__gtg", "foo/bar"]  ## (1) ignored URL prefixes

plug Tapper.Plug.Trace  ## (2) intercept incoming B3 headers, start trace

# other plugs
plug Plug.RequestId

plug Myapp.Web.Router  # standard Phoenix router etc.
```

1. you can exclude certain URLs for the purposes of tracing using the optional `Tapper.Plug.Filter`.
2. install the `Tapper.Plug.Trace` plug as soon as possible in the plug list, for accuracy. This plug reads any incoming [B3](https://github.com/openzipkin/b3-propagation) style headers, and either joins the incoming span, or starts a new one (dependent on result of sampling), adding a 'server receive' annotation, and various other binary annotations with incoming request details.

## Obtaining the Trace Id in Request Handlers

You can retrieve the Tapper Trace id from the `%Plug.Conn{}` using the `Tapper.Plug.get/1` function, and then use it to start child spans etc.:

```elixir
id = Tapper.Plug.get(conn)

id = Tapper.start_span(id, name: "remote api call")
|> Tapper.http_host("www.my-service.com")

...

id = Tapper.finish_span(id)
```

It is the application's responsibility to maintain the Trace Id across its child-spans, but it should not update the id in the `Plug.Conn` as it goes, since this plug is only interested in
the top-level trace.

### See also

* [Tapper.Plug.Absinthe](https://github.com/Financial-Times/tapper_absinthe_plug) - propagate Tapper Id to [Absinthe](http://absinthe-graphql.org/) resolvers.

## Filtering with Tapper.Plug.Filter

This filter takes a list of URL path prefixes to be excluded from sampling, even if a sampled or debug B3 header is sent.

The prefixes can be in specified as a list of segments, or path strings:

```elixir
plug Tapper.Plug.Filter, prefixes: ["__gtg", "foo/bar"]

# is equivalent to
plug Tapper.Plug.Filter, prefixes: [["__gtg"], ["foo","bar"]]
```

For matching paths, sets the tapper id to `:ignore`, which is matched to a no-op in the `Tapper` API.

## Sampling

The default sampler is [`Tapper.Plug.Sampler.Simple`](lib/sampler.ex), which samples a percentage of requests,
where the percentage is specified with a `percent` option (default 10%):

```elixir
plug Tapper.Plug.Trace, percent: 25 # sample 25% of requests
```

`Tapper.Plug.Trace` also takes a `sampler` option, specifying a module with a `sample?/2` function,
or a `fun/2`, to call with the `Plug.Conn` and the plug's configuration; this
function should return `true` if a trace is to be sampled:

```elixir
# silly example shows conn and config is passed to sampler
plug Tapper.Plug.Trace, x: "/foo", sampler: fn
    (conn, config) -> String.starts_with?(conn.request_path, config[:x]) 
  end
```

The sampler is only called if:

* the trace is not already sampled due to an incoming header,
* the `debug` option on the `Trace` plug is not set to `true`.

> Note that you cannot turn sampling on for a trace after `Tapper.Plug.Trace` has determined
that sampling should not take place; this is because this causes operations to become no-ops.
A work-around for this, to allow traces to be sampled post-fact, may be included in future versions, 
but for now, you could hard-code the `debug` flag to `true`, and take care of
determining whether to report a trace in an implementation of Tapper's reporter.

## Propagating a Trace Downstream

`Tapper.Plug.HeaderPropagation.decode/1` will decode a Tapper Id into [B3](https://github.com/openzipkin/b3-propagation) headers suitable for passing to HTTPoison etc.
for propagation to down-stream servers:

```elixir
id = Tapper.start_span(id, name: "call-out")

headers = Tapper.Plug.HeaderPropagation.encode(id)

response = HTTPoison.get("http://some.service.com/some/api", headers)
```

For non-HTTP propagation, you could translate the headers to whatever structure you need to populate.

## Installation

For the latest pre-release (and unstable) code, add github repo to your mix dependencies:

```elixir
def deps do
  [{:tapper_plug, git: "https://github.com/Financial-Times/tapper_plug"}]
end
```

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `tapper_plug` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:tapper_plug, "~> 0.1.0"}]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/tapper_plug](https://hexdocs.pm/tapper_plug).

