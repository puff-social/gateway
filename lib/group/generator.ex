defmodule Gateway.Group.Generator do
  @adjectives ~w(
    Blue Afghan Bubba Maui Golden White Pineapple
    Fruity Sour Apple Jack Green Bruce Grease Banana
    Tropicana Durban Khalifa Lava
  )

  @nouns ~w(
    Dream Kush Wowie Goat Widow Express Pebbles Diesel
    Fritter Herer Crack Banner Monkey Cookies Posion Cake
  )

  def generateName() do
    adjective = @adjectives |> Enum.random()
    noun = @nouns |> Enum.random()

    [adjective, noun] |> Enum.join(" ")
  end

  def generateId() do
    for _ <- 1..6, into: "", do: <<Enum.random('0123456789abcdefghijklmnopqrstuvwxyz')>>
  end
end
