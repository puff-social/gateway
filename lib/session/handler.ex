defmodule Gateway.Session do
  use GenServer

  alias Gateway.Session.Token

  defstruct session_id: nil,
            name: nil,
            linked_socket: nil,
            group_id: nil,
            device_state: nil,
            session_token: nil

  defimpl Jason.Encoder do
    def encode(
          %Gateway.Session{
            session_id: session_id,
            name: name,
            linked_socket: linked_socket,
            group_id: group_id,
            device_state: device_state,
            session_token: session_token
          },
          opts
        ) do
      Jason.Encode.map(
        %{
          "session_id" => session_id,
          "name" => name,
          "linked_socket" => linked_socket,
          "group_id" => group_id,
          "device_state" => device_state,
          "session_token" => session_token
        },
        opts
      )
    end
  end

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: :"#{state.session_id}")
  end

  def init(state) do
    Process.flag(:trap_exit, true)

    session_token = Token.generate()

    {:ok,
     %__MODULE__{
       session_id: state.session_id,
       name: "Unnamed",
       linked_socket: nil,
       group_id: nil,
       device_state: %{},
       session_token: session_token
     }, {:continue, :setup_session}}
  end

  def terminate(_reason, state) do
    {:noreply, state}
  end

  def handle_continue(:setup_session, state) do
    {:noreply, state}
  end

  def handle_info({:close_session_if_socket_dead}, state) do
    if Process.alive?(state.linked_socket) do
      {:noreply, state}
    else
      if state.group_id != nil do
        {:ok, group} = GenRegistry.lookup(Gateway.Group, state.group_id)

        if group != nil do
          GenServer.cast(group, {:leave_group, state.session_id})
        end
      end

      {:stop, :normal, state}
    end
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  def handle_info({:send_to_socket, message}, state) do
    if Process.alive?(state.linked_socket) do
      send(state.linked_socket, {:remote_send, message})
    end

    {:noreply, state}
  end

  def handle_info({:send_to_socket, message, socket}, state) when is_pid(socket) do
    send(socket, {:remote_send, message})

    {:noreply, state}
  end

  def handle_info({:send_init, socket}, state) when is_pid(socket) do
    send(
      socket,
      {:send_op, 0,
       %{
         session_id: state.session_id,
         session_token: state.session_token,
         heartbeat_interval: 25000
       }}
    )

    {:noreply, state}
  end

  def handle_call({:get_state}, _from, state) do
    {:reply, state, state}
  end

  def handle_cast({:send_join, group_state}, state) do
    send(
      state.linked_socket,
      {:send_event, :JOINED_GROUP,
       %{
         name: group_state.name,
         group_id: group_state.group_id,
         visibility: group_state.visibility,
         state: group_state.state,
         sesh_counter: group_state.sesh_counter,
         members:
           Enum.reduce(group_state.members, [], fn id, acc ->
             case GenRegistry.lookup(Gateway.Session, id) do
               {:ok, pid} ->
                 session_state = GenServer.call(pid, {:get_state})

                 if Process.alive?(pid) do
                   [
                     %{
                       name: session_state.name,
                       session_id: session_state.session_id,
                       device_state: session_state.device_state
                     }
                     | acc
                   ]
                 else
                   acc
                 end

               {:error, :not_found} ->
                 acc
             end
           end)
       }}
    )

    {:noreply, state}
  end

  def handle_cast({:send_user_join, group_id, session_id, session_name}, state) do
    send(
      state.linked_socket,
      {:send_event, :GROUP_USER_JOIN,
       %{group_id: group_id, session_id: session_id, name: session_name}}
    )

    {:noreply, state}
  end

  def handle_cast({:send_group_user_ready, session_id}, state) do
    send(
      state.linked_socket,
      {:send_event, :GROUP_USER_READY, %{session_id: session_id}}
    )

    {:noreply, state}
  end

  def handle_cast({:send_group_user_unready, session_id}, state) do
    send(
      state.linked_socket,
      {:send_event, :GROUP_USER_UNREADY, %{session_id: session_id}}
    )

    {:noreply, state}
  end

  def handle_cast({:send_group_user_update, group_id, session_state}, state) do
    send(
      state.linked_socket,
      {:send_event, :GROUP_USER_UPDATE,
       %{
         group_id: group_id,
         session_id: session_state.session_id,
         name: session_state.name
       }}
    )

    {:noreply, state}
  end

  def handle_cast({:send_group_user_device_update, session_id, device_state}, state) do
    send(
      state.linked_socket,
      {:send_event, :GROUP_USER_DEVICE_UPDATE,
       %{
         group_id: state.group_id,
         session_id: session_id,
         device_state: device_state
       }}
    )

    {:noreply, state}
  end

  def handle_cast({:send_group_user_message, author_session_id, message_data}, state) do
    send(
      state.linked_socket,
      {:send_event, :GROUP_MESSAGE,
       %{
         group_id: state.group_id,
         author_session_id: author_session_id,
         message: message_data
       }}
    )

    {:noreply, state}
  end

  def handle_cast({:send_group_user_device_disconnect, session_id}, state) do
    send(
      state.linked_socket,
      {:send_event, :GROUP_USER_DEVICE_DISCONNECT,
       %{
         group_id: state.group_id,
         session_id: session_id
       }}
    )

    {:noreply, state}
  end

  def handle_cast({:send_visiblity_action, new_visibility, session_id}, state) do
    send(
      state.linked_socket,
      {:send_event, :GROUP_VISIBILITY_CHANGE,
       %{visibility: new_visibility, session_id: session_id}}
    )

    {:noreply, state}
  end

  def handle_cast({:send_group_heat_start}, state) do
    send(
      state.linked_socket,
      {:send_event, :GROUP_START_HEATING}
    )

    {:noreply, state}
  end

  def handle_cast({:send_group_heat_inquiry, session_id}, state) do
    send(
      state.linked_socket,
      {:send_event, :GROUP_HEAT_INQUIRY, %{session_id: session_id}}
    )

    {:noreply, state}
  end

  def handle_cast({:disconnect_device}, state) do
    if state.group_id != nil do
      {:ok, group} = GenRegistry.lookup(Gateway.Group, state.group_id)
      GenServer.cast(group, {:group_user_device_disconnect, state.session_id})
      {:noreply, %{state | device_state: %{}}}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:send_message_to_group, message_data}, state) do
    if state.group_id != nil do
      {:ok, group} = GenRegistry.lookup(Gateway.Group, state.group_id)
      GenServer.cast(group, {:broadcast_user_message, message_data, state.session_id})
    end

    {:noreply, state}
  end

  def handle_cast({:start_with_ready}, state) do
    if state.group_id != nil do
      {:ok, group} = GenRegistry.lookup(Gateway.Group, state.group_id)
      group_state = GenServer.call(group, {:get_state})

      if length(group_state.ready) == 0 do
        if Process.alive?(state.linked_socket) do
          send(
            state.linked_socket,
            {:send_event, :GROUP_ACTION_ERROR, %{code: "NO_MEMBERS_READY"}}
          )
        end
      else
        GenServer.cast(group, {:start_group_heat})
      end
    end

    {:noreply, state}
  end

  def handle_cast({:inquire_group_heat}, state) do
    {:ok, group} = GenRegistry.lookup(Gateway.Group, state.group_id)
    GenServer.cast(group, {:inquire_group_heat, state.session_id})

    {:noreply, state}
  end

  def handle_cast({:fail_heat_inquiry, error}, state) do
    if Process.alive?(state.linked_socket) do
      send(state.linked_socket, {:send_event, :GROUP_ACTION_ERROR, error})
    end

    {:noreply, state}
  end

  def handle_cast({:stop_group_heat}, state) do
    {:ok, group} = GenRegistry.lookup(Gateway.Group, state.group_id)
    GenServer.cast(group, {:stop_group_heat, state.session_id})

    {:noreply, state}
  end

  def handle_cast({:send_user_leave, group_id, session_id}, state) do
    send(
      state.linked_socket,
      {:send_event, :GROUP_USER_LEFT, %{group_id: group_id, session_id: session_id}}
    )

    {:noreply, state}
  end

  def handle_cast({:send_group_update, group_state}, state) do
    if Process.alive?(state.linked_socket) do
      send(state.linked_socket, {:send_event, :GROUP_UPDATE, group_state})
    end

    {:noreply, state}
  end

  def handle_cast({:send_group_delete, group_id}, state) do
    if Process.alive?(state.linked_socket) do
      send(state.linked_socket, {:send_event, :GROUP_DELETE, %{group_id: group_id}})
    end

    {:noreply, state}
  end

  def handle_cast({:link_socket, socket_pid}, state) do
    send(self(), {:send_init, socket_pid})

    {:noreply,
     %{
       state
       | linked_socket: socket_pid
     }}
  end

  def handle_cast({:link_socket_without_init, socket_pid}, state) do
    {:noreply,
     %{
       state
       | linked_socket: socket_pid
     }}
  end

  def handle_cast({:create_group, group_id, group_name, group_visibility}, state) do
    if String.length(group_name) > 32 do
      send(
        state.linked_socket,
        {:send_event, :GROUP_CREATE_ERROR, %{code: "INVALID_GROUP_NAME"}}
      )
    else
      {:ok, _pid} =
        GenRegistry.lookup_or_start(Gateway.Group, group_id, [
          %{
            group_id: group_id,
            name: group_name,
            visibility: group_visibility,
            owner_session_id: state.session_id
          }
        ])

      send(
        state.linked_socket,
        {:send_event, :GROUP_CREATE,
         %{
           group_id: group_id,
           name: group_name,
           visibility: group_visibility,
           owner_session_id: state.session_id
         }}
      )
    end

    {:noreply, state}
  end

  def handle_cast({:join_group, group_id}, state) do
    case GenRegistry.lookup(Gateway.Group, group_id) do
      {:ok, pid} ->
        group_state = GenServer.call(pid, {:get_state})

        if Enum.member?(group_state.members, state.session_id) do
          if Process.alive?(state.linked_socket) do
            send(
              state.linked_socket,
              {:send_event, :GROUP_JOIN_ERROR, %{code: "ALREADY_IN_GROUP"}}
            )
          end

          {:noreply, state}
        else
          GenServer.cast(
            pid,
            {:join_group, state.session_id, state.name, self()}
          )

          {:noreply, %{state | group_id: group_id}}
        end

      {:error, :not_found} ->
        if Process.alive?(state.linked_socket) do
          send(state.linked_socket, {:send_event, :GROUP_JOIN_ERROR, %{code: "INVALID_GROUP_ID"}})
        end

        {:noreply, state}
    end
  end

  def handle_cast({:leave_group}, state) do
    case GenRegistry.lookup(Gateway.Group, state.group_id) do
      {:ok, pid} ->
        group_state = GenServer.call(pid, {:get_state})

        if Enum.member?(group_state.members, state.session_id) do
          GenServer.cast(pid, {:leave_group, state.session_id})
        end

        {:noreply, %{state | group_id: nil, device_state: %{}}}

      {:error, :not_found} ->
        {:noreply, %{state | group_id: nil, device_state: %{}}}
    end
  end

  def handle_cast({:update_device_state, device_state}, state) when state.group_id != nil do
    {:ok, group_pid} = GenRegistry.lookup(Gateway.Group, state.group_id)

    GenServer.cast(
      group_pid,
      {:group_user_device_update, state.session_id, device_state}
    )

    group_state = GenServer.call(group_pid, {:get_state})

    cond do
      group_state.state == "awaiting" and device_state["state"] == 6 ->
        GenServer.cast(group_pid, {:group_user_ready, state.session_id})

      group_state.state == "seshing" and device_state["state"] == 5 and
          (state.device_state.state == 8 or state.device_state.state == 7) ->
        GenServer.cast(group_pid, {:increment_sesh_counter})
        GenServer.cast(group_pid, {:set_group_state, "chilling"})

      true ->
        true
    end

    {:noreply,
     %{
       state
       | device_state:
           Map.merge(
             state.device_state,
             device_state |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
           )
     }}
  end

  def handle_cast({:edit_current_group, group_data}, state) do
    {:ok, group_pid} = GenRegistry.lookup(Gateway.Group, state.group_id)
    GenServer.cast(group_pid, {:update_channel_state, group_data, state.session_id})

    {:noreply, state}
  end

  def handle_cast({:start_group_heating}, state) do
    {:ok, group_pid} = GenRegistry.lookup(Gateway.Group, state.group_id)
    GenServer.cast(group_pid, {:start_group_heat})

    {:noreply, state}
  end

  def handle_cast({:update_session_state, session_data}, state) do
    new_state = Map.merge(state, session_data |> Map.new(fn {k, v} -> {String.to_atom(k), v} end))

    if state.group_id != nil do
      {:ok, group_pid} = GenRegistry.lookup(Gateway.Group, state.group_id)
      GenServer.cast(group_pid, {:group_user_update, state.session_id, new_state})
    end

    {:noreply, new_state}
  end

  def handle_cast({:send_public_groups}, state) do
    groups =
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
                member_count: length(state.members),
                sesh_counter: state.sesh_counter
              }
              | list
            ]
          else
            list
          end
      end)

    if Process.alive?(state.linked_socket) do
      send(state.linked_socket, {:send_event, :PUBLIC_GROUPS_UPDATE, groups})
    end

    {:noreply, state}
  end
end
