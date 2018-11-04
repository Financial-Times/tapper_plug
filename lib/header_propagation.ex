defmodule Tapper.Plug.HeaderPropagation do
  @moduledoc """
  Decode/Encode [B3](https://github.com/openzipkin/b3-propagation) headers to/from trace context.

  Sub-module `Tapper.Plug.HeaderPropagation.B3Multi` supports the orginal
  [B3 multi-header format](https://github.com/openzipkin/b3-propagation/blob/master/README.md),
  whilst `Tapper.Plug.HeaderPropagation.B3Single` supports the newer
  [B3 Single format](https://cwiki.apache.org/confluence/display/ZIPKIN/b3+single+header+format).

  On *decode*, this module first tries to locate and decode a `b3` header in B3 Single format,
  and if it doesn't exist, tries to find and decode the multiple B3 headers format. If neither
  exist, the caller is free to decide whether to sample the trace.

  On *encode* the format is entirely up to the caller, and which module they choose to call.

  > NB The decode APIs are currently semi-private to this module (and `Tapper.Plug`), and are therefore
  subject to change in minor versions. The encoding APIs are stable across minor versions.
  """

  require Logger

  @b3_trace_id_header "x-b3-traceid"
  @b3_span_id_header "x-b3-spanid"
  @b3_single_header "b3"

  @type sampled :: boolean() | :absent

  defmodule B3Multi do
    @moduledoc """
    Supports encoding and decoding a Tapper trace context in the original
    [B3 propagation format](https://github.com/openzipkin/b3-propagation/blob/master/README.md),
    typically represented in HTTP(S) as a set of `x-b3-*` headers.
    """

    @b3_trace_id_header "x-b3-traceid"
    @b3_span_id_header "x-b3-spanid"
    @b3_parent_span_id_header "x-b3-parentspanid"
    @b3_sampled_header "x-b3-sampled"
    @b3_flags_header "x-b3-flags"

    @doc """
    decode `x-b3-*` headers to a tagged trace context.
    """
    @spec decode(headers :: %{required(String.t()) => String.t()}) :: tuple()
    def decode(
          %{@b3_trace_id_header => raw_trace_id, @b3_span_id_header => raw_span_id} = headers
        ) do
      raw_parent_span_id = Map.get(headers, @b3_parent_span_id_header, :root)

      with {:ok, trace_id} <- Tapper.TraceId.parse(raw_trace_id),
           {:ok, span_id} <- Tapper.SpanId.parse(raw_span_id),
           {:ok, parent_span_id} <-
             if(raw_parent_span_id == :root,
               do: {:ok, :root},
               else: Tapper.SpanId.parse(raw_parent_span_id)
             ) do
        sample =
          case Map.get(headers, @b3_sampled_header) do
            "1" -> true
            "0" -> false
            nil -> :absent
            _ -> false
          end

        debug =
          case Map.get(headers, @b3_flags_header) do
            "1" -> true
            _ -> false
          end

        {:join, trace_id, span_id, parent_span_id, sample, debug}
      else
        :error ->
          Logger.info(fn -> "Bad B3 headers #{inspect(headers)}" end)
          :start
      end
    end

    def decode(_), do: :start

    @doc """
    Encode a Tapper id into a list of B3 propagation headers.

    i.e. a list of 2-tuples like `{"x-b3-traceid", "463ac35c9f6413ad48485a3953bb6124"}`.

    This encodes headers in the original B3 multi-header format, to use the B3 Single format,
    use `Tapper.Plug.HeaderPropagation.B3Single.encode_value/1`.

    ## Example
    ```
      id = Tapper.start_span(id, name: "foo")
    ...
      headers = Tapper.Plug.HeaderPropagation.B3Multi.encode(id)
      response = HTTPoison.get("http://some.service.com/some/api", headers)
    ```
    """
    @spec encode(Tapper.Id.t() | tuple()) :: [{binary(), binary()}]
    def encode(idOrDestructed)

    def encode(%Tapper.Id{} = id) do
      encode(Tapper.Id.destructure(id))
    end

    def encode({trace_id, span_id, parent_span_id, sample, debug})
        when is_binary(trace_id) and is_binary(span_id) and is_binary(parent_span_id) do
      headers = [
        {@b3_trace_id_header, trace_id},
        {@b3_span_id_header, span_id},
        {@b3_sampled_header, if(sample, do: "1", else: "0")},
        {@b3_flags_header, if(debug, do: "1", else: "0")}
      ]

      case parent_span_id do
        "" -> headers
        parent_span_id -> [{@b3_parent_span_id_header, parent_span_id} | headers]
      end
    end

    def encode(:ignore), do: []
  end

  defmodule B3Single do
    @moduledoc """
    [B3 Single format](https://cwiki.apache.org/confluence/display/ZIPKIN/b3+single+header+format) allows
    the `Tapper.Id` trace context to be encoded in a single string value.

    Typically this is sent/received as a `b3` header in HTTP(S), or in a W3C `trace-state` as the `b3` property.
    """

    @doc "decode a B3 Single format string into a tagged trace context."
    def decode(b3_single) when is_binary(b3_single) do
      with {raw_trace_id, raw_span_id, rest} <- decode_mandatory(b3_single),
           {sample_or_debug, raw_parent_span_id} <- decode_optional(rest),
           {:ok, trace_id} <- Tapper.TraceId.parse(raw_trace_id),
           {:ok, span_id} <- Tapper.SpanId.parse(raw_span_id),
           {:ok, parent_span_id} <-
             if(raw_parent_span_id == :root,
               do: {:ok, :root},
               else: Tapper.SpanId.parse(raw_parent_span_id)
             ) do
        {sample, debug} =
          case sample_or_debug do
            "d" -> {false, true}
            "1" -> {true, false}
            "0" -> {false, false}
            _ -> {:absent, false}
          end

        {:join, trace_id, span_id, parent_span_id, sample, debug}
      else
        _ -> :start
      end
    end

    defp decode_optional(<<"-", flag::bytes-size(1), "-", raw_parent_span_id::bytes-size(16)>>)
         when flag in ["0", "1", "d"],
         do: {flag, raw_parent_span_id}

    defp decode_optional(<<"-", _flag::bytes-size(1), "-", _garbage>>),
      do: :error

    defp decode_optional(<<"-", "d">>), do: {"d", :root}
    defp decode_optional(<<"-", "0">>), do: {"0", :root}
    defp decode_optional(<<"-", "1">>), do: {"1", :root}

    defp decode_optional(<<>>), do: {:absent, :root}

    defp decode_optional(_), do: :error

    defp decode_mandatory(
           <<raw_trace_id::bytes-size(32), "-", raw_span_id::bytes-size(16), rest::binary>>
         ) do
      {raw_trace_id, raw_span_id, rest}
    end

    defp decode_mandatory(_), do: :error

    @doc "encode a `Tapper` trace context to B3 Single format string; use this to set an appropriate downstream header or property."
    @spec encode_value(idOrDestructured :: Tapper.Id.t() | tuple()) :: binary()
    def encode(idOrDestructed)

    def encode(%Tapper.Id{} = id) do
      encode_value(Tapper.Id.destructure(id))
    end

    def encode_value({trace_id, span_id, "", _, true}) do
      trace_id <> "-" <> span_id <> "-d"
    end

    def encode_value({trace_id, span_id, "", true, false}) do
      trace_id <> "-" <> span_id <> "-1"
    end

    def encode_value({trace_id, span_id, "", _, _}) do
      trace_id <> "-" <> span_id <> "-0"
    end

    def encode_value({trace_id, span_id, parent_span_id, _, true}) do
      trace_id <> "-" <> span_id <> "-d-" <> parent_span_id
    end

    def encode_value({trace_id, span_id, parent_span_id, true, false}) do
      trace_id <> "-" <> span_id <> "-1-" <> parent_span_id
    end

    def encode_value({trace_id, span_id, parent_span_id, _, _}) do
      trace_id <> "-" <> span_id <> "-0-" <> parent_span_id
    end
  end

  @doc """
  Decode [B3](https://github.com/openzipkin/b3-propagation) headers from a list of `{header_name, header_value}` tuples,
  supporting multiple B3 propagation formats.

  Returns either the atom `:start` if (valid) B3 headers were not present (which is a suggestion,
  rather than an instruction, since sampling is a separate concern), or the tuple
  `{:join, trace_id, span_id, parent_span_id, sampled, debug}` which passes on the decoded
  values of the B3 headers. Note that if the `parent_span_id` is absent, implying the root
  span, this function sets it to the atom `:root`, rather than `nil`.

  Whether the trace should be sampled on a `:join` result depends on the values of `sampled` and `debug`.
  `sampled` can be `true` (the originator is sampling this trace, and expects us to do so too) or `false`
  when the originator is not sampling this trace and doesn't expect us to either, or the atom `:absent`
  when the originator does not pass the `X-B3-Sampled` header, implying that determining whether to trace
  is up to us. The `debug` flag, if `true` implies  we should always sample the trace regardless of the
  `sampled` status:

  | Result | trace ids? | `sampled` | `debug` | should sample? |
  | ------ | ---------- | --------- | ------- | -------------- |
  | :join  | true       | false     | false   | no             |
  | :join  | true       | true      | false   | yes            |
  | :join  | true       | false     | true    | yes            |
  | :join  | true       | true      | true    | yes            |
  | :join  | true       | :absent   | true    | yes            |
  | :join  | true       | :absent   | false   | maybe          |

  """
  @spec decode([{String.t(), String.t()}] | map) ::
          {:join, Tapper.TraceId.t(), Tapper.SpanId.t(), Tapper.SpanId.t(), sampled(), boolean()}
          | :start
  def decode(headers) when is_list(headers) do
    header_map = Map.new(headers)
    decode(header_map)
  end

  def decode(%{@b3_single_header => b3_single}), do: B3Single.decode(b3_single)

  def decode(%{@b3_trace_id_header => _, @b3_span_id_header => _} = headers),
    do: B3Multi.decode(headers)

  def decode(_), do: :start

  @doc """
  Encode a Tapper id into a list of B3 Multi format propagation headers,
  i.e. a list of 2-tuples like `{"x-b3-traceid", "463ac35c9f6413ad48485a3953bb6124"}`.

  > This encodes to headers in the original B3 multi-header format, to use the B3 Single format,
    use `Tapper.Plug.HeaderPropagation.B3Single.encode_value/1`.

  ## Example
  ```
    id = Tapper.start_span(id, name: "foo")
  ...
    headers = Tapper.Plug.HeaderPropagation.encode(id)
    response = HTTPoison.get("http://some.service.com/some/api", headers)
  ```
  """
  @spec encode(Tapper.Id.t() | {String.t(), String.t(), String.t(), boolean(), boolean()}) :: [
          {String.t(), String.t()}
        ]
  defdelegate encode(trace), to: B3Multi
end
