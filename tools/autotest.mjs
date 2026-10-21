// Headless Chromium (WebGL via SwiftShader) autotest runner. Usage: node tools/autotest.mjs [portrait|desktop]
import { chromium } from "playwright"; import path from "node:path"; import { serve, CHROME_ARGS } from "./serve.mjs";
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const mode = process.argv[2] || "portrait"; const vp = mode === "desktop" ? { width: 1280, height: 800 } : { width: 540, height: 1200 };
const srv = await serve(path.join(root, "dist"), 4791);
const browser = await chromium.launch({ args: CHROME_ARGS });
const page = await browser.newPage({ viewport: vp, hasTouch: mode !== "desktop", deviceScaleFactor: 1 });
const errors = [];
page.on("console", (m) => { const t = m.text(); if (t.startsWith("[AUTOTEST]")) console.log(t); else if (m.type() === "error") { errors.push(t); console.log("[console.error] " + t); } });
page.on("pageerror", (e) => { errors.push(String(e)); console.log("[pageerror] " + e); });
const url = `http://127.0.0.1:4791/index.html?autotest=1&god=1&timescale=${process.env.TS || 6}&quality=${process.env.Q || "low"}`;
console.log("[RUNNER] " + url + " viewport=" + vp.width + "x" + vp.height);
await page.goto(url);
await page.waitForFunction(() => window.__autotest && window.__autotest.done, null, { timeout: 600000, polling: 500 });
// Browser-level multi-touch through CDP (independent of the in-page synthetic PointerEvents)
let cdpOk = "skipped";
if (mode !== "desktop") {
  const cdp = await page.context().newCDPSession(page);
  await page.evaluate(() => { const g = window.VS; g.startRun(); g.touch.setEnabled(true); g.battle.directorPaused = true; window.__x0 = g.battle.player.x; window.__s0 = g.battle.player.weapons.find((w) => w.id === "pulse_cannon").shots; });
  const L = { x: 110, y: vp.height * 0.75, id: 1 }, R = { x: vp.width - 110, y: vp.height * 0.75, id: 2 };
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [L, R] });
  for (let i = 1; i <= 8; i++) { await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ ...L, x: L.x + i * 10 }, { ...R, y: R.y - i * 10 }] }); await page.waitForTimeout(30); }
  await page.waitForTimeout(1500);
  const st = await page.evaluate(() => { const g = window.VS; return { moved: g.battle.player.x - window.__x0, shots: g.battle.player.weapons.find((w) => w.id === "pulse_cannon").shots - window.__s0, ev: g.touch.events, mx: window.VS_INPUT ? 0 : 0 }; });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  const ok = st.moved > 10 && st.shots > 0;
  cdpOk = ok ? "OK" : "FAIL";
  console.log(`[AUTOTEST] CHECK touch_cdp_multitouch ${cdpOk} moved=${st.moved.toFixed(1)} shots=${st.shots} events=${JSON.stringify(st.ev)}`);
}
const r = await page.evaluate(() => ({ pass: window.__autotest.pass, n: window.__autotest.results.length, fails: window.__autotest.results.filter((x) => !x.ok).map((x) => x.name) }));
const pass = r.pass && cdpOk !== "FAIL" && errors.length === 0;
console.log(`[RUNNER] ${pass ? "PASS" : "FAIL"} in-page=${r.pass} checks=${r.n} fails=${JSON.stringify(r.fails)} cdp_touch=${cdpOk} console_errors=${errors.length}`);
await browser.close(); srv.close(); process.exit(pass ? 0 : 1);
