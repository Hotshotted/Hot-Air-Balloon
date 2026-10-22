# Wind Layers: style guide

One identity for every Clear Prop Games title (the same system as Pattern Work): **friendly, chunky, high-contrast, sunny**.
A dark navy interface floats over the bright sky; gold means coins and stars, green means go, red means trouble. The tokens
live in code in `scripts/Style.gd` (copied from Pattern Work, so both games change together), the drawing helpers in
`scripts/Ui.gd` (labels, buttons, cards) and `scripts/Icons.gd` (the icon set). Change the token, not the call site.

## Palette

| Role | Token | Hex | Use |
|---|---|---|---|
| Primary | `PRIMARY` | `#3d8bff` | brand blue: selection, open Flights, info |
| Primary dark | `PRIMARY_DARK` | `#2459c4` | lip of blue elements |
| Accent | `ACCENT` | `#ffc933` | coins, stars, rewards, the one thing to look at |
| Accent dark | `ACCENT_DARK` | `#c98a0b` | lip of gold elements |
| Success | `SUCCESS` | `#35c98a` | FLY, played Flights, propane, go |
| Success dark | `SUCCESS_DARK` | `#1a8a5a` | lip of the primary button |
| Warning | `WARNING` | `#ff9f2e` | half-empty tank, the sun, flames |
| Danger | `DANGER` | `#ff5c4d` | nearly empty tank, vent, trouble |
| Ink | `INK` | `#0a1020` | outlines, deepest dark |
| Surface dark / 2 | `SURFACE_DARK` / `_2` | `#14213d` / `#1d3157` | cards, sheets; raised or selected surface |
| Surface light / 2 | `SURFACE_LIGHT` / `_2` | `#f3f7ff` / `#d9e5f8` | popups on a light theme (unused so far) |
| Text / soft / quiet | `TEXT` / `TEXT_SOFT` / `TEXT_QUIET` | `#ffffff` / `#bcd0ec` / `#8497b8` | primary, secondary, disabled text |
| Scrim | `SCRIM` | `#060b18` | the shade behind a screen |

`TEXT`, `TEXT_SOFT` and `ACCENT` on `SURFACE_DARK` are at least 4.5:1 (checked by the smoke test). Text always has an ink outline
(size / 8, at least 4 px). Colour is never the only signal: stars and icons carry the meaning too.

## Typography

Fredoka SemiBold (600) for titles, every number and anything 56 px or bigger; Nunito Bold (700) for labels and descriptions.
Both are SIL OFL 1.1 variable fonts (`assets/fonts/`, licences `OFL.txt` and `OFL-Nunito.txt`). `Style.font_for` picks the face.

## Shape

Radii: S 14, M 26 (cards, chips, Flight nodes), L 40 (primary button, sheets), pill 60 (ghost chips). Borders 3 px (light, alpha 0.55).
Shadow: `#030814` 45 %, blur 16, offset (0, 8) on every raised panel. Every card carries a light highlight cap across its top.
Chunky lip: buttons sit on a darker bottom border (10 px on the primary); pressing pushes the face down into it.

## Buttons

Primary (green, lip; FLY, AGAIN-style actions), secondary (dark surface, light border), ghost (translucent round chip, icon only:
previous / next), accent (gold: ad rewards), and the Flight nodes (blue open, green played, gold three stars, dark locked).
`Ui.button(text, size, pos, area, colour, icon)` picks the kind from the legacy colour argument (`Ui.kind_of`), and every
button carries an icon from the set (only the numbered Flight nodes and the shop's item cards have none: the number and the
balloon are their picture). States: normal, hover, pressed (face 5 px into the lip), disabled (flat, greyed).

## Icons

One vector set drawn in code (`Icons.draw`, shown by `IconView`): bold filled silhouettes with an ink outline, round
proportions, no text and no emoji, strokes r / 6 (at least 3 px), two-tone only where colour is the meaning. The same icon
always means the same thing: **stats** coin, star, propane tank, balloon (legs); **actions** play, pause, restart, home, back,
next, check, close, lock, speaker, note, shop, daily, map, album, ad; **tools** sandbag, anchor, vent; **goal types**
climb (arrow), stars, mail, storm, landing; **regions** countryside (hill and sun), Alps (peaks), Sahara (dune and sun),
Himalayas (tall peak with a flag); **shop categories** envelope, basket, passenger.

## Spacing

Scale 8, 16, 24, 40, 64; gutter 30-40. Cards sit 40-60 px in from the screen edge. One primary element per screen.

## Safe areas

`Style.safe_top / bottom / left / right` come from the device (`DisplayServer.get_display_safe_area`) or, in the browser, from the
page's `env(safe-area-inset-*)` (`Style.detect_safe`). The HUD's top readouts move down and the tool buttons (with their touch
areas) move up by the insets (`Ui.apply_safe`); the map, the shop and the album scale and move into the safe rectangle
(`Ui.fit_safe`). The game world and backgrounds still run edge to edge.

## Motion

`T_FAST` 0.12 s (press, release), `T_BASE` 0.30 s (screen transitions), `T_SLOW` 0.50 s (celebrations), `STAGGER` 0.05 s.
Ease-out-cubic for things arriving, ease-in-cubic for things leaving, ease-out-back (overshoot 1.70) for popups and stars.
Forward navigation slides in from the right, back from the left. Nothing moves slower than 0.5 s unless it is a celebration, and
every animation can be skipped.

## Studio: Clear Prop Games

The studio mark is a three-blade gold propeller with a dark outline and a white hub in a round dark badge with a blue ring
(`Style.draw_mark`, the same drawing as the SVG in `web/shell.html`). The wordmark is `CLEAR PROP GAMES` in the display face
with the middle word in gold (`Style.draw_wordmark`). The mark spins on the loading pages while the progress bar fills.

## Loading

No raw text ever shows while loading. The web loading page (`web/shell.html`, the export's custom HTML shell) is the brand
background (`#0d1a33`), the spinning mark, the wordmark and a bar; a plain message shows only if the game cannot start. When
the engine is up, the in-game pre-warm cover (`Hud.SplashDraw`, its own CanvasLayer above everything) shows the same mark and
bar over an opaque background. The boot splash image is `assets/splash.png` on the same colour.

## The build stamp

The commit and build time are for debugging only: they show, small, bottom-right, with `?debug`, `?tune` or `?perf`, and never
otherwise.

## Deviations from Pattern Work

* **More type sizes.** Pattern Work uses three sizes (XL 110, M 56, S 30). This game's flight HUD is dense (gauge, three
  progress readouts, a goal line) on a portrait screen, so it also uses 24-28 px labels, 34-46 px for the top row and 36-44 px in
  buttons; the faces, the outline rule and the colours are the same.
* **Node-built UI.** Pattern Work draws its HUD in one `Control` (`Hud.Art`); this game builds Labels and Buttons once and restyles
  them through `Ui`, because its screens (map, album, shop) are separate scenes of ordinary controls. The look is the same.
* **Aspect.** The viewport is a fixed 1080 x 1920 portrait with the width kept (`stretch aspect = keep`), not `expand`.
* **World art.** The sky, the hazards and the balloon keep their own black-outlined low-poly look (the game's world); only the
  interface (HUD, panels, buttons, icons, loading) is the shared system.
* **The app icon and splash image are drawn for this game** (a balloon rather than an aircraft); the mark, background and rules
  are shared.

## In-game scenery and feedback (Phase 4)

- **Backdrops** are three parallax ridge layers per region (far, middle, near), each one outlined polygon drawn once per leg:
  Countryside rolling hills with field furrows, Alps jagged peaks with snow, Sahara lopsided dunes with a lit crest,
  Himalayas tall ridges in violet haze. Far layers are tinted toward the sky and have a fainter outline; the near layer
  keeps the full black outline. They drift opposite to the wind of the balloon's layer at 5 %, 11 % and 20 % of its speed.
- **Time of day**: the five legs of a Flight run dawn (warm wash) -> midday (clear) -> dusk (violet wash), one full-screen
  gradient over the scenery that is strongest at the horizon. It never covers hazards, pickups or the HUD.
- **Hazards** are the loudest things in the sky: black outlines, saturated fills (a slight saturation boost in the shader).
- **Feedback**: pickups, handoffs and landings burst squares *and* an expanding outlined ring; the passenger cheers; a crash
  empties the envelope (squash, flutter), drops the basket and droops the passenger instead of vanishing.
