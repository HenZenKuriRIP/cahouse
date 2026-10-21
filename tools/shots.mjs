// Screenshot harness: drives the real build through window.VS and captures every key state at portrait + desktop sizes.
import { chromium } from "playwright"; import path from "node:path"; import fs from "node:fs"; import { serve, CHROME_ARGS } from "./serve.mjs";
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");
const outDir = path.join(root, "docs/screenshots"); fs.mkdirSync(outDir, { recursive: true });
const Q = process.env.Q || "high"; const only = process.argv[2];
const srv = await serve(path.join(root, "dist"), 4792);
const browser = await chromium.launch({ args: CHROME_ARGS });
const sizes = { portrait: { width: 540, height: 1200 }, desktop: { width: 1280, height: 800 } };
const PILOT = `window.__pilot = setInterval(() => { const g = window.VS; if (!g || !g.battle) return; const b = g.battle, p = b.player; let best = null, bd = 1e9;
  for (const e of b.enemies) { const d = Math.hypot(e.x - p.x, e.y - p.y); if (d < bd) { bd = d; best = e; } }
  const rel = p.y - b.scrollY; g.override = Object.assign({ mx: Math.sin(b.time * 0.8) * 0.7 - p.x / 200, my: rel > -60 ? -0.6 : 0.3, ax: best ? best.x : p.x, ay: best ? best.y : p.y - 150, aimActive: true, fire: true, fire2: !!best && bd < 200, dash: false, overload: false }, window.__extra || {}); }, 30);`;
for (const [name, vp] of Object.entries(sizes)) {
  if (only && only !== name) continue;
  const page = await browser.newPage({ viewport: vp, hasTouch: name === "portrait", deviceScaleFactor: 1 });
  page.on("pageerror", (e) => console.log("[pageerror] " + e)); page.on("console", (m) => { if (m.type() === "error") console.log("[console.error] " + m.text()); });
  const shot = async (n) => { const f = path.join(outDir, `${name}_${n}.png`); await page.screenshot({ path: f }); console.log("[SHOT] " + path.relative(root, f)); };
  const settle = (ms = 700) => page.waitForTimeout(ms);
  const go = async (lang) => { await page.goto(`http://127.0.0.1:4792/index.html?quality=${Q}&seed=3287&lang=${lang}&touch=${name === "portrait" ? "on" : "off"}`); await page.waitForFunction(() => window.VS, null, { timeout: 120000 }); await settle(1500); };
  const simUntil = (cond, maxMs = 60000) => page.waitForFunction(cond, null, { timeout: maxMs, polling: 100 });
  await go("zh"); await shot("title_zh");
  await page.evaluate(() => window.VS.menus.render()); await page.evaluate(() => { window.VS.r.render(); });
  await go("en"); await shot("title_en");
  // combat
  await page.evaluate(() => { const g = window.VS; g.startRun(); g.battle.player.god = true; window.VS_TS = 3; });
  await page.evaluate(PILOT); await page.evaluate(() => { window.VS.constructor; }); 
  await page.evaluate(() => { const gm = window.VS; gm.__ts = 1; }); 
  await page.evaluate(() => { const GMod = window.VS; GMod.battle.directorPaused = false; });
  await page.evaluate(() => window.VS.setTimeScale(4)); await simUntil(() => window.VS.battle.time > 30, 240000); await page.evaluate(() => window.VS.setTimeScale(1)); await simUntil(() => window.VS.battle.enemies.length >= 4, 60000).catch(() => {}); await shot("combat");
  // overload
  await page.evaluate(() => { window.__extra = { overload: true }; });
  await simUntil(() => window.VS.battle.player.core.coreHeat > 70, 120000); await shot("overload"); await page.evaluate(() => { window.__extra = {}; });
  // synergy: stunned dummies ahead, fire everything
  await page.evaluate(() => { clearInterval(window.__pilot); const g = window.VS, b = g.battle, p = b.player; for (const e of [...b.enemies]) b.removeEnemy(e); b.directorPaused = true;
    const E = b.director.constructor; const proto = Object.getPrototypeOf(b.enemies); void proto; });
  await page.evaluate(() => { const g = window.VS, b = g.battle, p = b.player; const mk = window.__mkEnemy; void mk; });
  await page.evaluate(() => { const g = window.VS; g.spawnDummies(5); window.__syn = setInterval(() => { const b = g.battle, p = b.player; const t = b.enemies[2] || b.enemies[0]; for (const e of b.enemies) { e.stunTimer = 99; e.y = p.y - 110; }
    const k = Math.floor(b.time / 1.3); const sw = k !== window.__sw; window.__sw = k; g.override = { mx: 0, my: 0, ax: t ? t.x : p.x, ay: t ? t.y : p.y - 110, aimActive: true, fire: true, fire2: true, dash: false, overload: false, swap: sw }; }, 30); });
  await page.evaluate(() => window.VS.setTimeScale(2)); await simUntil(() => window.VS.battle.synergy.counts.ion_vortex > 0 && window.VS.battle.wells.some((w) => w.ion), 180000); await page.evaluate(() => window.VS.setTimeScale(1)); await settle(300); await shot("synergy");
  await page.evaluate(() => { clearInterval(window.__syn); const g = window.VS; for (const e of [...g.battle.enemies]) g.battle.removeEnemy(e); g.battle.directorPaused = false; });
  await page.evaluate(PILOT);
  // pause zh / en
  await page.evaluate(() => { window.VS.togglePause(true); }); await page.evaluate(() => { const L = window.VS_LOC; void L; });
  await page.evaluate(() => window.VS.setLang("zh")); await settle(); await shot("pause_zh");
  await page.evaluate(() => window.VS.setLang("en")); await settle(); await shot("pause_en");
  await page.evaluate(() => window.VS.togglePause(false));
  // builder
  await page.evaluate(() => window.VS.openBuilder()); await settle(1200); await shot("builder");
  await page.evaluate(() => { document.querySelector('[data-b="view"]').click(); }); await settle(1500); await shot("builder_3d");
  await page.evaluate(() => { document.querySelector('[data-b="view"]').click(); window.VS.builder.hide(); window.VS.startRun(); window.VS.battle.player.god = true; });
  // victory: short goal so the pilot reaches it quickly, still through the real win path
  await page.evaluate(() => { const g = window.VS; g.battle.goal = 900; g.battle.directorPaused = false; g.battle.player.god = true; window.VS_FAST = true; g.setTimeScale(4); });
  await simUntil(() => window.VS.battle.ended, 180000); await page.evaluate(() => window.VS.setTimeScale(1)); await settle(1600); await shot("victory");
  // game over
  await page.evaluate(() => { const g = window.VS; g.startRun(); clearInterval(window.__pilot); g.override = null; const p = g.battle.player; p.god = false;
    window.__kill = setInterval(() => { if (p.alive) { p.shield = 0; p.takeDamage(20, p.x + 10, p.y - 20); } else clearInterval(window.__kill); }, 120); });
  await simUntil(() => window.VS.battle.ended, 120000); await settle(1800); await shot("gameover");
  await page.close();
}
await browser.close(); srv.close();
