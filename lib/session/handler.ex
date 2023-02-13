defmodule Gateway.Session do
  use GenServer

  defstruct session_id: nil,
            name: nil,
            linked_socket: nil,
            group_id: nil,
            puffco_state: nil

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: :"#{state.session_id}")
  end

  def init(state) do
    Process.flag(:trap_exit, true)

    {:ok,
     %__MODULE__{
       session_id: state.session_id,
       name: "Unnamed",
       linked_socket: nil,
       group_id: nil,
       puffco_state: nil
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
    send(socket, {:send_op, 0, %{heartbeat_interval: 25000}})

    {:noreply, state}
  end

  def handle_call({:get_state}, _from, state) do
    {:reply, state, state}
  end

  def handle_cast({:send_join, group_state}, state) do
    send(
      state.linked_socket,
      {:send_op, 2,
       %{
         name: group_state.name,
         group_id: group_state.group_id,
         visibility: group_state.visibility,
         members: Enum.concat(group_state.members, [state.session_id])
       }}
    )

    {:noreply, state}
  end

  def handle_cast({:send_user_join, group_id, session_id, session_name}, state) do
    send(
      state.linked_socket,
      {:send_op, 3, %{group_id: group_id, session_id: session_id, name: session_name}}
    )

    {:noreply, state}
  end

  def handle_cast({:send_group_user_update, group_id, session_state}, state) do
    send(
      state.linked_socket,
      {:send_op, 15,
       %{group_id: group_id, session_id: session_state.session_id, name: session_state.name}}
    )

    {:noreply, state}
  end

  def handle_cast({:send_user_leave, group_id, session_id}, state) do
    send(state.linked_socket, {:send_op, 4, %{group_id: group_id, session_id: session_id}})

    {:noreply, state}
  end

  def handle_cast({:send_group_update, group_state}, state) do
    send(state.linked_socket, {:send_op, 12, group_state})

    {:noreply, state}
  end

  def handle_cast({:send_group_delete, group_id}, state) do
    send(state.linked_socket, {:send_op, 7, %{group_id: group_id}})

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
          send(state.linked_socket, {:send_op, 8, %{code: "ALREADY_IN_GROUP"}})
          {:noreply, state}
        else
          IO.puts("Socket connection #{state.session_id} joined group #{group_id}")
          GenServer.cast(pid, {:join_group, state.session_id, state.name, self()})

          {:noreply, %{state | group_id: group_id}}
        end

      {:error, :not_found} ->
        IO.puts("Failed to locate group with that id #{group_id} (#{state.session_id})")
        send(state.linked_socket, {:remote_close, 4001, "INVALID_GROUP_ID"})

        {:noreply, state}
    end
  end

  def handle_cast({:edit_current_group, group_data}, state) do
    {:ok, group_pid} = GenRegistry.lookup(Gateway.Group, state.group_id)
    GenServer.cast(group_pid, {:update_channel_state, group_data})

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
end
