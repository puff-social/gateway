defmodule Gateway.Hash do
  @internal_api System.get_env("INTERNAL_API") || "http://127.0.0.1:8002"

  def get_user_by_token(token) do
    %HTTPoison.Response{body: body} =
      HTTPoison.get!("#{@internal_api}/verify", %{"authorization" => token})

    %{
      "valid" => valid,
      "user" => user
    } = body |> Jason.decode!()

    if !valid do
      nil
    end

    user
  end
end
