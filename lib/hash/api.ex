defmodule Gateway.Hash do
  def get_user_by_token(token) do
    %HTTPoison.Response{body: body} =
      HTTPoison.get!("#{Application.fetch_env!(:gateway, :internal_api)}/verify", %{
        "authorization" => token
      })

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
