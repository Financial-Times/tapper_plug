defmodule HeaderPropagationTest do
  use ExUnit.Case

  import Tapper.Plug.HeaderPropagation

  describe "decode/1 b3 multi header" do
    test "join a span with parent span id" do
      {:join, {trace_id, _uniq}, span_id, parent_span_id, _sample, _debug} =
        decode([{"x-b3-traceid", "123"}, {"x-b3-spanid", "abc"}, {"x-b3-parentspanid", "ffe"}])

      assert trace_id == String.to_integer("123", 16)
      assert span_id == String.to_integer("abc", 16)
      assert parent_span_id == String.to_integer("ffe", 16)
    end

    test "join a span, no parent span id" do
      {:join, {trace_id, _uniq}, span_id, parent_span_id, _sample, _debug} =
        decode([{"x-b3-traceid", "123"}, {"x-b3-spanid", "abc"}])

      assert trace_id == String.to_integer("123", 16)
      assert span_id == String.to_integer("abc", 16)
      assert parent_span_id == :root
    end

    test "join a span, sampled" do
      {:join, {trace_id, _uniq}, span_id, parent_span_id, sample, debug} =
        decode([
          {"x-b3-traceid", "123"},
          {"x-b3-spanid", "abc"},
          {"x-b3-parentspanid", "ffe"},
          {"x-b3-sampled", "1"}
        ])

      assert trace_id == String.to_integer("123", 16)
      assert span_id == String.to_integer("abc", 16)
      assert parent_span_id == String.to_integer("ffe", 16)

      assert sample == true
      assert debug == false
    end

    test "join a span, not sampled" do
      {:join, {trace_id, _uniq}, span_id, parent_span_id, sample, debug} =
        decode([
          {"x-b3-traceid", "123"},
          {"x-b3-spanid", "abc"},
          {"x-b3-parentspanid", "ffe"},
          {"x-b3-sampled", "0"}
        ])

      assert trace_id == String.to_integer("123", 16)
      assert span_id == String.to_integer("abc", 16)
      assert parent_span_id == String.to_integer("ffe", 16)

      assert sample == false
      assert debug == false
    end

    test "join a span, no sample, debug flag on" do
      {:join, {trace_id, _uniq}, span_id, parent_span_id, sample, debug} =
        decode([
          {"x-b3-traceid", "123"},
          {"x-b3-spanid", "abc"},
          {"x-b3-parentspanid", "ffe"},
          {"x-b3-flags", "1"}
        ])

      assert trace_id == String.to_integer("123", 16)
      assert span_id == String.to_integer("abc", 16)
      assert parent_span_id == String.to_integer("ffe", 16)

      assert sample == :absent
      assert debug == true
    end

    test "start a span: no b3 headers" do
      :start = decode([])
    end

    test "start a span: partial b3 headers" do
      :start = decode([{"x-b3-traceid", "123"}, {"x-b3-parentspanid", "abc"}])
    end

    test "start a span: bad b3 headers" do
      :start =
        decode([{"x-b3-traceid", "123"}, {"x-b3-spanid", "abc"}, {"x-b3-parentspanid", "xffe"}])

      :start =
        decode([{"x-b3-traceid", "123x"}, {"x-b3-spanid", "abc"}, {"x-b3-parentspanid", "ffe"}])

      :start =
        decode([{"x-b3-traceid", ""}, {"x-b3-spanid", "abc"}, {"x-b3-parentspanid", "ffe"}])
    end

    test "bad sample flag is false" do
      {:join, {trace_id, _uniq}, span_id, parent_span_id, sample, debug} =
        decode([
          {"x-b3-traceid", "123"},
          {"x-b3-spanid", "abc"},
          {"x-b3-parentspanid", "ffe"},
          {"x-b3-sampled", "x"}
        ])

      assert trace_id == String.to_integer("123", 16)
      assert span_id == String.to_integer("abc", 16)
      assert parent_span_id == String.to_integer("ffe", 16)

      assert sample == false
      assert debug == false
    end

    test "bad flags is debug false" do
      {:join, {trace_id, _uniq}, span_id, parent_span_id, sample, debug} =
        decode([
          {"x-b3-traceid", "123"},
          {"x-b3-spanid", "abc"},
          {"x-b3-parentspanid", "ffe"},
          {"x-b3-sampled", "1"},
          {"x-b3-flags", "4"}
        ])

      assert trace_id == String.to_integer("123", 16)
      assert span_id == String.to_integer("abc", 16)
      assert parent_span_id == String.to_integer("ffe", 16)

      assert sample == true
      assert debug == false
    end
  end

  @tag :b3_single
  describe "decode/1 b3 single header" do
    test "decode parent span with sampled flag" do
      {:ok, trace_id} = Tapper.TraceId.parse("11223344556677881122334455667788")
      {:ok, span_id} = Tapper.SpanId.parse("0102030405060708")
      {:ok, parent_span_id} = Tapper.SpanId.parse("1020304050607080")
      sample = true
      debug = false

      headers = [{"b3", "11223344556677881122334455667788-0102030405060708-1-1020304050607080"}]

      assert {:join, decoded_trace_id, ^span_id, ^parent_span_id, ^sample, ^debug} =
               decode(headers)

      assert Tapper.TraceId.to_hex(decoded_trace_id) == Tapper.TraceId.to_hex(trace_id)
    end

    test "decode parent span with debug flag" do
      {:ok, trace_id} = Tapper.TraceId.parse("11223344556677881122334455667788")
      {:ok, span_id} = Tapper.SpanId.parse("0102030405060708")
      {:ok, parent_span_id} = Tapper.SpanId.parse("1020304050607080")
      sample = false
      debug = true

      headers = [{"b3", "11223344556677881122334455667788-0102030405060708-d-1020304050607080"}]

      assert {:join, decoded_trace_id, ^span_id, ^parent_span_id, ^sample, ^debug} =
               decode(headers)

      assert Tapper.TraceId.to_hex(decoded_trace_id) == Tapper.TraceId.to_hex(trace_id)
    end

    test "decode root span with sample flag" do
      {:ok, trace_id} = Tapper.TraceId.parse("11223344556677881122334455667788")
      {:ok, span_id} = Tapper.SpanId.parse("0102030405060708")
      sample = true
      debug = false

      headers = [{"b3", "11223344556677881122334455667788-0102030405060708-1"}]

      assert {:join, decoded_trace_id, ^span_id, :root, ^sample, ^debug} = decode(headers)
      assert Tapper.TraceId.to_hex(decoded_trace_id) == Tapper.TraceId.to_hex(trace_id)
    end

    test "decode root span with debug flag" do
      {:ok, trace_id} = Tapper.TraceId.parse("11223344556677881122334455667788")
      {:ok, span_id} = Tapper.SpanId.parse("0102030405060708")
      sample = false
      debug = true

      headers = [{"b3", "11223344556677881122334455667788-0102030405060708-d"}]

      assert {:join, decoded_trace_id, ^span_id, :root, ^sample, ^debug} = decode(headers)
      assert Tapper.TraceId.to_hex(decoded_trace_id) == Tapper.TraceId.to_hex(trace_id)
    end

    test "decode root span without flags" do
      {:ok, trace_id} = Tapper.TraceId.parse("11223344556677881122334455667788")
      {:ok, span_id} = Tapper.SpanId.parse("0102030405060708")
      sample = :absent
      debug = false

      headers = [{"b3", "11223344556677881122334455667788-0102030405060708"}]

      assert {:join, decoded_trace_id, ^span_id, :root, ^sample, ^debug} = decode(headers)
      assert Tapper.TraceId.to_hex(decoded_trace_id) == Tapper.TraceId.to_hex(trace_id)
    end

    test "decode invalid format" do
      assert :start == decode([{"b3", "1122334455667788112233445566778-0102030405060708"}]),
             "bad trace id"

      assert :start == decode([{"b3", "11223344556677881122334455667788-102030405060708"}]),
             "bad span id"

      assert :start == decode([{"b3", "11223344556677881122334455667788-0102030405060708-d-"}]),
             "garbage after flag"

      assert :start ==
               decode([{"b3", "11223344556677881122334455667788-0102030405060708-d-1234"}]),
             "bad parent"

      assert :start ==
               decode([
                 {"b3", "11223344556677881122334455667788-0102030405060708-P-0102030405060708"}
               ]),
             "parent, bad flag"

      assert :start ==
               decode([
                 {"b3", "11223344556677881122334455667788-0102030405060708-dd-0102030405060708"}
               ]),
             "parent, bad flag"

      assert :start ==
               decode([
                 {"b3", "11223344556677881122334455667788-0102030405060708--0102030405060708"}
               ]),
             "parent, bad flag"

      assert :start == decode([{"b3", "11223344556677881122334455667788-0102030405060708-P"}]),
             "bad flag, no parent"

      assert :start ==
               decode([
                 {"b3", "11223344556677881122334455667788-0102030405060708-0102030405060708"}
               ]),
             "parent, no flag"

      assert :start == decode([{"b3", ""}])
      assert :start == decode([{"b3", "-"}])
    end

    test "b3-single used in preference to b3-multi" do
      headers = [
        {"x-b3-traceid", "11223344556677881122334455667788"},
        {"x-b3-spanid", "1122334455667788"},
        {"x-b3-parentspanid", "2030405060708090"},
        {"b3", "11223344556677881122334455667788-0102030405060708-1-2030405060708090"},
        {"x-b3-flags", "1"},
        {"x-b3-sampled", "0"}
      ]

      {:ok, span_id} = Tapper.SpanId.parse("0102030405060708")
      {:ok, parent_span_id} = Tapper.SpanId.parse("2030405060708090")
      assert {:join, _, ^span_id, ^parent_span_id, true, false} = decode(headers)
    end

    test "invalid b3-single rules over valid b3-multi" do
      headers = [
        {"x-b3-traceid", "11223344556677881122334455667788"},
        {"x-b3-spanid", "1122334455667788"},
        {"x-b3-parentspanid", "2030405060708090"},
        {"b3", ""},
        {"x-b3-flags", "1"},
        {"x-b3-sampled", "0"}
      ]

      assert :start = decode(headers)
    end
  end

  @tag :b3_single
  describe "encode b3 single" do
    alias Tapper.Plug.HeaderPropagation.B3Single

    test "encode a root span" do
      id = Tapper.Id.test_id(:root)
      {trace, span, "", true, false} = Tapper.Id.destructure(id)

      single = B3Single.encode(id)

      assert single == trace <> "-" <> span <> "-" <> "1"
    end

    test "encode a root debug span" do
      id = %{Tapper.Id.test_id(:root) | sample: false, debug: true}
      {trace, span, "", _, true} = Tapper.Id.destructure(id)

      single = B3Single.encode(id)

      assert single == trace <> "-" <> span <> "-" <> "d"
    end

    test "encode a root unsampled span" do
      id = %{Tapper.Id.test_id(:root) | sample: false}
      {trace, span, "", false, false} = Tapper.Id.destructure(id)

      single = B3Single.encode(id)

      assert single == trace <> "-" <> span <> "-" <> "0"
    end

    test "encode a parented span" do
      id = Tapper.Id.test_id(Tapper.SpanId.generate())
      {trace, span, parent, true, false} = Tapper.Id.destructure(id)

      single = B3Single.encode(id)

      assert single == trace <> "-" <> span <> "-" <> "1" <> "-" <> parent
    end

    test "encode a parented debug span" do
      id = %{Tapper.Id.test_id(Tapper.SpanId.generate()) | sample: false, debug: true}
      {trace, span, parent, _, true} = Tapper.Id.destructure(id)

      single = B3Single.encode(id)

      assert single == trace <> "-" <> span <> "-" <> "d" <> "-" <> parent
    end

    test "encode a parented unsampled span" do
      id = %{Tapper.Id.test_id(Tapper.SpanId.generate()) | sample: false}
      {trace, span, parent, false, _} = Tapper.Id.destructure(id)

      single = B3Single.encode(id)

      assert single == trace <> "-" <> span <> "-" <> "0" <> "-" <> parent
    end
  end

  describe "encode/1" do
    test "encode id with root parent span" do
      trace_id = "1ee"
      span_id = "2ff"
      parent_span_id = ""

      headers = encode({trace_id, span_id, parent_span_id, true, false})

      assert {"x-b3-traceid", "1ee"} in headers
      assert {"x-b3-spanid", "2ff"} in headers
      assert {"x-b3-sampled", "1"} in headers
      assert {"x-b3-flags", "0"} in headers
      assert not :lists.keymember("x-b3-parentspanid", 1, headers)
    end

    test "encode id with non-root parent span" do
      trace_id = "1ee"
      span_id = "2ff"
      parent_span_id = "0dd"

      headers = encode({trace_id, span_id, parent_span_id, false, true})

      assert {"x-b3-traceid", "1ee"} in headers
      assert {"x-b3-spanid", "2ff"} in headers
      assert {"x-b3-parentspanid", "0dd"} in headers
      assert {"x-b3-sampled", "0"} in headers
      assert {"x-b3-flags", "1"} in headers
    end

    test "encode :ignore" do
      headers = encode(:ignore)

      assert headers == []
    end
  end
end
