# Tapper.Plug

[Plug](https://github.com/elixir-lang/plug) integration for the [Tapper](https://github.com/Financial-Times/tapper) Zipkin client.

[![Hex pm](http://img.shields.io/hexpm/v/tapper_plug.svg?style=flat)](https://hex.pm/packages/tapper_plug) [![Inline docs](http://inch-ci.org/github/Financial-Times/tapper_plug.svg)](http://inch-ci.org/github/Financial-Times/tapper_plug) [![Build Status](https://travis-ci.org/Financial-Times/tapper_plug.svg?branch=master)](https://travis-ci.org/Financial-Times/tapper_plug)

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
2. install the `Tapper.Plug.Trace` plug as soon as possible in the plug list, for timing accuracy. This plug reads any incoming [B3](https://github.com/openzipkin/b3-propagation) style headers, and either joins the incoming span, or starts a new one (dependent on result of sampling), adding a 'server receive' annotation, and various other binary annotations with incoming request details.

### See also

* [Tapper.Plug.Absinthe](https://github.com/Financial-Times/tapper_absinthe_plug) - propagate Tapper Id to [Absinthe](http://absinthe-graphql.org/) resolvers.

The API documentation can be found at [https://hexdocs.pm/tapper_plug](https://hexdocs.pm/tapper_plug).

## Obtaining the Trace Id in Request Handlers

You can retrieve the Tapper Id from the `%Plug.Conn{}` using the `Tapper.Plug.fetch/1` function, and then use it to start child spans etc.:

```elixir
id = Tapper.Plug.fetch(conn) # get top-level span id

id = Tapper.start_span(id, name: "remote api call") # use it
...

id = Tapper.finish_span(id)
```

It is the application's responsibility to maintain the Tapper Id locally through its child-spans.

## Filtering with Tapper.Plug.Filter

This filter takes a list of URL path prefixes to be excluded from sampling, even if a sampled or debug B3 header is sent.

The prefixes can be in specified as a list of segments, or path strings:

```elixir
plug Tapper.Plug.Filter, prefixes: ["__gtg", "foo/bar"]

# is equivalent to
plug Tapper.Plug.Filter, prefixes: [["__gtg"], ["foo", "bar"]]
```

For matching paths, the filter sets the Tapper id to `:ignore`, which is matched to a no-op in the `Tapper` API.

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

* the trace is not already sampled due to an incoming header, and
* the `debug` option on the `Trace` plug is not set to `true`.

> Note that you cannot turn sampling on for a trace after `Tapper.Plug.Trace` has determined
that sampling should not take place; this is because this causes operations to become no-ops for performance reasons.
A work-around for this, to allow traces to be sampled after some interesting event has occurred, may be included in future versions,
but for now, you could hard-code the `debug` flag to `true`, and take care of
determining whether to report a trace in an implementation of Tapper's reporter.

## Propagating a Trace Downstream

`Tapper.Plug.HeaderPropagation.encode/1` will encode a Tapper Id into [B3](https://github.com/openzipkin/b3-propagation) headers (as a keyword list) suitable for
passing to HTTPoison etc. for propagation to down-stream servers:

```elixir
id = Tapper.start_span(id, name: "call-out")

headers = Tapper.Plug.HeaderPropagation.encode(id)

response = HTTPoison.get("http://some.service.com/some/api", headers)
```

For non-HTTP propagation, you could translate the headers to whatever structure you need to populate, or use `Tapper.Id.destructure/1` to
obtain the underlying information.

## Installation

For the latest pre-release (and unstable) code, add the github repo to your mix dependencies:

```elixir
def deps do
  [{:tapper_plug, github: "Financial-Times/tapper_plug"}]
end
```

For release versions, the package can be installed by adding `tapper_plug` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:tapper_plug, "~> 0.2"}]
end
```

Ensure the `:tapper` application is present in your mix project's applications:

```elixir
  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {MyApp, []},
      applications: [:tapper]
    ]
  end
```
