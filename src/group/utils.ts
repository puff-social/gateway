const first = [
  "Blue",
  "Afghan",
  "Bubba",
  "Maui",
  "Golden",
  "White",
  "Pineapple",
  "Fruity",
  "Sour",
  "Apple",
  "Jack",
  "Green",
  "Bruce",
  "Grease",
  "Banana",
  "Tropicana",
  "Durban",
  "Khalifa",
  "Lava",
];

const second = [
  "Dream",
  "Kush",
  "Wowie",
  "Goat",
  "Widow",
  "Express",
  "Pebbles",
  "Diesel",
  "Fritter",
  "Herer",
  "Crack",
  "Banner",
  "Monkey",
  "Cookies",
  "Poison",
  "Cake",
];

export function randomStrain() {
  const randomFirst = first[Math.floor(Math.random() * first.length)];
  const randomSecond = second[Math.floor(Math.random() * second.length)];

  return `${randomFirst} ${randomSecond}`;
}
