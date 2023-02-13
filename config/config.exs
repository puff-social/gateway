use Mix.Config

config :gateway,
  port: String.to_integer(System.get_env("PORT") || "9000"),
  metrics_port: String.to_integer(System.get_env("METRICS_PORT") || "9001"),
  redis_uri: System.get_env("REDIS_URI") || "redis://redis:6379"
