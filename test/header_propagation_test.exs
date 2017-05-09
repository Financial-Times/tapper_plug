defmodule HeaderPropagationTest do
  use ExUnit.Case

  import Tapper.Plug.HeaderPropagation

  describe "decode/1" do
    test "join a span with parent span id" do
      {:join, {trace_id, _uniq}, span_id, parent_span_id, _sample, _debug} =
        decode([{"x-b3-traceid","123"},{"x-b3-spanid","abc"},{"x-b3-parentspanid","ffe"}])

      assert trace_id == String.to_integer("123", 16)
      assert span_id == String.to_integer("abc", 16)
      assert parent_span_id == String.to_integer("ffe", 16)
    end

    test "join a span, no parent span id" do
      {:join, {trace_id, _uniq}, span_id, parent_span_id, _sample, _debug} =
        decode([{"x-b3-traceid","123"},{"x-b3-spanid","abc"}])

      assert trace_id == String.to_integer("123", 16)
      assert span_id == String.to_integer("abc", 16)
      assert parent_span_id == :root
    end

    test "join a span, sampled" do
      {:join, {trace_id, _uniq}, span_id, parent_span_id, sample, debug} =
        decode([{"x-b3-traceid","123"},{"x-b3-spanid","abc"},{"x-b3-parentspanid","ffe"},{"x-b3-sampled", "1"}])

      assert trace_id == String.to_integer("123", 16)
      assert span_id == String.to_integer("abc", 16)
      assert parent_span_id == String.to_integer("ffe", 16)

      assert sample == true
      assert debug == false
    end

    test "join a span, not sampled" do
      {:join, {trace_id, _uniq}, span_id, parent_span_id, sample, debug} =
        decode([{"x-b3-traceid","123"},{"x-b3-spanid","abc"},{"x-b3-parentspanid","ffe"},{"x-b3-sampled", "0"}])

      assert trace_id == String.to_integer("123", 16)
      assert span_id == String.to_integer("abc", 16)
      assert parent_span_id == String.to_integer("ffe", 16)

      assert sample == false
      assert debug == false
    end

    test "join a span, no sample, debug flag on" do
      {:join, {trace_id, _uniq}, span_id, parent_span_id, sample, debug} =
        decode([{"x-b3-traceid","123"},{"x-b3-spanid","abc"},{"x-b3-parentspanid","ffe"},{"x-b3-flags", "1"}])

      assert trace_id == String.to_integer("123", 16)
      assert span_id == String.to_integer("abc", 16)
      assert parent_span_id == String.to_integer("ffe", 16)

      assert sample == :absent
      assert debug == true
    end

    test "start a span: no b3 headers" do
      :start =
        decode([])
    end

    test "start a span: partial b3 headers" do
      :start =
        decode([{"x-b3-traceid","123"},{"x-b3-parentspanid","abc"}])
    end

    test "start a span: bad b3 headers" do
      :start =
        decode([{"x-b3-traceid","123"},{"x-b3-spanid","abc"},{"x-b3-parentspanid","xffe"}])
      :start =
        decode([{"x-b3-traceid","123x"},{"x-b3-spanid","abc"},{"x-b3-parentspanid","ffe"}])
      :start =
        decode([{"x-b3-traceid",""},{"x-b3-spanid","abc"},{"x-b3-parentspanid","ffe"}])
    end

    test "bad sample flag is false" do
      {:join, {trace_id, _uniq}, span_id, parent_span_id, sample, debug} =
        decode([{"x-b3-traceid","123"},{"x-b3-spanid","abc"},{"x-b3-parentspanid","ffe"},{"x-b3-sampled", "x"}])

      assert trace_id == String.to_integer("123", 16)
      assert span_id == String.to_integer("abc", 16)
      assert parent_span_id == String.to_integer("ffe", 16)

      assert sample == false
      assert debug == false
    end

    test "bad flags is debug false" do
      {:join, {trace_id, _uniq}, span_id, parent_span_id, sample, debug} =
        decode([{"x-b3-traceid","123"},{"x-b3-spanid","abc"},{"x-b3-parentspanid","ffe"},{"x-b3-sampled", "1"}, {"x-b3-flags", "4"}])

      assert trace_id == String.to_integer("123", 16)
      assert span_id == String.to_integer("abc", 16)
      assert parent_span_id == String.to_integer("ffe", 16)

      assert sample == true
      assert debug == false
    end

  end

  describe "encode/1" do

    test "encode id with root parent span" do
      trace_id = "1ee"
      span_id = "2ff"
      parent_span_id = ""

      headers = encode({trace_id, span_id, parent_span_id, true, false})

      assert {"x-b3-traceid","1ee"} in headers
      assert {"x-b3-spanid","2ff"} in headers
      assert {"x-b3-sampled","1"} in headers
      assert {"x-b3-flags","0"} in headers
      assert not :lists.keymember("x-b3-parentspanid", 1, headers)
    end

    test "encode id with non-root parent span" do
      trace_id = "1ee"
      span_id = "2ff"
      parent_span_id = "0dd"

      headers = encode({trace_id, span_id, parent_span_id, false, true})

      assert {"x-b3-traceid","1ee"} in headers
      assert {"x-b3-spanid","2ff"} in headers
      assert {"x-b3-parentspanid","0dd"} in headers
      assert {"x-b3-sampled","0"} in headers
      assert {"x-b3-flags","1"} in headers
    end

  end

end