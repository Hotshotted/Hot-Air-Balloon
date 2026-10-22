class_name DebugFlags
extends RefCounted
## Debug switches, read from the page URL on web (or "--flag=value" user args elsewhere), so a
## suspected cause of a hitch can be switched off from a phone without a new build:
##   ?nosound        no sound at all (to rule the audio out on a phone)
##   ?debug          show the build stamp (it also shows with ?tune and ?perf); never otherwise
##   ?noprewarm      skip the start-up pre-warm and splash
##   ?perf           show a worst-frame-time readout
##   ?tune           show the on-screen tuning panel (TUNE button, top-right)
##   ?level=N        start at level N
##   ?god            nothing can hurt the balloon (to look at hazards)
##   ?preview=on     debug only: show the drift preview (two dotted paths + ghost hazards). Off by default, never shown to players
##   ?streaks=debug  draw the wind streaks bright magenta and thick (to check them on a phone); ?streaks=off hides them, ?streaks=cpu forces the CPU fallback
##   ?autoplay=N     skip the title and fly Flight N (0-23) at once, nothing can hurt the balloon (web checks)
##   ?audiocheck     fly Flight 1 at once with the burner pulsing and a gameplay sound every half second (the web audio check); nothing can hurt the balloon
##   ?unlockall      every region and Flight is open (not saved: drop the flag and the save decides again)
## Combine with "&", e.g.  ?perf&level=5&god
## The active flags are printed under the build stamp.

static var _loaded := false
static var _bad: Array[String] = []    # unknown names (typos), shown in the summary
static var noprewarm := false
static var perf := false
static var tune := false
static var start_level := 1
static var god := false
static var unlockall := false
static var preview := false
static var debug := false
static var nosound := false
static var streaks := ""          # "", "debug" or "off"
static var autoplay := -1          # the Flight to fly at once (web checks), -1 = off
static var audiocheck := false     # the web audio check drives the flight itself

static func prewarm_enabled() -> bool:
	_load()
	return not noprewarm

static func perf_enabled() -> bool:
	_load()
	return perf

static func preview_enabled() -> bool:
	_load()
	return preview

## The build stamp is only for people debugging: ?debug, ?tune or ?perf.
static func sound_off() -> bool:
	_load()
	return nosound

static func stamp_enabled() -> bool:
	_load()
	return debug or tune or perf

static func streaks_mode() -> String:
	_load()
	return streaks

static func audiocheck_enabled() -> bool:
	_load()
	return audiocheck

static func autoplay_flight() -> int:
	_load()
	return autoplay

static func unlockall_enabled() -> bool:
	_load()
	return unlockall

static func tune_enabled() -> bool:
	_load()
	return tune

## One-line description of the active flags ("" when none), shown next to the build stamp.
static func summary() -> String:
	_load()
	var parts: Array[String] = []
	if noprewarm:
		parts.append("noprewarm")
	if perf:
		parts.append("perf")
	if tune:
		parts.append("tune")
	if start_level > 1:
		parts.append("level=%d" % start_level)
	if god:
		parts.append("god")
	if debug:
		parts.append("debug")
	if nosound:
		parts.append("nosound")
	if unlockall:
		parts.append("unlockall")
	if preview:
		parts.append("preview=on")
	if streaks != "":
		parts.append("streaks=" + streaks)
	if autoplay >= 0:
		parts.append("autoplay=%d" % autoplay)
	if audiocheck:
		parts.append("audiocheck")
	for b in _bad:
		parts.append("?" + b)
	return " ".join(parts)

static func _load() -> void:
	if _loaded:
		return
	var args: Array[String] = []
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search")
		if q is String:
			for part in (q as String).trim_prefix("?").split("&", false):
				args.append(part)
	for a in OS.get_cmdline_user_args():
		args.append(a.trim_prefix("--"))
	parse(args)

## Parse "key" / "key=value" strings. Public so tests can feed it.
static func parse(args: Array[String]) -> void:
	_loaded = true
	_bad.clear()
	noprewarm = false
	perf = false
	tune = false
	start_level = 1
	god = false
	unlockall = false
	preview = false
	debug = false
	nosound = false
	streaks = ""
	autoplay = -1
	audiocheck = false
	for a in args:
		var kv := a.split("=", true, 1)
		var key := kv[0].uri_decode().to_lower()
		var val := kv[1].uri_decode().to_lower() if kv.size() > 1 else ""
		match key:
			"noprewarm":
				noprewarm = true
			"perf":
				perf = true
			"tune":
				tune = true
			"level":
				start_level = clampi(int(val), 1, 99)
			"god":
				god = true
			"debug":
				debug = true
			"nosound":
				nosound = true
			"unlockall":
				unlockall = true
			"streaks":
				streaks = val if val in ["debug", "off", "cpu"] else ""
			"audiocheck":
				audiocheck = true
				god = true
			"autoplay":
				autoplay = clampi(int(val), 0, 23)
				god = true
			"preview":
				preview = val in ["on", "1", "true", "yes"]
			"v":
				pass  # cache-busting parameter added by the page, not a flag
			_:
				_bad.append(key)
