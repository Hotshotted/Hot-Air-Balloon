# Wind Layers

A Frogger-style hot air balloon game (working title). Side view, low-poly shapes with black outlines.

**Play:** https://hotshotted.github.io/Hot-Air-Balloon/

- **Hold** (finger / mouse / Space) to fire the burner and rise. **Release** to sink slowly. The balloon has buoyancy lag: the air takes a moment to heat and cool.
- The sky is split into horizontal wind layers. Each blows left or right at its own speed (drifting particles, streamers and chevrons show it) and the balloon drifts with the layer it is in. The screen edges wrap.
- Every layer carries hazards that travel with its wind: birds, kites, other balloons, drones. Time your climbs and hold in the gaps.
- **Flights:** each Flight is a fixed chain of 5 legs generated from a seed (the same every time). One tank of propane for the whole Flight: what is left after a leg carries into the next. Failing a leg ends the Flight.
- **Stars per Flight:** 1 for finishing, 1 for finishing with enough propane left (the gold tick on the gauge), 1 for collecting enough of the floating gold coins. Progress toward each is shown under the gauge.
- **Coins** (currency): per leg cleared, per floating coin collected, and a bonus for leftover propane at the end. Score = legs x 100 + a speed bonus for every second under par.

## Variety, not density

Hazard density and wind speed are capped at moderate values (at most 4 hazards per layer, wind 170 px/s, jet stream 250). Difficulty past that comes from variety only.

**Leg goals**, mixed within a Flight (a Flight's five goals are fixed by its seed; a Flight never repeats a goal back to back, and favours the goals it has used least):

| Goal | What you do |
| --- | --- |
| Climb | reach the top (the first Flights are all Climb) |
| Delivery | pick up the mail at a mooring platform (green flag), drop it at another one higher up (red flag), then climb |
| Rising Storm | a storm rises from below at a set pace (it starts 2 s after lift-off); stay above it while climbing |
| Precision Landing | touch down gently on a slowly moving airship over the top; its hull is solid from below, too fast is a hard landing |
| Star Collect | collect every star in the leg before the top counts |

**Player tools** (buttons below the ground line, with charges per leg; touches are handled in `Main._input`, so a second finger works while the first holds the burner). Each is available from the second Flight of its region on and shows a one-line intro the first time:

- **Sandbag** (Alps): drop it for an instant climb burst, 2 per leg.
- **Anchor** (Sahara): hold position for 2 s, 1 per leg.
- **Quick Vent** (Himalayas): dump hot air for a much faster descent, 2 per leg.

**Rhythm hazards** (patterns you can read): geese in V formation (they flap together), kites that dip together on a 2.4 s beat, periodic lightning (a white flash and a blinking column for 1.1 s, then the strike; three columns in a repeating order). **Changing winds:** some layers reverse on a visible countdown (`<> 5`), hazards and all.

**Curriculum** (`Flights.CURRICULUM`): every Flight introduces at most one new idea and its legs only use ideas introduced so far: Climb, Star Collect, kite beat, Delivery, reversing winds, Rising Storm in the Countryside; the Alps add gusts, then the Sandbag, geese, Precision Landing and lightning; the Sahara their thermals and haze, then the Anchor; the Himalayas thin air and the jet stream, then the Quick Vent. A leg has at most two twists (kite beat / geese / reversing wind / lightning) and a storm leg has none besides the storm.

## The world

A map of 4 regions with 6 Flights each. A Flight opens when the one before it is completed; the next region opens at 12 of 18 stars in the current one. The map shows the stars earned per Flight, so replaying for 3 stars is obvious.

| Region | Palette | Hazards | Mechanics |
| --- | --- | --- | --- |
| Countryside | green hills | birds, kites, balloons, drones | gentle winds |
| Alps | icy blue, snow peaks | eagles, cable cars (+ birds, kites) | gusty layers: each layer's wind swells and fades over time |
| Sahara | sand and sunset | vultures, flying carpets (+ balloons, drones) | thermals (columns of strong updraft) and sand haze that hides distant layers |
| Himalayas | dusk purple, dark peaks | eagles, paragliders (+ birds, drones) | thin air (the burner weakens with altitude) and a fast jet-stream top layer |

Difficulty rises across the 6 Flights of a region (more hazard kinds, denser layers, faster winds) and from region to region.

## Postcards

Completing a region's last Flight awards its postcard: a small illustrated card of the region built from primitives, with a title. 3-starring all six Flights of the region upgrades it to a gold postcard (gold frame, corner stars, ribbon). The Postcard Album (button on the map) shows all four; tap one to see it large.

## Shop (cosmetics)

Bought with coins; purely visual (hit circles and flight are never affected). Equipped items show in the game, on the map (the balloon beside the next Flight) and in the shop preview, where you can try an item on before buying.

- **Envelopes:** 10 patterns / colours (Sunset, Candy, Ocean, Mint, Berry, Lemon, Checkers, Forest, Starry, Rainbow) and 3 novelty shapes (Cat, Hot Dog, Fish).
- **Baskets:** Wicker (free), Crate, Bucket, Gondola, Barrel, Cabin.
- **Passengers:** Cat, Dog, Fox, Owl, Raccoon ride in the basket.

A Flight pays about 100 coins, the cheapest item costs 150 (about two Flights) and the full set about 8,300 (some 80 Flights). All prices are in `scripts/Cosmetics.gd`.

## Daily Flight

One special Flight a day (button on the map), seeded by the UTC date: everyone gets the same one that day, in a region that rotates daily, a little harder than the region's mid Flight. The first completion each day pays a bonus (100 coins) plus 10 for every day of the streak (capped at 7 days); missing a day resets the streak. It does not record stars or postcards.

## Ads (stubs)

No SDK yet: a fake "Ad playing" screen stands in (`Ads.gd`, `Hud.show_ad`). All frequency settings are in `Tuning.gd` / the `?tune` panel.

- **Rewarded:** "+50% propane" on the ground at the start of a leg (when the tank is low), and "Retry this leg" after failing one (back to the leg's starting propane, coins and score; coins already paid are not paid twice).
- **Interstitial:** only between Flights (from the result / failed screens, never during play), once every 3 Flights and not before the 3rd Flight.
- The world stands still while an ad is up. `ads_enabled` switches everything off.

## Performance

Everything that repeats is pooled in fixed arrays, built once and drawn during the start-up pre-warm. The sky is drawn with almost no per-shape draw calls (`LaneRender.gd`):

- The backdrop (layer bands, scenery, goal strip, cables) is drawn **once per leg**; the balloon body is redrawn only when its cosmetics change; the burner flame is its own tiny node; sparks redraw only while alive.
- Wind streaks, chevrons and streamers are three **MultiMeshes moved entirely by `shaders/wind.gdshader`**: per frame the script only passes each layer's scroll and direction (two small arrays).
- Hazards, propane tanks and coins are **merged meshes with their outlines included** (`ShapeMesh` / `HazardMeshes`), one MultiMesh per kind; wing flap, kite tails and rotor flicker run in `shaders/hazard.gdshader`. Per frame only each instance's position is written into a pre-allocated buffer.
- Sand haze is **one shader quad** over all layers (`haze.gdshader`), thermals one quad plus one MultiMesh.
- **Hard caps:** 4 hazards per layer, 8 wind streaks / 4 chevrons / 1 streamer per layer, 24 sparks. Hazard density and wind speed are capped at moderate values.

`tests/perf_profile.gd` (run under xvfb with a software GL context) flies the worst leg of each region and reports script time per frame and the renderer's draw calls; the before / after numbers for the dense regions are in `tests/perf_baseline_before.txt` and `tests/perf_baseline_after.txt`:

| | before | after |
| --- | --- | --- |
| script time in `Lanes._draw` per frame | 5.6 - 6.4 ms | 0.15 - 0.19 ms (`LaneRender.update`) |
| draw calls per frame | 540 - 614 | 62 - 70 |
| objects per frame | ~1,000 - 1,280 | ~250 - 290 |

`?perf` shows a rolling frame-time graph (last 120 frames, 16.7 ms and 33 ms lines, frames over 33 ms marked red), the worst frame of the last 3 s, script time per frame in the simulation and in the render update, and how many frames went over 33 ms.

## Debug flags (URL query)

| Flag | Effect |
| --- | --- |
| `?perf` | rolling frame-time graph, worst-frame readout, script time per frame, hitch log, sim-vs-wall clock |
| `?tune` | TUNE button (top-right): live sliders for buoyancy, burner, winds, hazard density, propane...; **Copy values** puts the changed values on the clipboard |
| `?level=N` | start at level N |
| `?god` | hazards cannot hurt |
| `?unlockall` | every region and Flight is open (not saved: drop the flag and the save decides again) |
| `?noprewarm` | skip the start-up pre-warm splash |

In the `?tune` panel: add coins, unlock all regions (every region and Flight, saved at once), 3-star everything (also unlocks everything and awards all postcards), reset save, reset daily, next day (to test streaks), and sliders for every setting above. The screen you are on refreshes at once; no reload needed.

Combine with `&`, e.g. `?tune&perf&level=6`. Active flags are shown next to the build stamp (commit + UTC time, bottom-right).

## Project

- Godot 4.5, Compatibility (GL) renderer, portrait 1080x1920.
- All feel values live in `scripts/Tuning.gd` (an autoload, so the `?tune` panel edits them live).
- Pooling: hazards, pickups, particles and sparks live in fixed arrays filled in place when a level starts; restarting is in place; a start-up pre-warm draws every shape behind a splash. Nothing is allocated while playing (the smoke test checks it).
- CI (`.github/workflows/deploy.yml`): import, headless smoke test (`tests/smoke_test.gd`), web export with a commit-hash name and a stale-page check, deploy to GitHub Pages.
- `tests/balance_sim.gd` is a look-ahead autopilot that plays whole levels, for a feel of the difficulty curve (not run in CI).
