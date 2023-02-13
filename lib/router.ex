defmodule Gateway.Router do
  alias Gateway.Router.Util

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  match "/health" do
    send_resp(conn, 200, "OK")
  end

  patch "/status" do
    key = conn |> Plug.Conn.get_req_header("authorization")

    {:ok, body, conn} = Plug.Conn.read_body(conn, length: 1_000_000)

    {:ok, key} = Redix.command(:redix, ["GET", "gw/token:#{key}"])

    case key do
      nil ->
        Util.no_permission(conn)

      _ ->
        case Jason.decode(body) do
          {:ok, json} when is_map(json) ->
            Redix.command(
              :redix,
              Enum.concat(
                ["HSET", "status/current"],
                Gateway.Connectivity.RedisUtils.map_to_list(json)
              )
            )

            {_max_id, _max_pid} =
              GenRegistry.reduce(Gateway.Session, {nil, -1}, fn
                {_id, pid}, {_, _current} = _acc ->
                  send(pid, {:send_status, json})
              end)

            :ok

          _ ->
            :ok
        end

        Util.respond(conn, {:ok})
    end
  end

  match _ do
    Util.not_found(conn)
  end
end
