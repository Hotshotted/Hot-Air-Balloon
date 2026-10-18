class_name Ads
extends RefCounted
## Ad hooks: STUBS, no SDK yet. show() puts up a fake "Ad playing" screen (Hud.show_ad) for Tuning.ad_fake_seconds
## and calls back with true when the viewer claimed the reward / closed it, false when they backed out.
## A real SDK would replace show() and nothing else.

var hud: Hud
var shown := 0                 # ads put up so far (tests look at it)
var last_kind := ""
var _callback := Callable()

func _init(h: Hud) -> void:
	hud = h
	hud.ad_finished.connect(_on_finished)

## kind: "boost", "retry" or "interstitial".
func show(kind: String, callback: Callable) -> void:
	last_kind = kind
	shown += 1
	_callback = callback
	match kind:
		"boost":
			hud.show_ad("Rewarded ad", "+%d%% propane" % roundi(Tuning.ad_boost_frac * 100.0), Tuning.ad_fake_seconds, "CLAIM", true)
		"retry":
			hud.show_ad("Rewarded ad", "Retry this leg", Tuning.ad_fake_seconds, "CLAIM", true)
		_:
			hud.show_ad("Ad", "Thanks for playing!", Tuning.ad_fake_seconds, "CLOSE", false)

func _on_finished(rewarded: bool) -> void:
	var cb := _callback
	_callback = Callable()
	if cb.is_valid():
		cb.call(rewarded)

func is_showing() -> bool:
	return hud.ad_active
