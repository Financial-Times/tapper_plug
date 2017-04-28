defmodule TapperPlugTest do
  use ExUnit.Case
  use Plug.Test

  doctest Tapper.Plug

  setup do
    Application.ensure_all_started(:tapper)

    :ok
  end

  test "id is sampled when no propagated trace, if sampler returns true" do
    config = Tapper.Plug.Start.init(sampler: fn(_,_) -> true end)

    conn = conn(:get, "/test")

    new_conn = Tapper.Plug.Start.call(conn, config)

    id = new_conn.private[:tapper_plug]

    assert match?(%Tapper.Id{sampled: true}, id)
  end

  test "id is not sampled when no propagated trace, if sampler returns false" do
    config = Tapper.Plug.Start.init(sampler: fn(_,_) -> false end)

    conn = conn(:get, "/test")

    new_conn = Tapper.Plug.Start.call(conn, config)

    id = new_conn.private[:tapper_plug]

    assert match?(%Tapper.Id{sampled: false}, id)
  end

  test "id remains :ignore if ignoring" do
    config = Tapper.Plug.Start.init(sampler: fn(_,_) -> true end)

    conn = conn(:get, "/test")
    |> Tapper.Plug.store(:ignore)

    new_conn = Tapper.Plug.Start.call(conn, config)

    id = new_conn.private[:tapper_plug]

    assert id == :ignore
  end

  test "id is sampled when propagated trace is sampled" do
    config = Tapper.Plug.Start.init(sampler: fn(_,_) -> false end)

    conn = conn(:get, "/test")
    |> put_req_header("x-b3-traceid", "1fffffff")
    |> put_req_header("x-b3-parentspanid", "2ffffffff")
    |> put_req_header("x-b3-spanid", "ffff")
    |> put_req_header("x-b3-sampled", "1")

    new_conn = Tapper.Plug.Start.call(conn, config)

    id = new_conn.private[:tapper_plug]

    assert match?(%Tapper.Id{trace_id: {0x1fffffff, _}, span_id: 0xffff, parent_ids: [], sampled: true}, id)
  end

  test "id is not sampled when propagated trace is not sampled" do
    config = Tapper.Plug.Start.init(sampler: fn(_) -> false end)

    conn = conn(:get, "/test")
    |> put_req_header("x-b3-traceid", "1fffffff")
    |> put_req_header("x-b3-parentspanid", "2ffffffff")
    |> put_req_header("x-b3-spanid", "ffff")
    |> put_req_header("x-b3-sampled", "0")

    new_conn = Tapper.Plug.Start.call(conn, config)

    id = new_conn.private[:tapper_plug]

    assert match?(%Tapper.Id{trace_id: {0x1fffffff, _}, span_id: 0xffff, parent_ids: [], sampled: false}, id)
  end
end
