defmodule Gateway.Router.V1 do
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

  get "/groups" do
    list =
      GenRegistry.reduce(Gateway.Group, [], fn
        {_id, pid}, list ->
          state = GenServer.call(pid, {:get_state})

          if state.visibility == "public" do
            [
              %{
                group_id: state.group_id,
                name: state.name,
                visibility: state.visibility,
                state: state.state,
                member_count: length(state.members)
              }
              | list
            ]
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

        Util.respond(
          conn,
          {:ok,
           %{
             group_id: group_state.group_id,
             name: group_state.name,
             visibility: group_state.visibility,
             state: group_state.state,
             member_count: length(group_state.members)
           }}
        )

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
