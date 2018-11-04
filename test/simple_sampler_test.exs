defmodule SimpleSamplerTest do
  use ExUnit.Case

  use Plug.Test

  test "samples default (10%) percentage" do
    conn = conn(:get, "/test")

    num_sampled =
      Enum.reduce(1..1000, 0, fn _, acc ->
        if(Tapper.Plug.Sampler.Simple.sample?(conn, other: 1), do: acc + 1, else: acc)
      end)

    # 5%
    assert num_sampled > 50
    # 20%
    assert num_sampled < 200
  end

  test "samples 100% percentage" do
    conn = conn(:get, "/test")

    sampled =
      Enum.all?(1..1000, fn _ -> Tapper.Plug.Sampler.Simple.sample?(conn, percent: 100) end)

    assert sampled == true
  end

  test "samples 0% percentage" do
    conn = conn(:get, "/test")

    sampled = Enum.any?(1..1000, fn _ -> Tapper.Plug.Sampler.Simple.sample?(conn, percent: 0) end)

    assert sampled == false
  end
end
