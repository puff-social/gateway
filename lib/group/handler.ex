defmodule Gateway.Group do
  use GenServer

  defstruct group_id: nil,
            name: nil,
            visibility: nil,
            state: nil,
            members: [],
            ready: []

  defimpl Jason.Encoder do
    def encode(
          %Gateway.Group{
            group_id: group_id,
            name: name,
            visibility: visibility,
            state: state,
            members: members,
            ready: ready
          },
          opts
        ) do
      Jason.Encode.map(
        %{
          "group_id" => group_id,
          "name" => name,
          "visibility" => visibility,
          "state" => state,
          "members" => members,
          "ready" => ready
        },
        opts
      )
    end
  end

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: :"#{state.group_id}")
  end

  def init(state) do
    Gateway.Metrics.Collector.inc(:gauge, :puffers_active_groups)

    {:ok,
     %__MODULE__{
       group_id: state.group_id,
       name: state.name,
       visibility: "private",
       state: "chilling",
       members: [],
       ready: []
     }, {:continue, :setup_session}}
  end

  def handle_info({:delete}, state) do
    IO.puts("Deleting group #{state.group_id}")

    for member <- state.members do
      {:ok, session} = GenRegistry.lookup(Gateway.Session, member)
      GenServer.cast(session, {:send_group_delete, state.group_id})
    end

    Gateway.Metrics.Collector.dec(:gauge, :puffers_active_groups)

    {:stop, :normal, state}
  end

  def handle_info({:check_empty_and_delete}, state) do
    if length(state.members) == 0 do
      IO.puts("Deleting group #{state.group_id}")
      Gateway.Metrics.Collector.dec(:gauge, :puffers_active_groups)
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_call({:get_state}, _from, state) do
    {:reply, state, state}
  end

  def handle_continue(:setup_session, state) do
    {:noreply, state}
  end

  def handle_cast({:update_channel_state, updated_state, session_id}, state) do
    new_state =
      Map.merge(state, updated_state |> Map.new(fn {k, v} -> {String.to_atom(k), v} end))

    for member <- state.members do
      {:ok, session} = GenRegistry.lookup(Gateway.Session, member)
      GenServer.cast(session, {:send_group_update, new_state})

      if state.visibility != new_state.visibility do
        GenServer.cast(session, {:send_visiblity_action, new_state.visibility, session_id})
      end
    end

    if state.visibility != new_state.visibility do
      {_max_id, _max_pid} =
        GenRegistry.reduce(Gateway.Session, {nil, -1}, fn
          {id, pid}, {_, _current} = _acc ->
            GenServer.cast(pid, {:send_public_groups})
            {id, pid}
        end)
    end

    {:noreply, new_state}
  end

  def handle_cast({:group_user_update, session_id, session_state}, state) do
    for member <- state.members do
      {:ok, session} = GenRegistry.lookup(Gateway.Session, member)

      GenServer.cast(
        session,
        {:send_group_user_update, session_id, session_state}
      )
    end

    {:noreply, state}
  end

  def handle_cast({:group_user_device_disconnect, session_id}, state) do
    for member <- state.members do
      if member !== session_id do
        {:ok, session} = GenRegistry.lookup(Gateway.Session, member)

        GenServer.cast(session, {:send_group_user_device_disconnect, session_id})
      end
    end

    {:noreply, state}
  end

  def handle_cast({:group_user_device_update, session_id, device_state, device_type}, state) do
    for member <- state.members do
      if member !== session_id do
        {:ok, session} = GenRegistry.lookup(Gateway.Session, member)

        GenServer.cast(
          session,
          {:send_group_user_device_update, session_id, device_state, device_type}
        )
      end
    end

    {:noreply, state}
  end

  def handle_cast({:set_group_state, new_group_state}, state) do
    new_state = %{state | state: new_group_state}

    for member <- state.members do
      {:ok, session} = GenRegistry.lookup(Gateway.Session, member)
      GenServer.cast(session, {:send_group_update, new_state})
    end

    {:noreply, new_state}
  end

  def handle_cast({:start_group_heat}, state) do
    new_state = %{state | state: "seshing"}

    for member <- state.ready do
      {:ok, session} = GenRegistry.lookup(Gateway.Session, member)
      GenServer.cast(session, {:send_group_update, new_state})
      GenServer.cast(session, {:send_group_heat_start})
    end

    for member <- state.members do
      {:ok, session} = GenRegistry.lookup(Gateway.Session, member)
      GenServer.cast(session, {:send_group_update, new_state})
    end

    {:noreply, new_state}
  end

  def handle_cast({:start_group_heat, members}, state) do
    new_state = %{state | state: "seshing"}

    for member <- members do
      {:ok, session} = GenRegistry.lookup(Gateway.Session, member)
      GenServer.cast(session, {:send_group_heat_start})
      GenServer.cast(session, {:send_group_update, new_state})
    end

    for member <- state.members do
      {:ok, session} = GenRegistry.lookup(Gateway.Session, member)
      GenServer.cast(session, {:send_group_update, new_state})
    end

    {:noreply, new_state}
  end

  def handle_cast({:group_user_ready, session_id}, state) do
    for member <- state.members do
      {:ok, session} = GenRegistry.lookup(Gateway.Session, member)
      GenServer.cast(session, {:send_group_user_ready, session_id})
    end

    if Enum.member?(state.ready, session_id) do
      {:noreply, state}
    else
      ready_members = Enum.concat(state.ready, [session_id])

      members_with_devices =
        Enum.filter(state.members, fn member ->
          {:ok, pid} = GenRegistry.lookup(Gateway.Session, member)
          session_state = GenServer.call(pid, {:get_state})
          session_state.device_state != %{}
        end)

      case length(ready_members) >= length(members_with_devices) do
        true ->
          GenServer.cast(self(), {:start_group_heat, ready_members})
          {:noreply, %{state | ready: []}}

        false ->
          {:noreply, %{state | ready: ready_members}}
      end
    end
  end

  def handle_cast({:inquire_group_heat, session_id}, state) do
    new_state = %{state | state: "awaiting"}

    for member <- state.members do
      {:ok, session} = GenRegistry.lookup(Gateway.Session, member)
      GenServer.cast(session, {:send_group_update, new_state})
      GenServer.cast(session, {:send_group_heat_inquiry, session_id})
    end

    {:noreply, new_state}
  end

  def handle_cast({:join_group, session_id, session_name, device_type, session_pid}, state) do
    IO.puts("Session #{session_id} joined #{state.group_id}")
    GenServer.cast(session_pid, {:send_join, state})

    for member <- state.members do
      if member !== session_id do
        {:ok, session} = GenRegistry.lookup(Gateway.Session, member)

        GenServer.cast(
          session,
          {:send_user_join, state.group_id, session_id, session_name, device_type}
        )
      end
    end

    {:noreply,
     %{
       state
       | members: Enum.concat(state.members, [session_id])
     }}
  end

  def handle_cast({:leave_group, session_id}, state) do
    IO.puts("Session #{session_id} left #{state.group_id}")

    for member <- state.members do
      if member !== session_id do
        {:ok, session} = GenRegistry.lookup(Gateway.Session, member)
        GenServer.cast(session, {:send_user_leave, state.group_id, session_id})
      end
    end

    if length(state.members) == 1 do
      IO.puts(
        "Group #{state.group_id} is now empty, starting timeout to check and delete in 10 seconds"
      )

      Process.send_after(self(), {:check_empty_and_delete}, 10000)
    end

    {:noreply,
     %{
       state
       | members: Enum.filter(state.members, fn member -> member !== session_id end)
     }}
  end
end
