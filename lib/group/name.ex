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

  def generate(max_id \\ 99) do
    adjective = @adjectives |> Enum.random()
    noun = @nouns |> Enum.random()
    id = :rand.uniform(max_id)

    [adjective, noun, id] |> Enum.join(" ")
  end
end
