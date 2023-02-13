defmodule Gateway do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      {GenRegistry, worker_module: Gateway.Session},
      {GenRegistry, worker_module: Gateway.Group},
      {Redix, {Application.fetch_env!(:gateway, :redis_uri), [name: :redix]}},
      {Plug.Cowboy,
       scheme: :http,
       plug: Gateway.Router,
       options: [
         port: Application.fetch_env!(:gateway, :port),
         dispatch: dispatch()
       ]},
      {Gateway.Metrics, :normal},
      {Plug.Cowboy,
       scheme: :http,
       plug: Gateway.Metrics.Router,
       options: [port: Application.fetch_env!(:gateway, :metrics_port)]}
    ]

    IO.puts("Starting Gateway App on #{Application.fetch_env!(:gateway, :port)}")

    opts = [strategy: :one_for_one, name: Gateway.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def dispatch do
    [
      {:_,
       [
         {"/socket", Gateway.Socket.Handler, []},
         {:_, Plug.Cowboy.Handler, {Gateway.Router, []}}
       ]}
    ]
  end
end
