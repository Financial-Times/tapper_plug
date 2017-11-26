defmodule TapperPlugTest do
  use ExUnit.Case
  use Plug.Test

  doctest Tapper.Plug

  setup do
    Application.ensure_all_started(:tapper)

    :ok
  end

  describe "config" do
    test "config sets defaults, and contains custom keys" do
      config = Tapper.Plug.Trace.init(top: :bottom)
      assert config[:sampler] == Tapper.Plug.Sampler.Simple
      assert config[:debug] == false
      assert config[:tapper] == []
      assert config[:top] == :bottom
    end

    test "config sets sampler and tapper opts, and contains custom keys" do
      config = Tapper.Plug.Trace.init(debug: true, sampler: Some.Module, tapper: [something: true], path_redactor: {Mod, :fun, [1]}, left: :right)
      assert config[:sampler] == Some.Module
      assert config[:debug] == true
      assert config[:tapper] == [something: true]
      assert config[:path_redactor] == {Mod, :fun, [1]}
      assert config[:left] == :right
    end

    test "debug can be set via Application config" do
      Application.put_env(:tapper_plug, :debug, true)
      config = Tapper.Plug.Trace.init([])
      assert config[:debug] == true
      Application.put_env(:tapper_plug, :debug, false)
    end
  end

  describe "sampling" do
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

      assert Tapper.Id.sampled?(id)
    end

    test "id is not sampled when no propagated trace, if sampler returns false" do
      config = Tapper.Plug.Trace.init(sampler: fn(_,_) -> false end)

      conn = conn(:get, "/test")

      new_conn = Tapper.Plug.Trace.call(conn, config)

      id = new_conn.private[:tapper_plug]

      refute Tapper.Id.sampled?(id)
    end

    test "id remains :ignore if ignoring" do
      config = Tapper.Plug.Trace.init(sampler: fn(_,_) -> true end)

      conn = conn(:get, "/test")
      |> Tapper.Plug.store(:ignore)

      new_conn = Tapper.Plug.Trace.call(conn, config)

      id = new_conn.private[:tapper_plug]

      assert id == :ignore
    end

  end

  describe "header parsing" do

    test "decodes headers into %Tapper.Id{}" do
      # see also tests in header_propagation_test.exs

      config = Tapper.Plug.Trace.init([])

      conn = conn(:get, "/test")
      |> put_req_header("x-b3-traceid", "1fffffff")
      |> put_req_header("x-b3-parentspanid", "2ffffffff")
      |> put_req_header("x-b3-spanid", "ffff")
      |> put_req_header("x-b3-sampled", "1")

      new_conn = Tapper.Plug.Trace.call(conn, config)

      id = new_conn.private[:tapper_plug]

      {trace_id_hex, span_id_hex, parent_id_hex, sampled_flag, debug_flag} = Tapper.Id.destructure(id)

      assert String.to_integer(trace_id_hex, 16) === 0x1fffffff
      assert String.to_integer(span_id_hex, 16) === 0xffff
      assert String.to_integer(parent_id_hex, 16) === 0x2ffffffff
      assert sampled_flag == true
      assert debug_flag == false
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

      assert Tapper.Id.sampled?(id)

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

      refute Tapper.Id.sampled?(id)

      refute_received :sample
    end

  end

  describe "finishing trace" do
    test "sets expected annotations on joined trace" do
      pid = self()
      config = Tapper.Plug.Trace.init(tapper: [reporter: fn(spans) -> send(pid, {:spans, spans}) end])

      conn = conn(:get, "http://test-host/test")
      |> put_req_header("x-b3-traceid", "1fffffff")
      |> put_req_header("x-b3-parentspanid", "2ffffffff")
      |> put_req_header("x-b3-spanid", "ffff")
      |> put_req_header("x-b3-sampled", "1")
      |> put_req_header("user-agent", "the-ua")

      conn = Tapper.Plug.Trace.call(conn, config)

      id = conn.private[:tapper_plug]

      assert Tapper.Id.sampled?(id)

      assert length(conn.before_send) == 1

      conn = Plug.Conn.resp(conn, 200, "Body")
      run_before_send(conn, :set) # Plug.Test doesn't support before_send (yet)
      _conn = Plug.Conn.send_resp(conn)

      assert_receive {:spans, spans}

      span = hd(spans)

      assert span.name == "unknown" # doesn't set name on joined span

      assert has_annotation?(span, :sr)
      assert has_annotation?(span, :ss)

      assert has_binary_annotation?(span, :ca, true)
      assert has_binary_annotation?(span, "http.path", "/test")
      assert has_binary_annotation?(span, "http.method", "GET")
      assert has_binary_annotation?(span, "http.host", "test-host")

      assert has_binary_annotation?(span, "http.status_code", 200)
    end

    test "sets expected annotations on started trace" do
      pid = self()
      config = Tapper.Plug.Trace.init(sampler: fn _,_ -> true end, tapper: [reporter: fn(spans) -> send(pid, {:spans, spans}) end])

      conn = conn(:get, "http://test-host/test")

      conn = Tapper.Plug.Trace.call(conn, config)

      id = conn.private[:tapper_plug]

      assert Tapper.Id.sampled?(id)

      assert length(conn.before_send) == 1

      conn = Plug.Conn.resp(conn, 200, "Body")
      run_before_send(conn, :set) # Plug.Test doesn't support before_send (yet)
      _conn = Plug.Conn.send_resp(conn)

      assert_receive {:spans, spans}

      span = hd(spans)

      assert span.name == "GET " <> conn.request_path

      assert has_annotation?(span, :sr)
      assert has_annotation?(span, :ss)

      assert has_binary_annotation?(span, :ca, true)
      assert has_binary_annotation?(span, "http.path", conn.request_path)
      assert has_binary_annotation?(span, "http.method", "GET")
      assert has_binary_annotation?(span, "http.host", "test-host")

      assert has_binary_annotation?(span, "http.status_code", 200)
    end
  end

  describe "redaction" do

    defmodule Redactor do
      def redact(s, :x), do: "****"
    end

    test "redacts path in started trace name and annotation" do
      pid = self()
      config = Tapper.Plug.Trace.init(path_redactor: {Redactor, :redact, [:x]}, tapper: [reporter: fn(spans) -> send(pid, {:spans, spans}) end], sampler: fn _,_ -> true end)

      conn = conn(:get, "http://test-host/test")

      conn = Tapper.Plug.Trace.call(conn, config)

      conn = Plug.Conn.resp(conn, 200, "Body")
      run_before_send(conn, :set) # Plug.Test doesn't support before_send (yet)
      _conn = Plug.Conn.send_resp(conn)

      assert_receive {:spans, spans}

      span = hd(spans)

      assert span.name == "GET ****"
      assert has_binary_annotation?(hd(spans), "http.path", "****")
    end

    test "redacts path in joined trace annotation" do
      pid = self()
      config = Tapper.Plug.Trace.init(path_redactor: {Redactor, :redact, [:x]}, tapper: [reporter: fn(spans) -> send(pid, {:spans, spans}) end])

      conn = conn(:get, "http://test-host/test")
      |> put_req_header("x-b3-traceid", "1fffffff")
      |> put_req_header("x-b3-parentspanid", "2ffffffff")
      |> put_req_header("x-b3-spanid", "ffff")
      |> put_req_header("x-b3-sampled", "1")

      conn = Tapper.Plug.Trace.call(conn, config)

      conn = Plug.Conn.resp(conn, 200, "Body")
      run_before_send(conn, :set) # Plug.Test doesn't support before_send (yet)
      _conn = Plug.Conn.send_resp(conn)

      assert_receive {:spans, spans}

      span = hd(spans)

      assert span.name == "unknown"
      assert has_binary_annotation?(hd(spans), "http.path", "****")
    end

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
