defmodule Tapper.Plug.HeaderPropagation do
  @moduledoc "Decode/Encode [B3](https://github.com/openzipkin/b3-propagation) Headers to/from trace properties."

  require Logger

  @b3_trace_id_header "x-b3-traceid"
  @b3_span_id_header "x-b3-spanid"
  @b3_parent_span_id_header "x-b3-parentspanid"
  @b3_sampled_header "x-b3-sampled"
  @b3_flags_header "x-b3-flags"

  @type sampled :: boolean() | :absent

  @doc """
  Decode [B3](https://github.com/openzipkin/b3-propagation) headers from a list of `{header_name, header_value}` tuples.

  Returns either the atom `:start` if (valid) B3 headers were not present (which is a suggestion,
  rather than an instruction, since sampling is a separate concern), or the tuple
  `{:join, trace_id, span_id, parent_span_id, sampled, debug}` which passes on the decoded
  values of the B3 headers. Note that if the parent_span_id is absent, implying the root
  span, this function sets it to the atom `:root`, rather than `nil`.

  Whether the trace should be sampled on a `:join` result depends on the values of `sampled` and `debug`.
  `sampled` can be `true` (the originator is sampling this trace, and expects us to do so too) or `false`
  when the originator is not sampling this trace and doesn't expect us to either, or the atom `:absent`
  when the originator does not pass the `X-B3-Sampled` header, implying that determining whether to trace
  is up to us. The `debug` flag, if `true` implies  we should always sample the trace regardless of the
  `sampled` status:

  | Result | `sampled` | `debug` | should sample? |
  | ------ | ------- | ----- | -------------- |
  | :join  | false   | false | no             |
  | :join  | true    | false | yes            |
  | :join  | false   | true  | yes            |
  | :join  | true    | true  | yes            |
  | :join  | :absent | true  | yes            |
  | :join  | :absent | false | maybe          |

  """
  @spec decode([{String.t, String.t}]) :: {:join, Tapper.Id.TraceId.t, Tapper.Id.SpanId.t, Tapper.Id.SpanId.t, sampled(), boolean()} | :start
  def decode(headers) do
    with {@b3_trace_id_header, trace_id} <- List.keyfind(headers, @b3_trace_id_header, 0),
      {@b3_span_id_header, span_id} <- List.keyfind(headers, @b3_span_id_header, 0),
      {@b3_parent_span_id_header, parent_span_id} <- List.keyfind(headers, @b3_parent_span_id_header, 0, {@b3_parent_span_id_header, :root}),
      {:ok, trace_id} <- Tapper.TraceId.parse(trace_id),
      {:ok, span_id} <- Tapper.SpanId.parse(span_id),
      {:ok, parent_span_id} <- if(parent_span_id == :root, do: {:ok, :root}, else: Tapper.SpanId.parse(parent_span_id))
    do
      sample = case List.keyfind(headers, @b3_sampled_header, 0) do
        {_, "1"} -> true
        {_, "0"} -> false
        nil -> :absent
        _ -> false
      end

      debug = case List.keyfind(headers, @b3_flags_header, 0) do
        {_, "1"} -> true
        _ -> false
      end

      {:join, trace_id, span_id, parent_span_id, sample, debug}
    else
      nil ->
        Logger.debug("No B3 headers (or incomplete ones)")
        :start
      :error ->
        Logger.info(fn -> "Bad B3 headers #{inspect headers}" end)
        :start
    end

  end

  @doc """
  Encode a Tapper id into a list of B3 propagation headers,
  i.e. a list of 2-tuples like `{"x-b3-traceid", "463ac35c9f6413ad48485a3953bb6124"}`.

  ## Example
  ```
    id = Tapper.start_span(id, name: "foo")
  ...
    headers = Tapper.Plug.HeaderPropagation.encode(id)
    response = HTTPoison.get("http://some.service.com/some/api", headers)
  ```
  """
  @spec encode(Tapper.Id.t) :: [{String.t, String.t}]
  def encode(id = %Tapper.Id{}) do
    encode(Tapper.Id.destructure(id))
  end

  @spec encode({String.t, String.t, String.t, boolean(), boolean()}) :: [{String.t, String.t}]
  def encode({trace_id, span_id, parent_span_id, sample, debug}) when is_binary(trace_id) and is_binary(span_id) and is_binary(parent_span_id) do
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

end
