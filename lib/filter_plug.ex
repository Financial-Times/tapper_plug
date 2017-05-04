defmodule Tapper.Plug.Filter do
  @moduledoc """
  Tapper filter plug, to prevent tracing of certain URLs.

  ```
  plug Tapper.Plug.Filter, prefixes: ["__gtg", "/a/path, ["b","path"]]
  ```

    * `prefixes` - a list of matching path prefixes, given either as path strings, or as a list of path segment strings.

  Uses `Tapper.Plug.store/2` to set state to `:ignore`.
  """

  @behaviour Plug

  def init(opts) do
    case Keyword.get(opts, :prefixes, []) do
      prefixes when is_list(prefixes) -> Enum.map(prefixes, &split/1)
      _ -> raise ArgumentError, "prefixes must be list of paths or path components"
    end
  end

  @doc false
  def split(prefix) when is_list(prefix), do: prefix
  def split(prefix) when is_binary(prefix) do
    String.split(prefix, "/", trim: true)
  end
  def split(_prefix), do: raise ArgumentError, ~S(prefixes must be a path "/a/b" or list of path components ["a","b"])

  def call(conn, []), do: conn
  def call(conn, prefixes) do
    case is_prefix?(prefixes, conn.path_info) do
      true -> Tapper.Plug.store(conn, :ignore)
      false -> conn
    end
  end

  @doc false
  def is_prefix?(prefixes, path_info) do
    Enum.any?(prefixes, fn(prefix) -> :lists.prefix(prefix, path_info) end)
  end

end
