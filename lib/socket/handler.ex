defmodule Gateway.Socket.Handler do
  @behaviour :cowboy_websocket

  alias Gateway.Group.Generator

  @type t :: %{
          session_id: nil,
          linked_session: pid,
          encoding: nil,
          compression: nil
        }

  defstruct session_id: nil,
            linked_session: nil,
            encoding: nil,
            compression: nil

  def init(request, _state) do
    compression =
      request
      |> :cowboy_req.parse_qs()
      |> Enum.find(fn {name, _value} -> name == "compression" end)
      |> case do
        {_name, "zlib"} -> :zlib
        _ -> :none
      end

    encoding =
      request
      |> :cowboy_req.parse_qs()
      |> Enum.find(fn {name, _value} -> name == "encoding" end)
      |> case do
        {_name, "etf"} -> :etf
        _ -> :json
      end

    session_id = UUID.uuid4()

    {:ok, session} =
      GenRegistry.lookup_or_start(Gateway.Session, session_id, [%{session_id: session_id}])

    Gateway.Metrics.Collector.inc(:gauge, :puffers_connected_sessions)

    state = %__MODULE__{
      linked_session: session,
      session_id: session_id,
      compression: compression,
      encoding: encoding
    }

    {:cowboy_websocket, request, state, %{idle_timeout: 5_000}}
  end

  def websocket_init(state) do
    GenServer.cast(state.linked_session, {:link_socket, self()})

    {:ok, state}
  end

  def websocket_handle({:binary, message}, state) do
    {:ok, data} = inflate_msg(message)
    message = Jason.decode!(data)
    handle_message(message, state)

    {:ok, state}
  end

  def websocket_handle({:text, message}, state) do
    case Jason.decode(message) do
      {:ok, json} when is_map(json) ->
        handle_message(json, state)
        {:ok, state}

      _ ->
        {:ok, state}
    end
  end

  def websocket_info({:set_new_session, session_pid, session_id}, state) do
    {:ok,
     %{
       state
       | linked_session: session_pid,
         session_id: session_id
     }}
  end

  def websocket_info({:send_event, event, data}, state) do
    send(
      self(),
      {:remote_send,
       construct_msg(state.encoding, state.compression, %{
         op: 3,
         t: Atom.to_string(event),
         d: data
       })}
    )

    {:ok, state}
  end

  def websocket_info({:send_event, event}, state) do
    send(
      self(),
      {:remote_send,
       construct_msg(state.encoding, state.compression, %{
         op: 3,
         t: Atom.to_string(event)
       })}
    )

    {:ok, state}
  end

  def websocket_info({:send_op, op, data}, state) do
    send(
      self(),
      {:remote_send, construct_msg(state.encoding, state.compression, %{op: op, d: data})}
    )

    {:ok, state}
  end

  def websocket_info({:send_op, op}, state) do
    send(self(), {:remote_send, construct_msg(state.encoding, state.compression, %{op: op})})

    {:ok, state}
  end

  def websocket_info({:remote_send, data}, state) do
    Gateway.Metrics.Collector.inc(:counter, :puffers_messages_outbound)
    {:reply, data, state}
  end

  def websocket_info({:remote_close, code, reason}, state) do
    {:reply, {:close, code, reason}, state}
  end

  def websocket_info({:send_to_linked_session, message}, state) do
    send(state.linked_session, message)
    {:ok, state}
  end

  def websocket_info(info, state) do
    {:reply, {:text, info}, state}
  end

  def websocket_info(message, req, state) do
    {:reply, {:text, message}, req, state}
  end

  def terminate(_reason, _req, state) do
    GenServer.cast(state.linked_session, {:socket_closed})
    Process.send_after(state.linked_session, {:close_session_if_socket_dead}, 7_000)
    Gateway.Metrics.Collector.dec(:gauge, :puffers_connected_sessions)
    :ok
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  defp handle_message(data, state) do
    Gateway.Metrics.Collector.inc(:counter, :puffers_messages_inbound)

    case data["op"] do
      # Join group
      1 ->
        if data["d"] != nil and is_map(data["d"]) and data["d"]["group_id"] != nil do
          GenServer.cast(state.linked_session, {:join_group, data["d"]["group_id"]})
        else
          send(
            self(),
            {:send_event, :SYNTAX_ERROR, %{code: "MISSING_DATA_OR_GROUP_ID"}}
          )
        end

      # Create group
      2 ->
        group_id = Generator.generateId()

        group_name =
          case data["d"]["name"] do
            nil ->
              Generator.generateName()

            _ ->
              if String.trim(data["d"]["name"]) == "" or
                   String.normalize(data["d"]["name"], :nfc) !=
                     String.normalize(data["d"]["name"], :nfd) do
                Generator.generateName()
              else
                data["d"]["name"]
              end
          end

        group_visibility = data["d"]["visibility"] || "private"

        GenServer.cast(
          state.linked_session,
          {:create_group, group_id, group_name, group_visibility}
        )

      # Send device state
      4 ->
        if data["d"] != nil and is_map(data["d"]) do
          GenServer.cast(state.linked_session, {:update_device_state, data["d"]})
        else
          send(
            self(),
            {:send_event, :SYNTAX_ERROR, %{code: "MISSING_DATA"}}
          )
        end

      # Edit group
      5 ->
        if data["d"] != nil and is_map(data["d"]) do
          case Hammer.check_rate("group_edit:#{state.session_id}", 10_000, 10) do
            {:allow, _count} ->
              GenServer.cast(state.linked_session, {:edit_current_group, data["d"]})

            {:deny, _limit} ->
              send(
                self(),
                {:send_event, :RATE_LIMITED}
              )
          end
        else
          send(
            self(),
            {:send_event, :SYNTAX_ERROR, %{code: "MISSING_DATA"}}
          )
        end

      # Update user
      6 ->
        if data["d"] != nil and is_map(data["d"]) do
          if data["d"]["name"] != nil and String.length(data["d"]["name"]) > 32 do
            send(
              self(),
              {:send_event, :USER_UPDATE_ERROR, %{code: "INVALID_NAME"}}
            )

            :ok
          else
            case Hammer.check_rate("user_update:#{state.session_id}", 30_000, 5) do
              {:allow, _count} ->
                GenServer.cast(state.linked_session, {:update_session_state, data["d"]})

              {:deny, _limit} ->
                send(
                  self(),
                  {:send_event, :RATE_LIMITED}
                )
            end
          end
        else
          send(
            self(),
            {:send_event, :SYNTAX_ERROR, %{code: "MISSING_DATA"}}
          )
        end

      # Leave group
      7 ->
        GenServer.cast(state.linked_session, {:leave_group})

      # Inquire heating
      8 ->
        GenServer.cast(state.linked_session, {:inquire_group_heat})

      # Start with ready
      9 ->
        GenServer.cast(state.linked_session, {:start_with_ready})

      # Disconnect device
      10 ->
        GenServer.cast(state.linked_session, {:disconnect_device})

      # Send message to group
      11 ->
        if data["d"] != nil and is_map(data["d"]) do
          if data["d"]["content"] == nil or
               String.trim(data["d"]["content"]) == "" or
               String.normalize(data["d"]["content"], :nfc) !=
                 String.normalize(data["d"]["content"], :nfd) or
               String.length(data["d"]["content"]) > 1024 do
            send(
              self(),
              {:send_event, :MESSAGE_ERROR, %{code: "INVALID_CONTENT"}}
            )

            :ok
          else
            case Hammer.check_rate("send_message:#{state.session_id}", 10_000, 10) do
              {:allow, _count} ->
                GenServer.cast(state.linked_session, {:send_message_to_group, data["d"]})

              {:deny, _limit} ->
                send(
                  self(),
                  {:send_event, :RATE_LIMITED}
                )
            end
          end
        else
          send(
            self(),
            {:send_event, :SYNTAX_ERROR, %{code: "MISSING_DATA"}}
          )
        end

      # Set group back to chilling (stop sesh)
      12 ->
        GenServer.cast(state.linked_session, {:stop_group_heat})

      # Resume session
      13 ->
        if data["d"] != nil and is_map(data["d"]) do
          case GenRegistry.lookup(Gateway.Session, data["d"]["session_id"]) do
            {:ok, session_pid} ->
              if session_pid != nil do
                session_state = :sys.get_state(session_pid)

                if session_state.session_token == data["d"]["session_token"] do
                  GenServer.cast(session_pid, {:link_socket_without_init, self()})

                  send(
                    self(),
                    {:send_event, :SESSION_RESUMED, %{session_id: session_state.session_id}}
                  )

                  send(self(), {:set_new_session, session_pid, session_state.session_id})
                  GenServer.stop(state.linked_session, :normal)
                else
                  {:reply, {:close, 4001, "INVALID_RESUME_SESSION"}, state}
                end
              else
                {:reply, {:close, 4001, "INVALID_RESUME_SESSION"}, state}
              end

            {:error, :not_found} ->
              {:reply, {:close, 4001, "INVALID_RESUME_SESSION"}, state}
          end
        else
          send(
            self(),
            {:send_event, :SYNTAX_ERROR, %{code: "MISSING_DATA"}}
          )
        end

      # Send Reaction to group
      14 ->
        if data["d"] != nil and is_map(data["d"]) do
          if Enum.member?(
               [
                 "👍",
                 "✌️",
                 "👋",
                 "🤙",
                 "😂",
                 "😮‍💨",
                 "🤬",
                 "🤯",
                 "🫠",
                 "🫡",
                 "💨",
                 "🚬",
                 "🗡️",
                 "🕐",
                 "⏭️",
                 "⏳",
                 "🎙️",
                 "🔥"
               ],
               data["d"]["emoji"]
             ) do
            case Hammer.check_rate("send_reaction:#{state.session_id}", 5_000, 15) do
              {:allow, _count} ->
                GenServer.cast(
                  state.linked_session,
                  {:send_reaction_to_group, data["d"]["emoji"]}
                )

              {:deny, _limit} ->
                send(
                  self(),
                  {:send_event, :RATE_LIMITED}
                )
            end
          else
            send(
              self(),
              {:send_event, :SYNTAX_ERROR, %{code: "MISSING_DATA"}}
            )
          end
        else
          send(
            self(),
            {:send_event, :SYNTAX_ERROR, %{code: "MISSING_DATA"}}
          )
        end

      # Delete group
      15 ->
        GenServer.cast(state.linked_session, {:delete_group})

      # Make another session group owner
      16 ->
        if data["d"] != nil and is_map(data["d"]) do
          if data["d"]["session_id"] == nil do
            send(
              self(),
              {:send_event, :USER_UPDATE_ERROR, %{code: "INVALID_TARGET_SESSION_ID"}}
            )

            :ok
          else
            case Hammer.check_rate("group_edit:#{state.session_id}", 10_000, 10) do
              {:allow, _count} ->
                GenServer.cast(
                  state.linked_session,
                  {:transfer_group_ownership, data["d"]["session_id"]}
                )

              {:deny, _limit} ->
                send(
                  self(),
                  {:send_event, :RATE_LIMITED}
                )
            end
          end
        else
          send(
            self(),
            {:send_event, :SYNTAX_ERROR, %{code: "MISSING_DATA"}}
          )
        end

      # Kick session from group
      17 ->
        if data["d"] != nil and is_map(data["d"]) do
          if data["d"]["session_id"] == nil do
            send(
              self(),
              {:send_event, :USER_UPDATE_ERROR, %{code: "INVALID_TARGET_SESSION_ID"}}
            )

            :ok
          else
            GenServer.cast(
              state.linked_session,
              {:kick_member_from_group, data["d"]["session_id"]}
            )
          end
        else
          send(
            self(),
            {:send_event, :SYNTAX_ERROR, %{code: "MISSING_DATA"}}
          )
        end

      # Set our sessions away state
      18 ->
        if data["d"] != nil and is_map(data["d"]) do
          if data["d"]["state"] == nil or !is_boolean(data["d"]["state"]) do
            send(
              self(),
              {:send_event, :USER_UPDATE_ERROR, %{code: "INVALID_PAYLOAD"}}
            )

            :ok
          else
            GenServer.cast(
              state.linked_session,
              {:set_session_away_state, data["d"]["state"]}
            )
          end
        else
          send(
            self(),
            {:send_event, :SYNTAX_ERROR, %{code: "MISSING_DATA"}}
          )
        end

      # Set session strain
      19 ->
        if data["d"] != nil and is_map(data["d"]) do
          if data["d"]["strain"] == nil or
               String.trim(data["d"]["strain"]) == "" or
               String.normalize(data["d"]["strain"], :nfc) !=
                 String.normalize(data["d"]["strain"], :nfd) or
               String.length(data["d"]["strain"]) > 32 do
            send(
              self(),
              {:send_event, :USER_UPDATE_ERROR, %{code: "INVALID_PAYLOAD"}}
            )

            :ok
          else
            GenServer.cast(
              state.linked_session,
              {:set_group_session_strain, data["d"]["strain"]}
            )
          end
        else
          send(
            self(),
            {:send_event, :SYNTAX_ERROR, %{code: "MISSING_DATA"}}
          )
        end

      # Link a user session to a gateway session
      20 ->
        if data["d"] != nil and is_map(data["d"]) do
          if data["d"]["token"] == nil or
               String.trim(data["d"]["token"]) == "" do
            send(
              self(),
              {:send_event, :USER_LINK_ERROR, %{code: "INVALID_TOKEN"}}
            )

            :ok
          else
            GenServer.cast(
              state.linked_session,
              {:link_user_to_session, data["d"]["token"]}
            )
          end
        else
          send(
            self(),
            {:send_event, :SYNTAX_ERROR, %{code: "MISSING_DATA"}}
          )
        end

      _ ->
        nil
    end
  end

  defp inflate_msg(data) do
    z = :zlib.open()
    :zlib.inflateInit(z)

    data = :zlib.inflate(z, data)

    :zlib.inflateEnd(z)

    {:ok, data}
  end

  defp construct_msg(encoding, compression, data) do
    data =
      case encoding do
        :etf ->
          data

        _ ->
          data |> Jason.encode!()
      end

    case compression do
      :zlib ->
        z = :zlib.open()
        :zlib.deflateInit(z)

        data = :zlib.deflate(z, data, :finish)

        :zlib.deflateEnd(z)

        {:binary, data}

      _ ->
        {:text, data}
    end
  end
end
