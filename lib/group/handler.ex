defmodule Gateway.Group do
  use GenServer

  defstruct group_id: nil,
            name: nil,
            visibility: nil,
            state: nil,
            sesh_counter: nil,
            owner_session_id: nil,
            members: [],
            ready: []

  defimpl Jason.Encoder do
    def encode(
          %Gateway.Group{
            group_id: group_id,
            name: name,
            visibility: visibility,
            state: state,
            sesh_counter: sesh_counter,
            owner_session_id: owner_session_id,
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
          "sesh_counter" => sesh_counter,
          "owner_session_id" => owner_session_id,
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
       visibility: state.visibility,
       state: "chilling",
       sesh_counter: 0,
       owner_session_id: state.owner_session_id,
       members: [],
       ready: []
     }, {:continue, :setup_session}}
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  def handle_info({:delete}, state) do
    for member <- state.members do
      case GenRegistry.lookup(Gateway.Session, member) do
        {:ok, pid} ->
          GenServer.cast(pid, {:send_group_delete, state.group_id})

        {:error, :not_found} ->
          nil
      end
    end

    Gateway.Metrics.Collector.dec(:gauge, :puffers_active_groups)

    {:stop, :normal, state}
  end

  def handle_info({:check_empty_and_delete}, state) do
    if length(state.members) == 0 do
      Gateway.Metrics.Collector.dec(:gauge, :puffers_active_groups)

      if state.visibility == "public" do
        GenRegistry.reduce(Gateway.Session, {nil, -1}, fn
          {id, pid}, {_, _current} = _acc ->
            GenServer.cast(pid, {:send_public_groups})
            {id, pid}
        end)
      end

      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  def handle_call({:get_state}, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:get_members}, _from, state) do
    members_with_devices =
      Enum.filter(state.members, fn member ->
        case GenRegistry.lookup(Gateway.Session, member) do
          {:ok, pid} ->
            if Process.alive?(pid) do
              session_state = GenServer.call(pid, {:get_state})
              session_state.device_state != %{}
            else
              false
            end

          {:error, :not_found} ->
            nil
        end
      end)

    members_without_devices =
      Enum.filter(state.members, fn member ->
        case GenRegistry.lookup(Gateway.Session, member) do
          {:ok, pid} ->
            if Process.alive?(pid) do
              session_state = GenServer.call(pid, {:get_state})
              session_state.device_state == %{}
            else
              false
            end

          {:error, :not_found} ->
            false
        end
      end)

    {:reply,
     %{
       seshers: members_with_devices,
       watchers: members_without_devices
     }, state}
  end

  def handle_continue(:setup_session, state) do
    {:noreply, state}
  end

  def handle_cast({:increment_sesh_counter}, state) do
    new_state = %{state | sesh_counter: state.sesh_counter + 1}

    for member <- state.members do
      case GenRegistry.lookup(Gateway.Session, member) do
        {:ok, pid} ->
          GenServer.cast(pid, {:send_group_update, new_state})

        {:error, :not_found} ->
          nil
      end
    end

    {:noreply, new_state}
  end

  def handle_cast({:update_channel_state, updated_state, session_id}, state) do
    new_state =
      Map.merge(state, updated_state |> Map.new(fn {k, v} -> {String.to_atom(k), v} end))

    for member <- state.members do
      case GenRegistry.lookup(Gateway.Session, member) do
        {:ok, pid} ->
          GenServer.cast(pid, {:send_group_update, new_state})

          if state.visibility != new_state.visibility do
            GenServer.cast(pid, {:send_visiblity_action, new_state.visibility, session_id})
          end

        {:error, :not_found} ->
          nil
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
      case GenRegistry.lookup(Gateway.Session, member) do
        {:ok, pid} ->
          GenServer.cast(
            pid,
            {:send_group_user_update, session_id, session_state}
          )

        {:error, :not_found} ->
          nil
      end
    end

    {:noreply, state}
  end

  def handle_cast({:broadcast_user_message, message_data, session_id}, state) do
    for member <- state.members do
      case GenRegistry.lookup(Gateway.Session, member) do
        {:ok, pid} ->
          GenServer.cast(pid, {:send_group_user_message, session_id, message_data})

        {:error, :not_found} ->
          nil
      end
    end

    {:noreply, state}
  end

  def handle_cast({:group_user_device_disconnect, session_id}, state) do
    members_with_devices =
      Enum.filter(state.members, fn member ->
        case GenRegistry.lookup(Gateway.Session, member) do
          {:ok, pid} ->
            if Process.alive?(pid) do
              session_state = GenServer.call(pid, {:get_state})
              session_state.device_state != %{}
            else
              false
            end

          {:error, :not_found} ->
            false
        end
      end)

    for member <- state.members do
      case GenRegistry.lookup(Gateway.Session, member) do
        {:ok, pid} ->
          if member !== session_id do
            if Enum.member?(state.ready, session_id) do
              GenServer.cast(self(), {:group_user_unready, session_id})
            end

            GenServer.cast(pid, {:send_group_user_device_disconnect, session_id})
          end

          if length(members_with_devices) == 0 do
            GenServer.cast(pid, {:send_group_update, %{state | state: "chilling"}})
          end

        {:error, :not_found} ->
          nil
      end
    end

    if length(members_with_devices) == 0 do
      {:noreply, %{state | state: "chilling"}}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:group_user_device_update, session_id, device_state}, state) do
    for member <- state.members do
      if member !== session_id do
        case GenRegistry.lookup(Gateway.Session, member) do
          {:ok, pid} ->
            GenServer.cast(
              pid,
              {:send_group_user_device_update, session_id, device_state}
            )

          {:error, :not_found} ->
            nil
        end
      end
    end

    {:noreply, state}
  end

  def handle_cast({:set_group_state, new_group_state}, state) do
    new_state = %{state | state: new_group_state}

    for member <- state.members do
      case GenRegistry.lookup(Gateway.Session, member) do
        {:ok, pid} ->
          GenServer.cast(pid, {:send_group_update, new_state})

        {:error, :not_found} ->
          nil
      end
    end

    {:noreply, new_state}
  end

  def handle_cast({:start_group_heat}, state) do
    new_state = %{state | state: "seshing"}

    for member <- state.ready do
      case GenRegistry.lookup(Gateway.Session, member) do
        {:ok, pid} ->
          GenServer.cast(pid, {:send_group_update, new_state})
          GenServer.cast(pid, {:send_group_heat_start})

        {:error, :not_found} ->
          nil
      end
    end

    for member <- state.members do
      case GenRegistry.lookup(Gateway.Session, member) do
        {:ok, pid} ->
          GenServer.cast(pid, {:send_group_update, new_state})

        {:error, :not_found} ->
          nil
      end
    end

    {:noreply, new_state}
  end

  def handle_cast({:start_group_heat, members}, state) do
    new_state = %{state | state: "seshing", ready: []}

    for member <- members do
      case GenRegistry.lookup(Gateway.Session, member) do
        {:ok, pid} ->
          GenServer.cast(pid, {:send_group_heat_start})
          GenServer.cast(pid, {:send_group_update, new_state})

        {:error, :not_found} ->
          nil
      end
    end

    {:noreply, new_state}
  end

  def handle_cast({:group_user_ready, session_id}, state) do
    for member <- state.members do
      case GenRegistry.lookup(Gateway.Session, member) do
        {:ok, pid} ->
          GenServer.cast(pid, {:send_group_user_ready, session_id})

        {:error, :not_found} ->
          nil
      end
    end

    if Enum.member?(state.ready, session_id) do
      {:noreply, state}
    else
      ready_members = Enum.concat(state.ready, [session_id])

      members_with_devices =
        Enum.filter(state.members, fn member ->
          case GenRegistry.lookup(Gateway.Session, member) do
            {:ok, pid} ->
              if Process.alive?(pid) do
                session_state = GenServer.call(pid, {:get_state})
                session_state.device_state != %{}
              else
                false
              end

            {:error, :not_found} ->
              false
          end
        end)

      case length(ready_members) >= length(members_with_devices) do
        true ->
          GenServer.cast(self(), {:start_group_heat, ready_members})
          {:noreply, state}

        false ->
          {:noreply, %{state | ready: ready_members}}
      end
    end
  end

  def handle_cast({:group_user_unready, session_id}, state) do
    members_with_devices =
      Enum.filter(state.members, fn member ->
        case GenRegistry.lookup(Gateway.Session, member) do
          {:ok, pid} ->
            if Process.alive?(pid) do
              session_state = GenServer.call(pid, {:get_state})
              session_state.device_state != %{}
            else
              false
            end

          {:error, :not_found} ->
            false
        end
      end)

    if length(members_with_devices) == 0 do
      new_state = %{
        state
        | state: "chilling",
          ready: Enum.filter(state.ready, fn member -> member !== session_id end)
      }

      for member <- state.members do
        case GenRegistry.lookup(Gateway.Session, member) do
          {:ok, pid} ->
            GenServer.cast(pid, {:send_group_update, new_state})

          {:error, :not_found} ->
            nil
        end
      end

      {:noreply, new_state}
    else
      for member <- state.members do
        case GenRegistry.lookup(Gateway.Session, member) do
          {:ok, pid} ->
            GenServer.cast(pid, {:send_group_user_unready, session_id})

          {:error, :not_found} ->
            nil
        end
      end

      new_state = %{
        state
        | ready: Enum.filter(state.ready, fn member -> member !== session_id end)
      }

      {:noreply, new_state}
    end
  end

  def handle_cast({:inquire_group_heat, session_id}, state) do
    members_with_devices =
      Enum.filter(state.members, fn member ->
        case GenRegistry.lookup(Gateway.Session, member) do
          {:ok, pid} ->
            if Process.alive?(pid) do
              session_state = GenServer.call(pid, {:get_state})
              session_state.device_state != %{}
            else
              false
            end

          {:error, :not_found} ->
            nil
        end
      end)

    if length(members_with_devices) == 0 do
      {:ok, pid} = GenRegistry.lookup(Gateway.Session, session_id)
      GenServer.cast(pid, {:fail_heat_inquiry, %{code: "NO_SESHERS"}})

      {:noreply, state}
    else
      new_state = %{state | state: "awaiting"}

      for member <- state.members do
        case GenRegistry.lookup(Gateway.Session, member) do
          {:ok, pid} ->
            GenServer.cast(pid, {:send_group_update, new_state})
            GenServer.cast(pid, {:send_group_heat_inquiry, session_id})

          {:error, :not_found} ->
            nil
        end
      end

      {:noreply, new_state}
    end
  end

  def handle_cast({:stop_group_heat, _session_id}, state) do
    new_state = %{state | state: "chilling", ready: []}

    for member <- state.members do
      case GenRegistry.lookup(Gateway.Session, member) do
        {:ok, pid} ->
          GenServer.cast(pid, {:send_group_update, new_state})

        {:error, :not_found} ->
          nil
      end
    end

    {:noreply, new_state}
  end

  def handle_cast({:join_group, session_id, session_name, session_pid}, state) do
    GenServer.cast(session_pid, {:send_join, state})

    for member <- state.members do
      if member !== session_id do
        case GenRegistry.lookup(Gateway.Session, member) do
          {:ok, pid} ->
            GenServer.cast(
              pid,
              {:send_user_join, state.group_id, session_id, session_name}
            )

          {:error, :not_found} ->
            nil
        end
      end
    end

    {:noreply,
     %{
       state
       | members: Enum.concat(state.members, [session_id])
     }}
  end

  def handle_cast({:leave_group, session_id}, state) do
    if Enum.member?(state.ready, session_id) do
      GenServer.cast(self(), {:group_user_unready, session_id})
    end

    for member <- state.members do
      if member !== session_id do
        case GenRegistry.lookup(Gateway.Session, member) do
          {:ok, pid} ->
            GenServer.cast(pid, {:send_user_leave, state.group_id, session_id})

          {:error, :not_found} ->
            nil
        end
      end
    end

    if length(state.members) == 1 do
      Process.send_after(self(), {:check_empty_and_delete}, 30000)
    end

    {:noreply,
     %{
       state
       | members: Enum.filter(state.members, fn member -> member !== session_id end)
     }}
  end
end
