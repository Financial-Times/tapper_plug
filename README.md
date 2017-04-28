# TapperPlug

[Plug](https://github.com/elixir-lang/plug) integration for [Tapper](https://github.com/Financial-Times/tapper) Zipkin client.

## Synopsis

Add plugs to your pipeline to add Tapper tracing to each request, e.g. in your Phoenix `Endpoint`:

```elixir
plug Tapper.Plug.PrefixFilter, prefixes: ["__gtg", "foo/bar"]  ## (1) ignored URL prefixes

plug Tapper.Plug.Start  ## (2) intercept incoming B3 headers, start trace

# other plugs
plug Plug.RequestId
...

plug Myapp.Web.Router  # standard Phoenix router

plug Tapper.Plug.Finish ## (3) finish trace spans
```

  1. you can exclude certain URLs for the purposes of tracing using the optional `Tapper.Plug.PrefixFilter`.
  2. install the `Tapper.Plug.Start` plug as soon as possible in the plug list, for accuracy. This plug reads any incoming B3 style headers, and either joins the incoming span, or starts a new one (dependent on result of sampling), adding a 'server receive' annotation, and various other binary annotations with incoming request details.
  3. install the `Tapper.Plug.Finish` plug after most, if not all request processing, for accuracy. This plug finishes the top-level span, adding a 'server send' annotation.

## Obtaining the Trace Id in applications

Applications can retreive the Tapper Trace id from the `%Plug.Conn{}` using the `Tapper.Plug.get/1` function, and then use it to start child spans etc.:

```elixir
id = Tapper.Plug.get(conn)

id 
|> Tapper.start_span(id, name: "remote api call")
|> Tapper.http_host("www.my-service.com")

...

Tapper.finish_span(id)
```

The `get/1` function also works directly from the value of the `private` property, if you only have access to `private`, e.g. in Absinthe.

It is the application's responsibility to maintain the Trace Id across its child-spans, but it need not update the `Plug.Conn` as it goes.

## Filtering with `Tapper.Plug.PrefixFilter`

This filter takes a list of URL path prefixes (in either path or patch-segment list format) which
should be excluded from sampling, even if a sampled or debug B3 header is sent. It sets the
tapper id to `:ignore`, which may be useful to client functions (indeed it is matched to a do a no-op in the
`Tapper` API).

## Sampling

`Tapper.Start.Plug` takes a `sampler` option, specifying a module or fun (arity 2)
to call with the `Plug.Conn` and configuration which should return a boolean a
trace is to be sampled. The default sampler is `Tapper.Plug.Sampler.Simple`. 

The sampler is only called if the trace is not already sampled due to an incoming B3 header,
or due to the `debug` option being set on the plug.

Note that sampling cannot be started after `Tapper.Start.Plug` has determined that sampling
should not take place; this is because this causes operations to become no-ops.

(A work-around is to hard-code the sample flag, and extend the `recorder` function/module
to determine if to actually propagate the trace, at the expense of recording data that might
not be sent. This functionality may be included as standard in future). 

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

