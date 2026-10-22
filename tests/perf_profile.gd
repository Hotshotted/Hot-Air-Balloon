extends SceneTree
## Profile the worst-case leg of each region:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 540x960 --script res://tests/perf_profile.gd -- [frames=240] [regions=0,1,2,3]
## Needs a real (software) GL context so the draw-call counters are meaningful; headless gives script timings only.
## Per region it flies the last leg of the region's last Flight (densest hazards, fastest winds, all mechanics) with the
## burner held, and reports: time per frame in the simulation (Main.sim) and in Lanes._draw (script cost of building the
## draw commands), the split of _draw by part, and the renderer's draw calls / objects per frame.

func _initialize() -> void:
	await process_frame
	var sv = root.get_node("Save")
	sv.persist = false
	sv.reset_all()
	var frames := 240
	var regions: Array = [0, 1, 2, 3]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("frames="):
			frames = int(a.substr(7))
		elif a.begins_with("regions="):
			regions = []
			for x in a.substr(8).split(","):
				regions.append(int(x))
	var LanesS = load("res://scripts/Lanes.gd")
	var FlightsS = load("res://scripts/Flights.gd")
	var m = load("res://scenes/main.tscn").instantiate()
	DebugFlags.parse([])
	root.add_child(m)
	await create_timer(0.3).timeout
	while m._warming:   # (the start-up pre-warm must be over: it draws everything at once)
		await process_frame
	var parts: PackedStringArray = LanesS.PROF_NAMES
	var gpu := RenderingServer.get_video_adapter_name()
	print("renderer: %s  (%s)" % [RenderingServer.get_current_rendering_driver_name(), gpu])
	for r in regions:
		var fid: int = FlightsS.id_of(r, 5)
		m.start_flight(fid)
		# the worst leg: the last one
		m.leg = 4
		m._begin_leg()
		m.burn_override = 1
		m.fuel = 1000.0
		DebugFlags.god = true
		LanesS.prof_on = true
		LanesS.prof_us.fill(0.0)
		var sim_us := 0.0
		var sim_max := 0.0
		var frame_ms: Array[float] = []
		var calls: Array[float] = []
		var objs: Array[float] = []
		var hazards := 0
		for i in m.lanes.n_lanes:
			hazards += m.lanes.lane_count[i]
		var n := 0
		while n < frames:
			# keep the balloon flying around the layers so that every layer is the "focus" in turn
			m.balloon.position.y = 330.0 + fposmod(float(n) * 6.0, 1300.0)
			m.balloon.on_ground = false
			var t0 := Time.get_ticks_usec()
			m.sim(1.0 / 60.0)
			var dt := float(Time.get_ticks_usec() - t0)
			sim_us += dt
			sim_max = maxf(sim_max, dt)
			await process_frame
			if n > 10:
				frame_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
				calls.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
				objs.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
			n += 1
		var avg := func(a: Array[float]) -> float:
			var s := 0.0
			for v in a:
				s += v
			return s / maxf(float(a.size()), 1.0)
		var worst := 0.0
		for v in frame_ms:
			worst = maxf(worst, v)
		print("\n== %s, Flight %d leg 5: %d layers, %d hazards ==" % [m.flight_region, fid + 1, m.lanes.n_lanes, hazards])
		print("  script: sim %.0f us/frame (worst %.0f), _draw %.0f us/frame" % [sim_us / frames, sim_max, _sum(LanesS.prof_us) / frames])
		for k in parts.size():
			print("    %-26s %6.0f us" % [parts[k], LanesS.prof_us[k] / frames])
		print("  renderer: %.0f draw calls, %.0f objects per frame; process time avg %.1f ms, worst %.1f ms" % [avg.call(calls), avg.call(objs), avg.call(frame_ms), worst])
	quit()

func _sum(a: PackedFloat32Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s
