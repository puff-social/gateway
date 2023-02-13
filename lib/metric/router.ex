defmodule Gateway.Metrics.Router do
  use Plug.Router

  plug(Gateway.Metrics.Exporter)

  plug(:match)
  plug(:dispatch)

  match _ do
    send_resp(conn, 404, "Metrics available at /metrics")
  end
end
