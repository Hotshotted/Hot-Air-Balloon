// Plays the exported web build in headless Chromium through its real WebGL 2 path (ANGLE / SwiftShader), mid-leg, and checks that the
// wind streaks are really on screen and really moving:
//   node tools/web_streak_check.js build/web [path-to-chrome]
// * the game's own on-device self-test of the streak shader (window.__streaks.probe) passed, and no shader errors were logged,
// * ?streaks=debug draws the streaks bright magenta: enough magenta pixels, and they MOVE between two frames,
// * the normal rendering has clearly more "streak white" than ?streaks=off (the same leg, streaks hidden) and the shader-less CPU
//   fallback (?streaks=cpu) does too.
// Exits non-zero on any failure and prints what it measured.
const path = require('path');
const fs = require('fs');
const http = require('http');
let playwright;
try { playwright = require('playwright-core'); } catch (e) { playwright = require('playwright'); }
const { chromium } = playwright;
const root = path.resolve(process.argv[2] || 'build/web');
const chrome = process.argv[3] || process.env.CHROME_PATH || '/opt/pw-browsers/chromium';
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.ttf': 'font/ttf', '.wav': 'audio/wav' };
const FLIGHTS = [0, 6, 12, 18];   // one mid-leg per region

const srv = http.createServer((q, r) => {
  let p = path.join(root, decodeURIComponent(q.url.split('?')[0]));
  if (p.endsWith('/')) p += 'index.html';
  fs.readFile(p, (e, d) => {
    if (e) { r.writeHead(404); r.end(); return; }
    r.writeHead(200, { 'Content-Type': mime[path.extname(p)] || 'application/octet-stream' });
    r.end(d);
  });
});

srv.listen(0, async () => {
  const port = srv.address().port;
  let failed = false;
  const fail = (m) => { console.error('FAIL: ' + m); failed = true; };
  const browser = await chromium.launch({ executablePath: chrome, args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const analyser = await browser.newPage();   // a blank page used to read pixels back from screenshots
  // magenta pixels, and "streak white" (bright, low-saturation pixels in the layers' band, below the HUD and above the ground)
  const analyse = (buf) => analyser.evaluate(async (b64) => {
    const img = new Image(); img.src = 'data:image/png;base64,' + b64; await img.decode();
    const c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
    const g = c.getContext('2d'); g.drawImage(img, 0, 0);
    const d = g.getImageData(0, 0, c.width, c.height).data;
    const w = c.width, h = c.height;
    const mag = new Uint8Array(w * h);
    let magenta = 0, white = 0;
    const y0 = Math.floor(h * 0.30), y1 = Math.floor(h * 0.72);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4, r = d[i], gg = d[i + 1], bb = d[i + 2];
      if (r > 190 && bb > 190 && gg < 90) { mag[y * w + x] = 1; magenta++; }
      if (y >= y0 && y < y1 && r > 232 && gg > 232 && bb > 232) white++;
    }
    return { magenta, white };
  }, buf.toString('base64'));
  const maskOf = (buf) => analyser.evaluate(async (b64) => {
    const img = new Image(); img.src = 'data:image/png;base64,' + b64; await img.decode();
    const c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
    const g = c.getContext('2d'); g.drawImage(img, 0, 0);
    const d = g.getImageData(0, 0, c.width, c.height).data;
    const out = [];
    for (let i = 0; i < d.length; i += 4) out.push(d[i] > 190 && d[i + 2] > 190 && d[i + 1] < 90 ? 1 : 0);
    return out;
  }, buf.toString('base64'));

  const play = async (flight, flags) => {
    const context = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true });
    const page = await context.newPage();
    const logs = [];
    page.on('console', (m) => logs.push(m.type() + ': ' + m.text()));
    page.on('pageerror', (e) => logs.push('pageerror: ' + e));
    await page.goto(`http://localhost:${port}/index.html?autoplay=${flight}${flags}`);
    await page.waitForFunction(() => { const l = document.getElementById('loader'); return !l || l.style.display === 'none' || l.classList.contains('gone'); }, null, { timeout: 180000 });
    await page.waitForTimeout(5000);
    const a = await page.screenshot();
    await page.waitForTimeout(600);
    const b = await page.screenshot();
    const st = await page.evaluate(() => window.__streaks || null);
    await context.close();
    return { a, b, st, logs };
  };

  try {
    for (const f of FLIGHTS) {
      const tag = 'Flight ' + (f + 1);
      const dbg = await play(f, '&streaks=debug');
      const off = await play(f, '&streaks=off');
      const nrm = await play(f, '');
      const cpu = await play(f, '&streaks=cpu');
      const bad = [].concat(dbg.logs, nrm.logs).filter((l) => /shader|SHADER|GLSL|compile|link/i.test(l) && /error|ERROR|failed/i.test(l));
      const ma = await maskOf(dbg.a), mb = await maskOf(dbg.b);
      let na = 0, nb = 0, fresh = 0;
      for (let i = 0; i < mb.length; i++) { na += ma[i]; nb += mb[i]; if (mb[i] && !ma[i]) fresh++; }
      const moved = nb ? fresh / nb : 0;
      const wOff = (await analyse(off.a)).white, wNrm = (await analyse(nrm.a)).white, wCpu = (await analyse(cpu.a)).white;
      const mBase = Math.max(wOff, 1);
      console.log(JSON.stringify({ flight: f + 1, probe: nrm.st, magenta: [na, nb], movedShare: +moved.toFixed(2), streakWhite: { off: wOff, normal: wNrm, cpu: wCpu } }));
      if (bad.length) fail(tag + ': shader errors in the console: ' + bad.slice(0, 3).join(' | '));
      if (!nrm.st || nrm.st.probe !== 'ok') fail(tag + ': the on-device self-test of the streak shader did not pass (' + JSON.stringify(nrm.st) + ')');
      if (na < 600 || nb < 600) fail(tag + ': ?streaks=debug shows too few streak pixels (' + na + ' / ' + nb + ')');
      if (moved < 0.2) fail(tag + ': the streaks do not move between two frames (' + (moved * 100).toFixed(0) + '% new pixels)');
      if (wNrm < mBase * 1.2 + 150) fail(tag + ': the normal rendering has no more streak white than ?streaks=off (' + wNrm + ' vs ' + wOff + ')');
      if (wCpu < mBase * 1.2 + 150) fail(tag + ': the CPU fallback has no more streak white than ?streaks=off (' + wCpu + ' vs ' + wOff + ')');
    }
    if (!failed) console.log('OK: wind streaks are drawn, visible and moving in every region (shader path and CPU fallback)');
  } catch (e) {
    fail(String(e && e.stack || e));
  }
  await browser.close();
  srv.close();
  process.exit(failed ? 1 : 0);
});
