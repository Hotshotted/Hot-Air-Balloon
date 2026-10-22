# Wind Layers: style guide

The shared identity of Clear Prop Games (the same system as Pattern Work): **friendly, chunky, high-contrast, sunny**.
A dark navy interface floats over the bright sky; gold means coins and stars, green means go, red means trouble.
The tokens live in `scripts/Style.gd` (copied from Pattern Work); change the token, not the call site.

This guide is extended in phase 2 with the palette, type, shape, buttons, icons, spacing, safe areas and motion tables
and the deviations from Pattern Work. What is already fixed:

## Studio: Clear Prop Games

The studio mark is a three-blade gold propeller with a dark outline and a white hub in a round dark badge with a blue
ring (`Style.draw_mark`, the same drawing as the SVG in `web/shell.html`). The wordmark is `CLEAR PROP GAMES` in the
display face (Fredoka SemiBold) with the middle word in gold (`Style.draw_wordmark`). The mark spins on the loading
pages while the progress bar fills.

## Loading

No raw text ever shows while loading. The web loading page (`web/shell.html`, set as the export's custom HTML shell) is the
brand background (`#0d1a33`), the spinning mark, the wordmark and a bar; a plain message shows only if the game cannot
start. When the engine is up, the in-game pre-warm cover (`Hud.SplashDraw`, its own CanvasLayer above everything) shows the
same mark and a bar over an opaque background, so nothing of the game behind it can show through. The boot splash image
is `assets/splash.png` on the same background colour.

## The build stamp

The commit and build time are for debugging only: they show, small, in the bottom-right corner with `?debug`, `?tune`
or `?perf`, and never otherwise.

## Fonts

Fredoka (display) and Nunito (text), both SIL OFL 1.1; the licence files are in `assets/fonts/`.
