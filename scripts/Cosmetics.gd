class_name Cosmetics
extends RefCounted
## The cosmetic catalogue: envelopes, baskets and passengers. Purely visual (hit circles and physics never
## look at them). Item 0 of each category is the free default. Prices are in coins.
## Typical income: a Flight pays about 100 coins (5 legs x 10, ~9 floating coins x 5, a propane bonus), so the
## cheapest item is about two Flights and the whole set is some 80.

const ENV := 0
const BASKET := 1
const PASSENGER := 2
const CATEGORIES := ["ENVELOPES", "BASKETS", "PASSENGERS"]

## Envelopes: name, price, shape (0 round, 1 cat head, 2 hot dog, 3 fish), pattern (0 centre gore, 1 bands, 2 side gores, 3 gore and bands), colours 1-3.
const ENV_NAMES := ["Classic", "Banded", "Twilight", "Meadow", "Sunset", "Candy", "Lemon", "Berry", "Forest", "Starry", "Rainbow", "Whiskers", "Hot Dog", "Big Fish"]
const ENV_PRICE := [0, 150, 180, 200, 220, 250, 280, 320, 360, 400, 450, 900, 1000, 1100]
const ENV_SHAPE := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3]
const ENV_PATTERN := [0, 1, 0, 1, 3, 1, 0, 3, 1, 2, 3, 0, 0, 0]
const ENV_C1 := [Color("ff5c4d"), Color("3d8bff"), Color("a06bff"), Color("35c98a"), Color("ff9f2e"), Color("ff7aa8"), Color("ffc933"), Color("c04a9a"), Color("2f9a5a"), Color("2d3e8a"), Color("ff5c4d"), Color("ff9f2e"), Color("e0a050"), Color("3d8bff")]
const ENV_C2 := [Color("ffffff"), Color("ffffff"), Color("ffffff"), Color("ffffff"), Color("ffd95c"), Color("ffffff"), Color("ffffff"), Color("ffe0f2"), Color("ffffff"), Color("ffc933"), Color("ffc933"), Color("ffffff"), Color("d9473f"), Color("ff9f2e")]
const ENV_C3 := [Color("ffffff"), Color("ffffff"), Color("ffffff"), Color("ffffff"), Color("ffffff"), Color("ffffff"), Color("ffffff"), Color("ffffff"), Color("ffffff"), Color("ffffff"), Color("ffffff"), Color("ffffff"), Color("ffc933"), Color("ffffff")]

const BASKET_NAMES := ["Wicker", "Crate", "Bucket", "Gondola", "Barrel", "Cabin"]
const BASKET_PRICE := [0, 150, 180, 240, 280, 360]

const PASSENGER_NAMES := ["Nobody", "Cat", "Dog", "Fox", "Owl", "Raccoon"]
const PASSENGER_PRICE := [0, 200, 220, 260, 300, 340]

static func count(cat: int) -> int:
	return ENV_NAMES.size() if cat == ENV else (BASKET_NAMES.size() if cat == BASKET else PASSENGER_NAMES.size())

static func item_name(cat: int, i: int) -> String:
	return ENV_NAMES[i] if cat == ENV else (BASKET_NAMES[i] if cat == BASKET else PASSENGER_NAMES[i])

static func price(cat: int, i: int) -> int:
	return ENV_PRICE[i] if cat == ENV else (BASKET_PRICE[i] if cat == BASKET else PASSENGER_PRICE[i])

## Coins a decent Flight pays: used to sanity-check the prices.
static func typical_flight_coins() -> float:
	return Tuning.legs_per_flight * Tuning.leg_coins + float(Flights.coin_target()) * Tuning.coin_value + 30.0 * Tuning.propane_coins
