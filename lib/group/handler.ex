defmodule Gateway.Group do
  use GenServer

  defstruct group_id: nil,
            name: nil,
            visibility: nil,
            members: []

  defimpl Jason.Encoder do
    def encode(
          %Gateway.Group{
            group_id: group_id,
            name: name,
            visibility: visibility,
            members: members
          },
          opts
        ) do
      Jason.Encode.map(
        %{
          "group_id" => group_id,
          "name" => name,
          "visibility" => visibility,
          "members" => members
        },
        opts
      )
    end
  end

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: :"#{state.group_id}")
  end

  def init(state) do
    Process.flag(:trap_exit, true)

    group_name = Gateway.Group.Name.generate()

    {:ok,
     %__MODULE__{
       group_id: state.group_id,
       name: group_name,
       visibility: "private",
       members: []
     }, {:continue, :setup_session}}
  end

  def handle_info({:delete}, state) do
    IO.puts("Deleting group #{state.group_id}")

    for member <- state.members do
      {:ok, session} = GenRegistry.lookup(Gateway.Session, member)
      GenServer.cast(session, {:send_group_delete, state.group_id})
    end

    {:stop, :normal, state}
  end

  def handle_call({:get_state}, _from, state) do
    {:reply, state, state}
  end

  def handle_continue(:setup_session, state) do
    {:noreply, state}
  end

  def handle_cast({:update_channel_state, updated_state}, state) do
    new_state =
      Map.merge(state, updated_state |> Map.new(fn {k, v} -> {String.to_atom(k), v} end))

    for member <- state.members do
      {:ok, session} = GenRegistry.lookup(Gateway.Session, member)
      GenServer.cast(session, {:send_group_update, new_state})
    end

    {:noreply, new_state}
  end

  def handle_cast({:group_user_update, session_id, session_state}, state) do
    for member <- state.members do
      if member !== session_id do
        {:ok, session} = GenRegistry.lookup(Gateway.Session, member)

        GenServer.cast(
          session,
          {:send_group_user_update, state.group_id, session_state}
        )
      end
    end

    {:noreply, state}
  end

  def handle_cast({:join_group, session_id, session_name, session_pid}, state) do
    IO.puts("Session #{session_id} joined #{state.group_id}")
    GenServer.cast(session_pid, {:send_join, state})

    for member <- state.members do
      if member !== session_id do
        {:ok, session} = GenRegistry.lookup(Gateway.Session, member)
        GenServer.cast(session, {:send_user_join, state.group_id, session_id, session_name})
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
      IO.puts("Group #{state.group_id} is now empty, deleting")
      send(self(), {:delete})
    end

    {:noreply,
     %{
       state
       | members: Enum.filter(state.members, fn member -> member !== session_id end)
     }}
  end
end
