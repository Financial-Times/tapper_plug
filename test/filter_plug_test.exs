defmodule PrefixFilterTest do
  use ExUnit.Case
  use Plug.Test

  alias Tapper.Plug.Filter

  test "empty config is a no-op" do
    c = Filter.init([])

    assert c == []

    conn = conn(:get, "/test")
    assert conn == Filter.call(conn, c)
  end

  test "bad config" do
    assert_raise ArgumentError, fn -> Filter.init(prefixes: "/a/b/c") end
    assert_raise ArgumentError, fn -> Filter.init(prefixes: [1]) end
  end

  test "string config" do
    assert Filter.init(prefixes: ["/a/b/c"]) == [["a", "b", "c"]]
    assert Filter.init(prefixes: ["/a/b/c", "d"]) == [["a", "b", "c"], ["d"]]
    assert Filter.init(prefixes: ["/"]) == [[]]
  end

  test "split paths config" do
    assert Filter.init(prefixes: [["a"]]) == [["a"]]
    assert Filter.init(prefixes: [["a"], ["b", ["c"]]]) == [["a"], ["b", ["c"]]]
    assert Filter.init(prefixes: [[]]) == [[]]
  end

  test "no match is identity" do
    config = Filter.init(prefixes: ["/a/b", "c"])
    conn = conn(:get, "/d")
    assert Filter.call(conn, config) == conn
  end

  test "match sets ignore flag" do
    config = Filter.init(prefixes: ["/a/b", "c"])
    conn = conn(:get, "/c")
    assert %Plug.Conn{private: %{tapper_plug: :ignore}} = Filter.call(conn, config)
  end
end
