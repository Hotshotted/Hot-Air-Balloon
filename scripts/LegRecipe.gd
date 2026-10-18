class_name LegRecipe
extends RefCounted
## What makes one leg different: its goal and the optional twists (rhythm hazards, a reversing layer, lightning).
## Made by Flights.leg_recipe() from the Flight's seed, so a Flight is the same every time.

var goal := Flights.CLIMB
var kite_beat := false      # kites dip on a beat
var geese := false          # a layer of geese in V formation
var reverse := false        # a layer that reverses its wind on a visible timer
var lightning := false      # periodic lightning with a warning flash
var storm_speed := 0.0      # Rising Storm: px/s
var leg_index := 0

func twist_count() -> int:
	return int(kite_beat) + int(geese) + int(reverse) + int(lightning)

func describe() -> String:
	var parts: Array[String] = [Flights.GOAL_NAMES[goal]]
	if kite_beat:
		parts.append("kite beat")
	if geese:
		parts.append("geese")
	if reverse:
		parts.append("reversing wind")
	if lightning:
		parts.append("lightning")
	return ", ".join(parts)
