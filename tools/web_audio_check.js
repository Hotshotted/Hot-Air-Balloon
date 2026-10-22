// Plays the exported web build (?audiocheck: Flight 1, burner pulsing, a gameplay sound every half second) in headless Chromium under
// 4x CPU throttle and analyses the audio it actually produces: every AudioNode connection to a context's destination is tee'd into an
// AudioWorklet that measures the real output block by block.
//   node tools/web_audio_check.js build/web [path-to-chrome]
// Fails on: silence while playing, clicks (sample jumps), dropouts (all-zero blocks mid-sound), repeated buffers (identical blocks
// back to back), clipping, any sound while the page is hidden or after it comes back (until Resume is tapped), no sound after Resume,
// a gameplay one-shot peaking above the music/ambience mix, and page errors.
const path = require('path');
const fs = require('fs');
const http = require('http');
let playwright;
try { playwright = require('playwright-core'); } catch (e) { playwright = require('playwright'); }
const { chromium } = playwright;
const root = path.resolve(process.argv[2] || 'build/web');
const chrome = process.argv[3] || process.env.CHROME_PATH || '/opt/pw-browsers/chromium';
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.ttf': 'font/ttf', '.wav': 'audio/wav' };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const srv = http.createServer((q, r) => {
  let p = path.join(root, decodeURIComponent(q.url.split('?')[0]));
  if (p.endsWith('/')) p += 'index.html';
  fs.readFile(p, (e, d) => {
    if (e) { r.writeHead(404); r.end(); return; }
    r.writeHead(200, { 'Content-Type': mime[path.extname(p)] || 'application/octet-stream' });
    r.end(d);
  });
});

// Runs in the page before anything else: tee every context's output into a measuring worklet.
const INIT = `(() => {
  const Ctor = window.AudioContext;
  const worklet = \`
    class Meter extends AudioWorkletProcessor {
      constructor() { super(); this.phase = 'boot'; this.s = {}; this.prev = 0; this.last = null; this.same = 0;
        this.port.onmessage = (e) => { if (e.data.phase) { this.phase = e.data.phase; } if (e.data.report) { this.port.postMessage({ report: this.s }); } }; }
      st() { return this.s[this.phase] || (this.s[this.phase] = { blocks: 0, peak: 0, rms2: 0, n: 0, clicks: 0, zeroBlocks: 0, repeats: 0, clipped: 0, maxJump: 0 }); }
      process(inputs) {
        const ch = inputs[0] && inputs[0][0];
        const st = this.st(); st.blocks++;
        if (!ch) { st.zeroBlocks++; return true; }
        let allZero = true, same = this.last !== null;
        for (let i = 0; i < ch.length; i++) {
          const x = ch[i], a = Math.abs(x);
          if (x !== 0) { allZero = false; }
          if (this.last !== null && x !== this.last[i]) { same = false; }
          if (a > st.peak) { st.peak = a; }
          if (a >= 0.999) { st.clipped++; }
          st.rms2 += x * x; st.n++;
          const j = Math.abs(x - this.prev); if (j > st.maxJump) { st.maxJump = j; }
          if (j > 0.30) { st.clicks++; }
          this.prev = x;
        }
        if (allZero) { st.zeroBlocks++; }
        if (same && !allZero) { st.repeats++; }
        this.last = Float32Array.from(ch);
        return true;
      }
    }
    registerProcessor('meter', Meter);\`;
  window.__meters = [];
  function Wrapped() {
    const c = new (Function.prototype.bind.apply(Ctor, [null].concat([].slice.call(arguments))))();
    const m = { ctx: c, node: null, report: null, ready: false };
    window.__meters.push(m);
    c.audioWorklet.addModule(URL.createObjectURL(new Blob([worklet], { type: 'text/javascript' }))).then(() => {
      m.tee = c.createGain(); m.tee.gain.value = 1;
      m.node = new AudioWorkletNode(c, 'meter', { numberOfOutputs: 0 });
      m.node.port.onmessage = (e) => { if (e.data.report) { m.report = e.data.report; } };
      m.tee.connect(m.node); m.ready = true;
      if (window.__phase) { m.node.port.postMessage({ phase: window.__phase }); }
    });
    return c;
  }
  Wrapped.prototype = Ctor.prototype;
  window.AudioContext = Wrapped;
  const orig = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function (dest) {
    const r = orig.apply(this, arguments);
    const m = window.__meters.find((q) => q.ctx === this.context);
    if (m && dest === this.context.destination) {
      const hook = () => { if (m.ready) { orig.call(this, m.tee); } else { setTimeout(hook, 20); } };
      hook();
    }
    return r;
  };
  window.__setPhase = (p) => { window.__phase = p; window.__meters.forEach((m) => { if (m.node) { m.node.port.postMessage({ phase: p }); } }); };
  window.__collect = () => { window.__meters.forEach((m) => { if (m.node) { m.node.port.postMessage({ report: true }); } }); };
})();`;

srv.listen(0, async () => {
  const port = srv.address().port;
  const fails = [];
  const check = (ok, what) => { console.log((ok ? '  ok   ' : '  FAIL ') + what); if (!ok) fails.push(what); };
  const browser = await chromium.launch({ executablePath: chrome, args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=user-gesture-required'] });
  const page = await browser.newPage({ viewport: { width: 540, height: 960 } });
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error' && !/favicon|ERR_FILE_NOT_FOUND|Failed to load resource|GPU stall|WebGL/.test(m.text())) errors.push(m.text()); });
  await page.addInitScript(INIT);
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });

  await page.goto(`http://localhost:${port}/?audiocheck`, { waitUntil: 'load' });
  await page.waitForFunction(() => window.__pw && window.__pw.screen === 6 /* PLAY */ || (window.__pw && window.__pw.screen !== undefined && window.__pw.screen !== 0), null, { timeout: 180000 });
  await page.waitForFunction(() => window.PWAudio && window.PWAudio.enabled && window.__meters.every((m) => m.ready), null, { timeout: 60000 });
  check(true, 'the game boots under 4x CPU throttle into the check flight');
  await sleep(1500);
  const states = () => page.evaluate(() => window.__meters.map((m) => m.ctx.state));
  const pw = () => page.evaluate(() => ({ paused: window.__pw.paused, held: window.__pw.held }));

  // 1. play: the first tap unlocks, then 14 s of burner pulses and one-shots
  await page.evaluate(() => window.__setPhase('boot'));
  await page.mouse.click(270, 480);
  await page.waitForFunction(() => window.__meters.some((m) => m.ctx.state === 'running'), null, { timeout: 15000 }).catch(() => {});
  check((await states()).includes('running'), 'the first tap unlocks the audio');
  await sleep(2500);
  await page.evaluate(() => window.__setPhase('play'));
  await sleep(14000);
  // 2. hidden
  await page.evaluate(() => { window.__setPhase('hiding'); Object.defineProperty(document, 'hidden', { value: true, configurable: true }); document.dispatchEvent(new Event('visibilitychange')); });
  await sleep(1500);
  await page.evaluate(() => window.__setPhase('hidden'));
  const hiddenState = await states(); const hiddenPw = await pw();
  await sleep(3000);
  // 3. visible again, no Resume yet
  await page.evaluate(() => { window.__setPhase('returning'); Object.defineProperty(document, 'hidden', { value: false, configurable: true }); document.dispatchEvent(new Event('visibilitychange')); });
  await sleep(1000);
  await page.evaluate(() => window.__setPhase('visible'));
  const visState = await states(); const visPw = await pw();
  await sleep(3000);
  // 4. Resume
  await page.evaluate(() => window.__setPhase('resuming'));
  await page.mouse.click(270, 337);   // the RESUME button (540 x 960 is half the 1080 x 1920 design size)
  await sleep(2500);
  await page.evaluate(() => window.__setPhase('resumed'));
  await sleep(6000);
  await page.evaluate(() => { window.__setPhase('end'); window.__collect(); });
  await sleep(1500);
  const reports = await page.evaluate(() => window.__meters.map((m) => ({ page: !!(m.ctx.__pw), report: m.report })));

  const merge = (phase, sel) => {
    const o = { blocks: 0, peak: 0, rms2: 0, n: 0, clicks: 0, zeroBlocks: 0, repeats: 0, clipped: 0, maxJump: 0 };
    reports.filter(sel).forEach((r) => { const s = r.report && r.report[phase]; if (!s) return; o.blocks += s.blocks; o.peak = Math.max(o.peak, s.peak); o.rms2 += s.rms2; o.n += s.n; o.clicks += s.clicks; o.zeroBlocks += s.zeroBlocks; o.repeats += s.repeats; o.clipped += s.clipped; o.maxJump = Math.max(o.maxJump, s.maxJump); });
    return o;
  };
  const isPage = (r) => r.page, isGodot = (r) => !r.page;
  const db = (x) => (x > 0 ? (20 * Math.log10(x)).toFixed(1) : '-inf') + ' dB';
  const pagePlay = merge('play', isPage), godotPlay = merge('play', isGodot);
  const pageRms = Math.sqrt(pagePlay.rms2 / Math.max(pagePlay.n, 1));
  console.log(`measured (play, 14 s): page mix peak ${pagePlay.peak.toFixed(3)} (${db(pagePlay.peak)}), rms ${pageRms.toFixed(4)}, clicks ${pagePlay.clicks} (max jump ${pagePlay.maxJump.toFixed(3)}), zero blocks ${pagePlay.zeroBlocks}/${pagePlay.blocks}, repeats ${pagePlay.repeats}, clipped ${pagePlay.clipped}`);
  console.log(`measured (play): engine one-shots peak ${godotPlay.peak.toFixed(3)} (${db(godotPlay.peak)}), clicks ${godotPlay.clicks} (max jump ${godotPlay.maxJump.toFixed(3)}), clipped ${godotPlay.clipped}, repeats ${godotPlay.repeats}`);

  check(pagePlay.blocks > 1000 && pageRms > 0.01, `the music and ambience play (rms ${pageRms.toFixed(3)})`);
  check(pagePlay.zeroBlocks === 0, `no dropouts in the looping layers (${pagePlay.zeroBlocks} silent blocks)`);
  check(pagePlay.clicks === 0 && godotPlay.clicks === 0, `no clicks (page ${pagePlay.clicks}, one-shots ${godotPlay.clicks}; largest sample jump ${Math.max(pagePlay.maxJump, godotPlay.maxJump).toFixed(3)})`);
  check(pagePlay.repeats === 0 && godotPlay.repeats === 0, `no repeated buffers (${pagePlay.repeats + godotPlay.repeats})`);
  check(pagePlay.clipped === 0 && godotPlay.clipped === 0, `no clipping (peaks ${pagePlay.peak.toFixed(3)} / ${godotPlay.peak.toFixed(3)})`);
  check(godotPlay.peak > 0.005, `the gameplay one-shots are heard (peak ${godotPlay.peak.toFixed(3)})`);
  check(godotPlay.peak < pagePlay.peak * 0.8, `gameplay sounds peak well under the music mix (${db(godotPlay.peak)} vs ${db(pagePlay.peak)})`);

  const hid = merge('hidden', () => true), vis = merge('visible', () => true), res = merge('resumed', isPage);
  check(hid.peak < 1e-4, `silent while the page is hidden (peak ${hid.peak.toExponential(1)})`);
  check(hiddenState.every((s) => s !== 'running') && hiddenPw.paused && hiddenPw.held, `hidden: contexts ${hiddenState.join('/')}, game paused ${hiddenPw.paused}, audio held ${hiddenPw.held}`);
  check(vis.peak < 1e-4, `still silent after the page is visible again, before Resume (peak ${vis.peak.toExponential(1)})`);
  check(visState.every((s) => s !== 'running') && visPw.paused && visPw.held, `visible, not resumed: contexts ${visState.join('/')}, game paused ${visPw.paused}, audio held ${visPw.held}`);
  const resRms = Math.sqrt(res.rms2 / Math.max(res.n, 1));
  check(res.peak > 0.02 && resRms > 0.01, `sound returns after the player taps Resume (peak ${res.peak.toFixed(3)}, rms ${resRms.toFixed(3)})`);
  check(res.clicks === 0 && res.repeats === 0 && res.clipped === 0, `...cleanly (clicks ${res.clicks}, repeats ${res.repeats}, clipped ${res.clipped})`);
  check(errors.length === 0, 'no page errors' + (errors.length ? ': ' + errors.slice(0, 3).join(' | ') : ''));

  await browser.close();
  srv.close();
  if (fails.length) { console.log('WEB AUDIO CHECK FAILED (' + fails.length + ')'); process.exit(1); }
  console.log('WEB AUDIO CHECK PASSED');
  process.exit(0);
});
