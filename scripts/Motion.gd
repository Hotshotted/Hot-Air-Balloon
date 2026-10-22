class_name Motion
extends RefCounted
## Screen and element motion on the shared timings (docs/style.md): forward navigation slides in from the right and fades,
## back slides in from the left; things arriving ease out (cubic), popups and stars overshoot (back). Used for UI only (a few
## short tweens when a screen changes); nothing here runs during play.

const SLIDE := 110.0

## A screen arrives: it slides in (from the right when dir > 0, from the left when dir < 0) and fades in over T_BASE.
static func enter(ctrl: Control, dir: int = 1) -> void:
	_kill(ctrl)
	var rest: float = ctrl.get_meta("rest_x", 0.0)
	ctrl.position.x = rest + float(dir) * SLIDE
	ctrl.modulate.a = 0.0
	var tw := ctrl.create_tween()
	ctrl.set_meta("mtw", tw)
	tw.set_parallel(true)
	tw.tween_property(ctrl, "position:x", rest, Style.T_BASE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ctrl, "modulate:a", 1.0, Style.T_BASE * 0.8)
	Sfx.ui("whoosh")

## A popup / card appears with an overshoot (scale about its centre) and fades in.
static func pop(ctrl: Control, delay: float = 0.0, dur: float = Style.T_BASE) -> void:
	_kill(ctrl)
	ctrl.pivot_offset = ctrl.size * 0.5
	ctrl.scale = Vector2(0.6, 0.6)
	ctrl.modulate.a = 0.0
	var tw := ctrl.create_tween()
	ctrl.set_meta("mtw", tw)
	tw.set_parallel(true)
	tw.tween_property(ctrl, "scale", Vector2.ONE, dur).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(ctrl, "modulate:a", 1.0, dur * 0.5).set_delay(delay)

## Leave `ctrl` at rest (positions, alpha, scale): what a skipped or finished transition looks like.
static func settle(ctrl: Control) -> void:
	_kill(ctrl)
	ctrl.position.x = ctrl.get_meta("rest_x", 0.0)
	ctrl.modulate.a = 1.0
	ctrl.scale = Vector2.ONE if not ctrl.has_meta("rest_scale") else ctrl.get_meta("rest_scale")

static func _kill(ctrl: Control) -> void:
	if ctrl.has_meta("mtw"):
		var old: Tween = ctrl.get_meta("mtw")
		if old != null and old.is_valid():
			old.kill()

static func ease_out_back(t: float) -> float:
	return Style.ease_out_back(t)
