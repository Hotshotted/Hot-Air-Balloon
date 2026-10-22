// CI web audio check: the exported game, loaded in Chromium under 4x CPU throttle, must (1) boot without errors, (2) unlock its
// audio context on the first tap, (3) keep the audio clock running in real time (no stalls) and (4) suspend the context when the
// page is hidden / closed / blurred and resume it afterwards.
//   node tools/web_audio_check.mjs http://localhost:8080/
import { chromium } from 'playwright';

const url = process.argv[2] || 'http://localhost:8080/';
const fails = [];
const check = (ok, what) => { console.log((ok ? '  ok   ' : '  FAIL ') + what); if (!ok) fails.push(what); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const browser = await chromium.launch({ args: ['--autoplay-policy=user-gesture-required', '--use-fake-device-for-media-stream'] });
const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => { if (m.type() === 'error' && !/favicon|ERR_FILE_NOT_FOUND|Failed to load resource/.test(m.text())) errors.push(m.text()); });
const cdp = await page.context().newCDPSession(page);
await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });

await page.goto(url, { waitUntil: 'load' });
// the game is up once the engine has created an audio context and the canvas is shown
await page.waitForFunction(() => document.querySelector('canvas') && window.__audioCtxs && window.__audioCtxs.length > 0, null, { timeout: 120000 });
check(true, 'the game boots under 4x CPU throttle and creates its audio context');
const state = () => page.evaluate(() => window.__audioCtxs.map((c) => c.state));
const anyRunning = async () => (await state()).includes('running');

await sleep(1500);
await page.mouse.click(195, 420);   // the first tap
await page.waitForFunction(() => window.__audioCtxs.some((c) => c.state === 'running'), null, { timeout: 15000 }).catch(() => {});
check(await anyRunning(), 'the first tap unlocks the audio context');

// the audio clock keeps up with real time (an audio thread that stalls under load would fall behind)
const t0 = await page.evaluate(() => ({ a: Math.max(...window.__audioCtxs.map((c) => c.currentTime)), w: performance.now() }));
await sleep(3000);
const t1 = await page.evaluate(() => ({ a: Math.max(...window.__audioCtxs.map((c) => c.currentTime)), w: performance.now() }));
const ratio = ((t1.a - t0.a) * 1000) / (t1.w - t0.w);
check(ratio > 0.8 && ratio < 1.2, `the audio clock runs in real time (${ratio.toFixed(2)}x)`);

const fire = async (name, extra) => {
  await page.evaluate(([n, e]) => { eval(e); }, [name, extra]);
  await sleep(600);
};
await fire('hidden', "Object.defineProperty(document, 'hidden', { value: true, configurable: true }); document.dispatchEvent(new Event('visibilitychange'));");
check(!(await anyRunning()), 'hiding the page (visibilitychange) suspends the audio');
await fire('visible', "Object.defineProperty(document, 'hidden', { value: false, configurable: true }); document.dispatchEvent(new Event('visibilitychange'));");
check(await anyRunning(), '...and showing it resumes the audio');
await fire('pagehide', "window.dispatchEvent(new Event('pagehide'));");
check(!(await anyRunning()), 'pagehide suspends the audio');
await fire('pageshow', "window.dispatchEvent(new Event('pageshow'));");
check(await anyRunning(), '...and pageshow resumes it');
await fire('blur', "window.dispatchEvent(new Event('blur'));");
check(!(await anyRunning()), 'losing focus (blur) suspends the audio');
await fire('focus', "window.dispatchEvent(new Event('focus'));");
check(await anyRunning(), '...and focus resumes it');

check(errors.length === 0, 'no page errors' + (errors.length ? ': ' + errors.slice(0, 3).join(' | ') : ''));
await browser.close();
if (fails.length) { console.log('WEB AUDIO CHECK FAILED (' + fails.length + ')'); process.exit(1); }
console.log('WEB AUDIO CHECK PASSED');
