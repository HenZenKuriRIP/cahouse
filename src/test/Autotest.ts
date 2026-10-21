// In-browser autotest (?autotest=1&god=1&timescale=6). Drives the real game loop + real DOM events and prints PASS/FAIL lines.
import type { Game } from "../main";
import { GameManager, Params } from "../core/GameManager";
import { InputManager } from "../core/InputManager";
import { Loc } from "../core/Loc";
import { EventBus } from "../core/EventBus";
import { Assets } from "../render/Assets";
import { Enemy } from "../sim/Enemy";
import { Data } from "../sim/Data";
import type { PlayerInput } from "../sim/Player";
const results: { name: string; ok: boolean; info: string }[] = [];
const log = (s: string) => console.log("[AUTOTEST] " + s);
function check(name: string, ok: boolean, info = ""): void { results.push({ name, ok, info }); log(`CHECK ${name} ${ok ? "OK" : "FAIL"} ${info}`); }
const frame = () => new Promise<void>((r) => requestAnimationFrame(() => r()));
const idle = (): PlayerInput => ({ mx: 0, my: 0, ax: 0, ay: 0, aimActive: false, fire: false, fire2: false, dash: false, overload: false });
async function sim(g: Game, seconds: number, each?: () => void, timeoutMs = 120000): Promise<void> {
  const t0 = g.battle.time; const start = performance.now();
  while (g.battle.time - t0 < seconds && !g.battle.ended) { each?.(); await frame(); if (performance.now() - start > timeoutMs) { log(`WARN sim timeout after ${(g.battle.time - t0).toFixed(1)}s`); break; } }
}
function nearest(g: Game) { const p = g.battle.player; let best: Enemy | null = null; let bd = 1e9; for (const e of g.battle.enemies) { const d = Math.hypot(e.x - p.x, e.y - p.y); if (d < bd) { bd = d; best = e; } } return best; }
function pointer(el: Element, type: string, id: number, x: number, y: number): void {
  el.dispatchEvent(new PointerEvent(type, { pointerId: id, pointerType: "touch", clientX: x, clientY: y, bubbles: true, cancelable: true, isPrimary: id === 11, buttons: type === "pointerup" ? 0 : 1 }));
}
export async function runAutotest(g: Game): Promise<void> {
  const W = window as any; W.__autotest = { done: false, results };
  log(`START seed=${Params.seed} timescale=${GameManager.timeScale} god=${Params.god} gpu="${g.r.gpuName}" quality=${g.r.quality} viewport=${innerWidth}x${innerHeight}`);
  try {
    check("boot_models", Assets.loaded === 18, `glb=${Assets.loaded} tris=${[...Assets.tris.values()].reduce((a, b) => a + b, 0)}`);
    await frame(); await frame();
    check("render_frame", g.r.gl.info.render.calls > 5, `draw_calls=${g.r.gl.info.render.calls} tris=${g.r.gl.info.render.triangles}`);
    check("state_playing", GameManager.state === "PLAYING", GameManager.state);
    const b = () => g.battle; const p = () => g.battle.player;
    b().directorPaused = true;
    // --- movement
    let x0 = p().x; g.override = { ...idle(), mx: 1 }; await sim(g, 1.0);
    const dxR = p().x - x0; x0 = p().x; g.override = { ...idle(), mx: -1 }; await sim(g, 2.0);
    check("movement", dxR > 20 && p().x - x0 < -20, `right=${dxR.toFixed(1)} left=${(p().x - x0).toFixed(1)}`);
    const y0 = p().y - b().scrollY; g.override = { ...idle(), my: -1 }; await sim(g, 0.8);
    check("movement_forward", p().y - b().scrollY < y0 - 15, `rel_y ${y0.toFixed(0)} -> ${(p().y - b().scrollY).toFixed(0)}`);
    const d0 = p().dashes; g.override = { ...idle(), mx: 1, dash: true }; await sim(g, 0.05); g.override = idle(); await sim(g, 0.5);
    check("dash", p().dashes === d0 + 1, `dashes=${p().dashes}`);
    // --- firing / weapons
    const shots0 = p().weapons.map((w) => w.shots);
    const aim = () => ({ ax: p().x, ay: p().y - 150, aimActive: true });
    g.override = { ...idle(), ...aim(), fire: true, fire2: true }; let maxProj = 0;
    let sw = 0; await sim(g, 4.0, () => { const k = Math.floor(b().time / 1.2); const s = k !== sw; sw = k; g.override = { ...idle(), ...aim(), fire: true, fire2: true, swap: s }; maxProj = Math.max(maxProj, b().projectiles.list.length); });
    g.override = idle();
    const fired = p().weapons.map((w, i) => `${w.id}:${w.shots - shots0[i]}`);
    check("firing", maxProj > 5, `max_live_projectiles=${maxProj} instanced_bullets=${g.view.bullets.count}`);
    check("weapons_all_4", p().weapons.length === 4 && p().weapons.every((w, i) => w.shots > shots0[i]), fired.join(" "));
    check("projectile_pool_reuse", b().projectiles.pool.created < 400, `pool_created=${b().projectiles.pool.created}`);
    // --- synergies: stage stunned high-HP dummies ahead, then fire everything through the real weapon code
    check("synergies_active", b().synergy.active.size === 3, [...b().synergy.active].join(","));
    const syn = async () => {
      for (const e of [...b().enemies]) b().removeEnemy(e);
      for (let i = 0; i < 5; i++) { const e = new Enemy(b(), "interceptor", Data.enemies.interceptor, p().x + (i - 2) * 14, p().y - 120, 99 + i); e.hp = 5000; e.stunTimer = 999; e.age = 1; b().enemies.push(e); }
      let ss = Math.floor(b().time / 1.3); await sim(g, 9.0, () => { const t = b().enemies[2] ?? b().enemies[0]; if (t) { t.stunTimer = 999; for (const e of b().enemies) { e.stunTimer = 999; e.y = p().y - 120; } } const k = Math.floor(b().time / 1.3); const s = k !== ss; ss = k; g.override = { ...idle(), ax: t ? t.x : p().x, ay: t ? t.y : p().y - 120, aimActive: true, fire: true, fire2: true, swap: s }; });
    };
    await syn(); g.override = idle();
    const sc = b().synergy.counts;
    check("synergy_gravity_missile", sc.gravity_missile > 0, `n=${sc.gravity_missile}`);
    check("synergy_emp_crit", sc.emp_crit > 0, `n=${sc.emp_crit}`);
    check("synergy_ion_vortex", sc.ion_vortex > 0, `n=${sc.ion_vortex} wells=${b().wells.length}`);
    W.__autotest.synergyShot = true; await frame();
    for (const e of [...b().enemies]) b().removeEnemy(e);
    // --- energy presets via real keyboard events
    const c = p().core; const m: Record<string, number> = {};
    for (const [i, name] of ["ASSAULT", "DEFENSE", "ESCAPE", "BALANCED"].entries()) {
      dispatchEvent(new KeyboardEvent("keydown", { code: "Digit" + (i + 1) })); dispatchEvent(new KeyboardEvent("keyup", { code: "Digit" + (i + 1) }));
      await sim(g, 1.5); m[name + "_w"] = c.mult("weapon_damage"); m[name + "_s"] = c.mult("shield_capacity"); m[name + "_e"] = c.mult("engine_accel");
      if (c.presetName !== name) { check("energy_presets", false, `expected ${name} got ${c.presetName}`); }
    }
    check("energy_presets", m.ASSAULT_w > m.BALANCED_w && m.DEFENSE_s > m.BALANCED_s && m.ESCAPE_e > m.BALANCED_e && c.stats.presets >= 4,
      `W ${m.ASSAULT_w.toFixed(2)}>${m.BALANCED_w.toFixed(2)} S ${m.DEFENSE_s.toFixed(2)}>${m.BALANCED_s.toFixed(2)} E ${m.ESCAPE_e.toFixed(2)}>${m.BALANCED_e.toFixed(2)}`);
    // --- overload -> overheat -> lock -> unlock
    const base = c.mult("weapon_damage"); g.override = { ...idle(), overload: true }; let peakMult = 0, peakTotal = 0;
    W.__autotest.overloadShot = false; const oh: { cat: string; locked: boolean; heat: number }[] = [];
    const offOh = EventBus.on("core_overheated", (cat) => { if (!oh.length) oh.push({ cat, locked: c.overloadLocked, heat: c.coreHeat }); });
    await sim(g, 5.0, () => { g.override = { ...idle(), overload: true }; peakMult = Math.max(peakMult, c.mult("weapon_damage")); peakTotal = Math.max(peakTotal, c.total()); if (c.coreHeat > 70 && !W.__autotest.overloadShot) W.__autotest.overloadShot = true; });
    offOh(); const o0 = oh[0];
    check("overheat_disables", !!o0 && o0.locked && o0.cat !== "" && o0.heat === 55, o0 ? `disabled=${o0.cat} locked=${o0.locked} heat_reset=${o0.heat.toFixed(0)}` : "no overheat");
    check("overload", peakTotal >= 1.39 && peakMult > base && c.stats.overheats >= 1, `total=${peakTotal} mult ${base.toFixed(2)}->${peakMult.toFixed(2)} overheats=${c.stats.overheats}`);
    g.override = idle(); await sim(g, 6.0);
    check("overload_unlock", !c.overloadLocked && c.disabledCategory === "", `heat=${c.coreHeat.toFixed(0)}`);
    // --- touch dual stick via real dispatched PointerEvents into the touch layer
    g.override = null; g.touch.setEnabled(true); const tel = g.touch.el; const H = innerHeight, Wd = innerWidth;
    p().x = 0; p().vx = 0; await sim(g, 0.1); const pulse = p().weapons.find((w) => w.id === "pulse_cannon")!; const tx0 = p().x; const sh0 = pulse.shots;
    pointer(tel, "pointerdown", 11, Wd * 0.2, H * 0.75); pointer(tel, "pointermove", 11, Wd * 0.2 + 80, H * 0.75);
    pointer(tel, "pointerdown", 12, Wd * 0.8, H * 0.75); pointer(tel, "pointermove", 12, Wd * 0.8, H * 0.75 - 80);
    const mxSeen = InputManager.touch.mx; const aimSeen = InputManager.touch.aimOn;
    W.__autotest.touchShot = true; await sim(g, 1.2); W.__autotest.touchShot = false;
    const moved = p().x - tx0; const shot = pulse.shots - sh0;
    pointer(tel, "pointerup", 11, Wd * 0.2 + 80, H * 0.75); pointer(tel, "pointerup", 12, Wd * 0.8, H * 0.75 - 80);
    const dashBtn = tel.querySelector('[data-k="dash"]')!; const dd = p().dashes; const r = dashBtn.getBoundingClientRect();
    pointer(dashBtn, "pointerdown", 13, r.x + 5, r.y + 5); pointer(dashBtn, "pointerup", 13, r.x + 5, r.y + 5); await sim(g, 0.3);
    check("touch_dual_stick", mxSeen > 0.5 && aimSeen && moved > 15 && shot > 0, `mx=${mxSeen.toFixed(2)} aimOn=${aimSeen} moved=${moved.toFixed(1)} shots=${shot} events=${JSON.stringify(g.touch.events)}`);
    check("touch_dash_button", p().dashes === dd + 1, `dashes ${dd}->${p().dashes}`);
    check("touch_release", InputManager.touch.mx === 0 && !InputManager.touch.aimOn, "");
    InputManager.touch.active = false; g.touch.setEnabled(false);
    // --- language switch (keyboard L) updates DOM text
    const lab = () => (document.querySelector('label[data-k="hull"]') as HTMLElement).textContent;
    const l0 = Loc.language; const t0 = lab();
    dispatchEvent(new KeyboardEvent("keydown", { code: "KeyL" })); dispatchEvent(new KeyboardEvent("keyup", { code: "KeyL" })); await frame();
    const t1 = lab(); const l1 = Loc.language;
    dispatchEvent(new KeyboardEvent("keydown", { code: "KeyL" })); dispatchEvent(new KeyboardEvent("keyup", { code: "KeyL" })); await frame();
    check("language_switch", l0 !== l1 && t0 !== t1 && Loc.language === l0 && /船体|HULL/.test(t0 + t1), `${l0}:"${t0}" -> ${l1}:"${t1}" -> ${Loc.language}`);
    // --- pause via DOM button
    (document.getElementById("pausebtn") as HTMLElement).click(); await frame();
    const pausedOk = GameManager.state === "PAUSED" && !document.getElementById("pause")!.classList.contains("hidden");
    (document.getElementById("btn-resume") as HTMLElement).click(); await frame();
    check("pause_resume", pausedOk && GameManager.state === "PLAYING", "");
    // --- full run to the goal with an autopilot (enemies on). Tracks chunk bounds.
    b().directorPaused = false; let maxChunks = 0, maxRocks = 0, maxEnemies = 0; const startT = performance.now();
    const pilot = () => {
      const e = nearest(g); const pl = p(); const rel = pl.y - b().scrollY;
      let mx = Math.sin(b().time * 0.7) * 0.6 - pl.x / 200; const my = rel > -150 ? -1 : 0.2;
      for (const a of b().field.rocks) if (a.alive && Math.abs(a.x - pl.x) < a.r + 14 && a.y < pl.y && a.y > pl.y - 60) mx += a.x > pl.x ? -1 : 1;
      g.override = { ...idle(), mx, my, ax: e ? e.x : pl.x, ay: e ? e.y : pl.y - 150, aimActive: true, fire: true, fire2: !!e, dash: false, overload: false };
      maxChunks = Math.max(maxChunks, b().field.chunks.size); maxRocks = Math.max(maxRocks, b().field.rocks.length); maxEnemies = Math.max(maxEnemies, b().enemies.length);
    };
    await sim(g, 400, pilot, 240000);
    const f = b().field;
    check("chunks_bounded", maxChunks <= 6 && maxRocks < 120, `max_chunks=${maxChunks} max_rocks=${maxRocks} destroyed=${f.destroyed} ore_det=${f.oreDetonations} ore_chain=${f.oreChains} meteors=${f.meteorsSpawned} scrap=${b().scrap}`);
    check("enemies", b().director.spawnedTotal > 20 && b().kills > 5 && maxEnemies <= 60, `spawned=${b().director.spawnedTotal} kills=${b().kills} max_alive=${maxEnemies} culled=${b().director.culledTotal}`);
    await frame(); await frame();
    check("win", b().ended && b().won && b().distance() >= Params.goal && !document.getElementById("end")!.classList.contains("hidden"),
      `dist=${Math.floor(b().distance())} t=${b().time.toFixed(1)}s grade=${b().grade()} real=${((performance.now() - startT) / 1000).toFixed(1)}s`);
    W.__autotest.winShot = true; await frame(); await frame();
    // --- lose: restart through the DOM button and kill the ship for real (god off)
    (document.getElementById("btn-restart") as HTMLElement).click(); await frame();
    p().god = false; g.override = idle(); b().directorPaused = true;
    await sim(g, 6, () => { const pl = p(); if (pl.alive) { pl.shield = 0; pl.takeDamage(25, pl.x, pl.y - 20); } });
    await frame(); await frame();
    check("lose", b().ended && !b().won && !p().alive && !document.getElementById("end")!.classList.contains("hidden") && document.querySelector("#end .lost") !== null, `hull=${p().hull.toFixed(0)} modules_lost=${p().ship.destroyedCount}`);
  } catch (e) { check("exception", false, String((e as Error).stack || e)); }
  g.override = null;
  const fails = results.filter((r) => !r.ok).length;
  log(`RESULT ${fails === 0 ? "PASS" : "FAIL"} ${results.length - fails}/${results.length} sim_steps=${g.simSteps} frames=${g.frames} avg_fps=${g.fps.toFixed(1)}`);
  W.__autotest.done = true; W.__autotest.pass = fails === 0;
}
