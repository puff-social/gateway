defmodule Gateway.Group.Name do
  @adjectives ~w(
    Blue Afghan Bubba Maui Golden White Pineapple
    Fruity Sour Apple Jack Green Bruce Grease Banana
    Tropicana Durban Khalifa Lava
  )

  @nouns ~w(
    Dream Kush Wowie Goat Widow Express Pebbles Diesel
    Fritter Herer Crack Banner Monkey Cookies Posion Cake
  )

  def generate() do
    adjective = @adjectives |> Enum.random()
    noun = @nouns |> Enum.random()

    [adjective, noun] |> Enum.join(" ")
  end
end
