defmodule PrefixFilterTest do

  use ExUnit.Case
  use Plug.Test

  alias Tapper.Plug.PrefixFilter

  test "empty config is a no-op" do
    c = PrefixFilter.init([])

    assert c == []

    conn = conn(:get, "/test")
    assert conn == PrefixFilter.call(conn, c)
  end

  test "bad config" do
    assert_raise ArgumentError, fn -> PrefixFilter.init(prefixes: "/a/b/c") end
    assert_raise ArgumentError, fn -> PrefixFilter.init(prefixes: [1]) end
end

  test "string config" do
    assert PrefixFilter.init(prefixes: ["/a/b/c"]) == [["a","b","c"]]
    assert PrefixFilter.init(prefixes: ["/a/b/c", "d"]) == [["a","b","c"],["d"]]
    assert PrefixFilter.init(prefixes: ["/"]) == [[]]
  end

  test "split paths config" do
    assert PrefixFilter.init(prefixes: [["a"]]) == [["a"]]
    assert PrefixFilter.init(prefixes: [["a"], ["b",["c"]]]) == [["a"], ["b",["c"]]]
    assert PrefixFilter.init(prefixes: [[]]) == [[]]
  end

  test "no match is identity" do
    config = PrefixFilter.init(prefixes: ["/a/b","c"])
    conn = conn(:get, "/d")
    assert PrefixFilter.call(conn, config) == conn
  end

  test "match sets ignore flag" do
    config = PrefixFilter.init(prefixes: ["/a/b","c"])
    conn = conn(:get, "/c")
    assert %Plug.Conn{private: %{tapper_plug: :ignore}} = PrefixFilter.call(conn, config)
  end

end