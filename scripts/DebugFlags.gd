class_name DebugFlags
extends RefCounted
## Debug switches, read from the page URL on web (or "--flag=value" user args elsewhere), so a
## suspected cause of a hitch can be switched off from a phone without a new build:
##   ?noprewarm      skip the start-up pre-warm and splash
##   ?perf           show a worst-frame-time readout
##   ?tune           show the on-screen tuning panel (TUNE button, top-right)
##   ?level=N        start at level N
##   ?god            nothing can hurt the balloon (to look at hazards)
##   ?preview=on     debug only: show the drift preview (two dotted paths + ghost hazards). Off by default, never shown to players
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

static func prewarm_enabled() -> bool:
	_load()
	return not noprewarm

static func perf_enabled() -> bool:
	_load()
	return perf

static func preview_enabled() -> bool:
	_load()
	return preview

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
	if unlockall:
		parts.append("unlockall")
	if preview:
		parts.append("preview=on")
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
			"unlockall":
				unlockall = true
			"preview":
				preview = val in ["on", "1", "true", "yes"]
			"v":
				pass  # cache-busting parameter added by the page, not a flag
			_:
				_bad.append(key)
