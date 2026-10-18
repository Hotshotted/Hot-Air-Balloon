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

## Envelopes: name, price, shape (0 round, 1 cat head, 2 hot dog, 3 fish), pattern (see BalloonArt), colours 1-3.
const ENV_NAMES := ["Classic", "Sunset", "Candy", "Ocean", "Mint", "Berry", "Lemon", "Checkers", "Forest", "Starry", "Rainbow", "Cat", "Hot Dog", "Fish"]
const ENV_PRICE := [0, 150, 180, 200, 220, 250, 280, 320, 360, 400, 450, 900, 1000, 1100]
const ENV_SHAPE := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3]
const ENV_PATTERN := [0, 3, 2, 3, 1, 5, 0, 4, 2, 6, 3, 0, 0, 0]
const ENV_C1 := [Color(1.0, 0.45, 0.16), Color(1.0, 0.55, 0.2), Color(0.9, 0.2, 0.25), Color(0.2, 0.5, 0.9), Color(0.5, 0.9, 0.75), Color(0.6, 0.25, 0.8), Color(1.0, 0.9, 0.3), Color(0.15, 0.15, 0.2), Color(0.2, 0.6, 0.3), Color(0.15, 0.2, 0.5), Color(0.95, 0.25, 0.25), Color(0.95, 0.6, 0.25), Color(0.9, 0.65, 0.3), Color(0.25, 0.65, 0.9)]
const ENV_C2 := [Color(1.0, 0.94, 0.78), Color(1.0, 0.45, 0.7), Color(1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0), Color(0.3, 0.7, 0.6), Color(1.0, 0.6, 0.8), Color(1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0), Color(0.1, 0.35, 0.2), Color(1.0, 0.85, 0.2), Color(1.0, 0.85, 0.2), Color(0.7, 0.35, 0.1), Color(0.85, 0.2, 0.15), Color(1.0, 0.55, 0.2)]
const ENV_C3 := [Color(1, 1, 1), Color(1.0, 0.85, 0.5), Color(1, 1, 1), Color(0.1, 0.3, 0.7), Color(1, 1, 1), Color(1, 1, 1), Color(1, 1, 1), Color(0.9, 0.2, 0.2), Color(0.8, 1.0, 0.8), Color(1, 1, 1), Color(0.3, 0.6, 0.95), Color(1.0, 0.85, 0.85), Color(1.0, 0.85, 0.2), Color(1.0, 1.0, 1.0)]

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
