defmodule Gateway.Session do
  use GenServer

  defstruct session_id: nil,
            name: nil,
            linked_socket: nil,
            group_id: nil,
            device_state: nil,
            device_type: nil

  defimpl Jason.Encoder do
    def encode(
          %Gateway.Session{
            session_id: session_id,
            name: name,
            linked_socket: linked_socket,
            group_id: group_id,
            device_state: device_state,
            device_type: device_type
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
          "device_type" => device_type
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
    Gateway.Metrics.Collector.inc(:gauge, :puffers_connected_sessions)

    {:ok,
     %__MODULE__{
       session_id: state.session_id,
       name: "Unnamed",
       linked_socket: nil,
       group_id: nil,
       device_state: %{}
     }, {:continue, :setup_session}}
  end

  def handle_continue(:setup_session, state) do
    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    IO.puts("Session #{state.session_id} terminated")

    if state.group_id != nil do
      {:ok, group} = GenRegistry.lookup(Gateway.Group, state.group_id)
      GenServer.cast(group, {:leave_group, state.session_id})
    end

    Gateway.Metrics.Collector.dec(:gauge, :puffers_connected_sessions)
    {:noreply, state}
  end

  def handle_info({:send_to_socket, message}, state) do
    send(state.linked_socket, {:remote_send, message})

    {:noreply, state}
  end

  def handle_info({:send_to_socket, message, socket}, state) when is_pid(socket) do
    send(socket, {:remote_send, message})

    {:noreply, state}
  end

  def handle_info({:send_init, socket}, state) when is_pid(socket) do
    send(socket, {:send_op, 0, %{session_id: state.session_id, heartbeat_interval: 25000}})

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
         members:
           Enum.reduce(group_state.members, [], fn id, acc ->
             {:ok, pid} = GenRegistry.lookup(Gateway.Session, id)
             session_state = GenServer.call(pid, {:get_state})

             [
               %{
                 name: session_state.name,
                 session_id: session_state.session_id,
                 device_state: session_state.device_state,
                 device_type: session_state.device_type
               }
               | acc
             ]
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

  def handle_cast({:send_group_user_update, group_id, session_state}, state) do
    send(
      state.linked_socket,
      {:send_event, :GROUP_USER_UPDATED,
       %{group_id: group_id, session_id: session_state.session_id, name: session_state.name}}
    )

    {:noreply, state}
  end

  def handle_cast({:send_group_user_device_update, session_id, device_state, device_type}, state) do
    send(
      state.linked_socket,
      {:send_event, :GROUP_USER_DEVICE_UPDATE,
       %{
         group_id: state.group_id,
         session_id: session_id,
         device_state: device_state,
         device_type: device_type
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

  def handle_cast({:inquire_group_heat}, state) when state.group_id != nil do
    {:ok, group} = GenRegistry.lookup(Gateway.Group, state.group_id)
    GenServer.cast(group, {:inquire_group_heat, state.session_id})

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
    send(state.linked_socket, {:send_event, :GROUP_UPDATE, group_state})

    {:noreply, state}
  end

  def handle_cast({:send_group_delete, group_id}, state) do
    send(state.linked_socket, {:send_event, :GROUP_DELETE, %{group_id: group_id}})

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

  def handle_cast({:join_group, group_id}, state) do
    case GenRegistry.lookup(Gateway.Group, group_id) do
      {:ok, pid} ->
        group_state = GenServer.call(pid, {:get_state})

        if Enum.member?(group_state.members, state.session_id) do
          IO.puts("Session #{state.session_id} tried to rejoin #{group_id}")
          send(state.linked_socket, {:send_event, :GROUP_JOIN_ERROR, %{code: "ALREADY_IN_GROUP"}})
          {:noreply, state}
        else
          IO.puts("Socket connection #{state.session_id} joined group #{group_id}")
          GenServer.cast(pid, {:join_group, state.session_id, state.name, self()})

          {:noreply, %{state | group_id: group_id}}
        end

      {:error, :not_found} ->
        IO.puts("Failed to locate group with that id #{group_id} (#{state.session_id})")
        send(state.linked_socket, {:send_event, :GROUP_JOIN_ERROR, %{code: "INVALID_GROUP_ID"}})

        {:noreply, state}
    end
  end

  def handle_cast({:leave_group}, state) when state.group_id != nil do
    case GenRegistry.lookup(Gateway.Group, state.group_id) do
      {:ok, pid} ->
        group_state = GenServer.call(pid, {:get_state})

        if Enum.member?(group_state.members, state.session_id) do
          GenServer.cast(pid, {:leave_group, state.session_id})
          {:noreply, %{state | group_id: nil, device_state: %{}}}
        end

      {:error, :not_found} ->
        {:noreply, %{state | group_id: nil, device_state: %{}}}
    end
  end

  def handle_cast({:update_device_state, device_state}, state) when state.group_id != nil do
    {:ok, group_pid} = GenRegistry.lookup(Gateway.Group, state.group_id)

    GenServer.cast(
      group_pid,
      {:group_user_device_update, state.session_id, device_state, state.device_type}
    )

    group_state = GenServer.call(group_pid, {:get_state})

    if group_state.state == "awaiting" and device_state["state"] == 6 do
      GenServer.cast(group_pid, {:group_user_ready, state.session_id})
    end

    if group_state.state == "seshing" and device_state["state"] == 5 do
      GenServer.cast(group_pid, {:set_group_state, "chilling"})
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
                member_count: length(state.members)
              }
              | list
            ]
          else
            list
          end
      end)

    send(state.linked_socket, {:send_event, :PUBLIC_GROUPS_UPDATE, groups})

    {:noreply, state}
  end
end
