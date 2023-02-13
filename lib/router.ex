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

  get "/groups" do
    list =
      GenRegistry.reduce(Gateway.Group, [], fn
        {_id, pid}, list ->
          state = GenServer.call(pid, {:get_state})

          if state.visibility == "public" do
            [state | list]
          else
            list
          end
      end)

    Util.respond(conn, {:ok, list})
  end

  get "/groups/:id" do
    case GenRegistry.lookup(Gateway.Group, id) do
      {:ok, pid} ->
        group_state = GenServer.call(pid, {:get_state})

        Util.respond(conn, {:ok, group_state})

      {:error, :not_found} ->
        Util.respond(conn, {:error, 404, :group_not_found, "Invalid group id provided"})
    end
  end

  options _ do
    conn
    |> send_resp(204, "")
  end

  match _ do
    Util.not_found(conn)
  end
end
