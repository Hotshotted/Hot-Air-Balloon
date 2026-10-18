# Wind Layers

A Frogger-style hot air balloon game (working title). Side view, low-poly shapes with black outlines.

**Play:** https://hotshotted.github.io/Hot-Air-Balloon/

- **Hold** (finger / mouse / Space) to fire the burner and rise. **Release** to sink slowly. The balloon has buoyancy lag: the air takes a moment to heat and cool.
- The sky is split into horizontal wind layers. Each blows left or right at its own speed (drifting particles, streamers and chevrons show it) and the balloon drifts with the layer it is in. The screen edges wrap.
- Every layer carries hazards that travel with its wind: birds, kites, other balloons, drones. Time your climbs and hold in the gaps.
- Reach the goal line at the top to clear the level: more layers, faster winds, denser hazards. Propane is limited; green tanks float in some layers.
- Score = levels cleared x 100 + a speed bonus for every second under par. Touching a hazard, or landing on an empty tank, ends the attempt.

## Debug flags (URL query)

| Flag | Effect |
| --- | --- |
| `?perf` | worst-frame-time readout, hitch log, sim-vs-wall clock |
| `?tune` | TUNE button (top-right): live sliders for buoyancy, burner, winds, hazard density, propane...; **Copy values** puts the changed values on the clipboard |
| `?level=N` | start at level N |
| `?god` | hazards cannot hurt |
| `?noprewarm` | skip the start-up pre-warm splash |

Combine with `&`, e.g. `?tune&perf&level=6`. Active flags are shown next to the build stamp (commit + UTC time, bottom-right).

## Project

- Godot 4.5, Compatibility (GL) renderer, portrait 1080x1920.
- All feel values live in `scripts/Tuning.gd` (an autoload, so the `?tune` panel edits them live).
- Pooling: hazards, pickups, particles and sparks live in fixed arrays filled in place when a level starts; restarting is in place; a start-up pre-warm draws every shape behind a splash. Nothing is allocated while playing (the smoke test checks it).
- CI (`.github/workflows/deploy.yml`): import, headless smoke test (`tests/smoke_test.gd`), web export with a commit-hash name and a stale-page check, deploy to GitHub Pages.
- `tests/balance_sim.gd` is a look-ahead autopilot that plays whole levels, for a feel of the difficulty curve (not run in CI).
