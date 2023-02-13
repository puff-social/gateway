defmodule Gateway.Connectivity.RedisUtils do
  def normalize(l) do
    l
    |> Enum.chunk_every(2)
    |> Map.new(fn [k, v] -> {k, v} end)
  end

  def map_to_list(map) when is_map(map) do
    map |> Enum.reduce([], fn {k, v}, acc -> [k, v | acc] end)
  end
end
