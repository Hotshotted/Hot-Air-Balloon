# Wind Layers

A Frogger-style hot air balloon game (working title). Side view, low-poly shapes with black outlines.

**Play:** https://hotshotted.github.io/Hot-Air-Balloon/

- **Hold** (finger / mouse / Space) to fire the burner and rise. **Release** to sink slowly. The balloon has buoyancy lag: the air takes a moment to heat and cool.
- The sky is split into horizontal wind layers. Each blows left or right at its own speed (drifting particles, streamers and chevrons show it) and the balloon drifts with the layer it is in. The screen edges wrap.
- Every layer carries hazards that travel with its wind: birds, kites, other balloons, drones. Time your climbs and hold in the gaps.
- **Flights:** each Flight is a fixed chain of 5 legs generated from a seed (the same every time). One tank of propane for the whole Flight: what is left after a leg carries into the next. Failing a leg ends the Flight.
- **Stars per Flight:** 1 for finishing, 1 for finishing with enough propane left (the gold tick on the gauge), 1 for collecting enough of the floating gold coins. Progress toward each is shown under the gauge.
- **Coins** (currency): per leg cleared, per floating coin collected, and a bonus for leftover propane at the end. Score = legs x 100 + a speed bonus for every second under par.

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
