defmodule Gateway.Metrics do
  use Task, restart: :transient

  def start_link(_opts) do
    Task.start_link(fn ->
      Gateway.Metrics.Collector.start()
      exit(:normal)
    end)
  end
end
