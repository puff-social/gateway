defmodule Gateway.Session.Token do
  def generate() do
    for _ <- 1..32,
        into: "",
        do: <<Enum.random('0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ')>>
  end
end
