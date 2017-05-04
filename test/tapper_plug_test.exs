defmodule TapperPlugTest do
  use ExUnit.Case
  use Plug.Test

  doctest Tapper.Plug

  setup do
    Application.ensure_all_started(:tapper)

    :ok
  end

  test "config sets defaults, and contains custom keys" do
    config = Tapper.Plug.Trace.init(top: :bottom)
    assert config[:sampler] == Tapper.Plug.Sampler.Simple
    assert config[:tapper] == []
    assert config[:top] == :bottom
  end

  test "config sets sampler and tapper opts, and contains custom keys" do
    config = Tapper.Plug.Trace.init(sampler: Some.Module, tapper: [something: true], left: :right)
    assert config[:sampler] == Some.Module
    assert config[:left] == :right
    assert config[:tapper] == [something: true]
  end

  test "sampler is called with conn and config" do
    pid = self()
    config = Tapper.Plug.Trace.init(sampler: fn(conn, config) ->
      send(pid, {:sample, conn, config})
      true
    end, left: :right)

    assert is_function(config[:sampler],2)
    assert config[:left] == :right

    conn = conn(:get, "/test")

    _new_conn = Tapper.Plug.Trace.call(conn, config)

    assert_received {:sample, ^conn, ^config}
  end

  test "id is sampled when no propagated trace, if sampler returns true" do
    config = Tapper.Plug.Trace.init(sampler: fn(_,_) -> true end)

    conn = conn(:get, "/test")

    new_conn = Tapper.Plug.Trace.call(conn, config)

    id = new_conn.private[:tapper_plug]

    assert match?(%Tapper.Id{sampled: true}, id)
  end

  test "id is not sampled when no propagated trace, if sampler returns false" do
    config = Tapper.Plug.Trace.init(sampler: fn(_,_) -> false end)

    conn = conn(:get, "/test")

    new_conn = Tapper.Plug.Trace.call(conn, config)

    id = new_conn.private[:tapper_plug]

    assert match?(%Tapper.Id{sampled: false}, id)
  end

  test "id remains :ignore if ignoring" do
    config = Tapper.Plug.Trace.init(sampler: fn(_,_) -> true end)

    conn = conn(:get, "/test")
    |> Tapper.Plug.store(:ignore)

    new_conn = Tapper.Plug.Trace.call(conn, config)

    id = new_conn.private[:tapper_plug]

    assert id == :ignore
  end

  test "id is sampled when propagated trace is sampled" do
    pid = self()
    config = Tapper.Plug.Trace.init(sampler: fn(_,_) ->
      send(pid, :sample)
      false
    end)

    conn = conn(:get, "/test")
    |> put_req_header("x-b3-traceid", "1fffffff")
    |> put_req_header("x-b3-parentspanid", "2ffffffff")
    |> put_req_header("x-b3-spanid", "ffff")
    |> put_req_header("x-b3-sampled", "1")

    new_conn = Tapper.Plug.Trace.call(conn, config)

    id = new_conn.private[:tapper_plug]

    assert match?(%Tapper.Id{trace_id: {0x1fffffff, _}, span_id: 0xffff, origin_parent_id: 0x2ffffffff, parent_ids: [], sampled: true}, id)

    refute_received :sample
  end

  test "id is not sampled when propagated trace is not sampled" do
    pid = self()
    config = Tapper.Plug.Trace.init(sampler: fn(_,_) ->
      send(pid, :sample)
      false
    end)

    conn = conn(:get, "/test")
    |> put_req_header("x-b3-traceid", "1fffffff")
    |> put_req_header("x-b3-parentspanid", "2ffffffff")
    |> put_req_header("x-b3-spanid", "ffff")
    |> put_req_header("x-b3-sampled", "0")

    new_conn = Tapper.Plug.Trace.call(conn, config)

    id = new_conn.private[:tapper_plug]

    assert match?(%Tapper.Id{trace_id: {0x1fffffff, _}, span_id: 0xffff, origin_parent_id: 0x2ffffffff, parent_ids: [], sampled: false}, id)

    refute_received :sample
  end

  test "finishing trace" do
    pid = self()
    config = Tapper.Plug.Trace.init(tapper: [reporter: fn(spans) -> send(pid, {:spans, spans}) end])

    conn = conn(:get, "http://test-host/test")
    |> put_req_header("x-b3-traceid", "1fffffff")
    |> put_req_header("x-b3-parentspanid", "2ffffffff")
    |> put_req_header("x-b3-spanid", "ffff")
    |> put_req_header("x-b3-sampled", "1")

    conn = Tapper.Plug.Trace.call(conn, config)

    id = conn.private[:tapper_plug]

    assert match?(%Tapper.Id{trace_id: {0x1fffffff, _}, span_id: 0xffff, origin_parent_id: 0x2ffffffff, parent_ids: [], sampled: true}, id)

    assert length(conn.before_send) == 1

    conn = Plug.Conn.resp(conn, 200, "Body")
    run_before_send(conn, :set) # Plug.Test doesn't support before_send (yet)
    _conn = Plug.Conn.send_resp(conn)

    assert_receive {:spans, spans}

    assert has_annotation?(hd(spans), :sr)
    assert has_annotation?(hd(spans), :ss)

    assert has_binary_annotation?(hd(spans), "http.path", "/test")
    assert has_binary_annotation?(hd(spans), "http.method", "GET")
    assert has_binary_annotation?(hd(spans), "http.host", "test-host")

    assert has_binary_annotation?(hd(spans), "http.status_code", 200)
  end

  defp run_before_send(%Plug.Conn{before_send: before_send} = conn, new) do
    conn = Enum.reduce before_send, %{conn | state: new}, &(&1.(&2))
    if conn.state != new do
      raise ArgumentError, "cannot send/change response from run_before_send callback"
    end
    %{conn | resp_headers: conn.resp_cookies}
  end

  defp has_annotation?(%Tapper.Protocol.Span{annotations: annotations}, type) do
    Enum.any?(annotations, fn(an) -> an.value == type end)
  end

  defp has_binary_annotation?(%Tapper.Protocol.Span{binary_annotations: annotations}, key, value) do
    Enum.any?(annotations, fn(an) -> an.key == key and an.value == value end)
  end


end
