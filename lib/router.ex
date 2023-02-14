defmodule Gateway.Router do
  alias Gateway.Router.Util

  use Plug.Router

  plug(Corsica,
    origins: "*",
    max_age: 600,
    allow_methods: :all,
    allow_headers: :all
  )

  plug(:match)
  plug(:dispatch)

  match "/health" do
    send_resp(conn, 200, "OK")
  end

  forward("/v1", to: Gateway.Router.V1)

  options _ do
    conn
    |> send_resp(204, "")
  end

  match _ do
    Util.not_found(conn)
  end
end
