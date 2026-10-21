// VOID SIGNAL 3D — boot + game loop. Fixed-step simulation (sim/) decoupled from rendering (render/) and DOM UI (ui/).
import "./ui/styles.css";
import { SaveManager } from "./core/SaveManager";
import { Loc, tr } from "./core/Loc";
import { GameManager, Params } from "./core/GameManager";
import { InputManager } from "./core/InputManager";
import { AudioManager } from "./core/AudioManager";
import { EventBus } from "./core/EventBus";
import { Battle } from "./sim/Battle";
import { ShipModel } from "./sim/ShipModel";
import { Assets } from "./render/Assets";
import { Renderer, detectQuality, type Quality } from "./render/Renderer";
import { GameView } from "./render/GameView";
import { Hud } from "./ui/Hud";
import { Touch } from "./ui/Touch";
import { Menus } from "./ui/Menus";
import { Builder } from "./ui/Builder";
import type { PlayerInput } from "./sim/Player";
import { Enemy } from "./sim/Enemy";
import { Data } from "./sim/Data";

const STEP = 1 / 60;
export class Game {
  r: Renderer; view!: GameView; hud!: Hud; touch!: Touch; menus!: Menus; builder!: Builder;
  battle!: Battle; ship: ShipModel; ui: HTMLElement;
  acc = 0; last = performance.now(); fps = 60; frameMs = 16; frames = 0; simSteps = 0;
  override: PlayerInput | null = null; // used by the autotest pilot
  lastIntent: PlayerInput = { mx: 0, my: 0, ax: 0, ay: 0, aimActive: false, fire: false, fire2: false, dash: false, overload: false };
  presetIdx = 3; prevState = "TITLE"; paused = false;
  constructor() {
    this.ui = document.getElementById("ui")!;
    this.r = new Renderer(document.getElementById("gl") as HTMLCanvasElement);
    const saved = SaveManager.data.ship; let ship: ShipModel | null = null;
    if (saved) { try { ship = ShipModel.fromDict(saved); if (!ship.isValid()) ship = null; } catch { ship = null; } }
    this.ship = ship ?? ShipModel.fromDefault();
  }
  qualityPref(): Quality { const q = (Params.quality || SaveManager.s.quality) as string; return q === "low" || q === "med" || q === "high" ? q : detectQuality(this.r.gl); }
  init(): void {
    this.r.setQuality(this.qualityPref());
    this.view = new GameView(this.r);
    this.touch = new Touch(this.ui, () => this.togglePause(), () => this.cyclePreset());
    this.hud = new Hud(this.ui, this.view);
    this.menus = new Menus(this.ui, {
      start: () => this.startRun(), resume: () => this.togglePause(false), restart: () => this.startRun(), quit: () => this.toTitle(),
      builder: () => this.openBuilder(), quality: () => this.cycleQuality(), touch: () => this.cycleTouch(),
    });
    this.menus.isTouch = () => this.touchEnabled();
    this.builder = new Builder(this.ui, (m) => { this.ship = m; SaveManager.data.ship = m.toDict(); SaveManager.save(); }, () => this.closeBuilder());
    document.getElementById("pausebtn")!.addEventListener("click", () => this.togglePause());
    InputManager.init(document.body);
    InputManager.onAction((a) => this.onAction(a));
    addEventListener("resize", () => { this.r.resize(); });
    addEventListener("pointerdown", () => AudioManager.unlock(), { once: false });
    addEventListener("keydown", (e) => { AudioManager.unlock(); if (GameManager.state === "TITLE" && (e.code === "Enter" || e.code === "Space")) this.startRun(); if (e.code === "F3") this.hud.showPerf = !this.hud.showPerf; if (e.code === "Tab") { e.preventDefault(); this.builder.open ? this.closeBuilder() : this.openBuilder(); } });
    document.addEventListener("visibilitychange", () => { if (document.hidden && GameManager.state === "PLAYING") this.togglePause(true); });
    EventBus.on("run_ended", (won) => { const d = Math.floor(this.battle.distance()); if (d > SaveManager.data.best.distance) { SaveManager.data.best.distance = d; SaveManager.save(); } setTimeout(() => this.menus.showEnd(this.battle, won), Params.autotest ? 0 : 900); });
    EventBus.on("core_overheated", () => AudioManager.play("overheat"));
    this.touch.setEnabled(false);
    this.newBattle(true);
    if (Params.skipTitle) this.startRun(); else this.toTitle();
    requestAnimationFrame(this.loop);
  }
  // ---- helpers used by tools/shots.mjs and debugging (window.VS)
  setLang(l: string): void { Loc.set(l, false); }
  setTimeScale(t: number): void { GameManager.timeScale = t; }
  spawnDummies(n: number): void {
    const b = this.battle, p = b.player;
    for (let i = 0; i < n; i++) { const e = new Enemy(b, "interceptor", Data.enemies.interceptor, p.x + (i - (n - 1) / 2) * 14, p.y - 110, 77 + i); e.hp = 5000; e.stunTimer = 99; e.age = 1; b.enemies.push(e); }
  }
  touchEnabled(): boolean { const t = Params.touch || SaveManager.s.touch; if (t === "on" || t === "1") return true; if (t === "off" || t === "0") return false; return matchMedia("(pointer: coarse)").matches || "ontouchstart" in window; }
  newBattle(attract: boolean): void {
    this.battle?.dispose();
    this.battle = new Battle(GameManager.runSeed, this.ship.clone()); this.battle.attract = attract;
    if (attract) { this.battle.player.god = true; }
    this.view.attach(this.battle); this.hud.attach(this.battle); this.presetIdx = 3;
  }
  startRun(): void {
    AudioManager.unlock(); this.menus.clearEnd(); GameManager.newRun();
    this.newBattle(false); this.menus.show("none"); this.hud.el.classList.remove("hidden");
    this.touch.setEnabled(this.touchEnabled()); this.paused = false; GameManager.state = "PLAYING";
  }
  toTitle(): void {
    GameManager.state = "TITLE"; this.paused = false; this.newBattle(true); this.menus.clearEnd(); this.menus.render(); this.menus.show("title");
    this.hud.el.classList.add("hidden"); this.touch.setEnabled(false);
  }
  togglePause(force?: boolean): void {
    const st = GameManager.state; if (st !== "PLAYING" && st !== "PAUSED") return;
    const want = force ?? st === "PLAYING";
    GameManager.state = want ? "PAUSED" : "PLAYING"; this.menus.render(); this.menus.show(want ? "pause" : "none"); this.touch.el.classList.toggle("hidden", want || !this.touch.enabled);
    if (!want) this.touch.reset();
  }
  openBuilder(): void {
    if (this.builder.open) return; this.prevState = GameManager.state; if (GameManager.state === "PLAYING") GameManager.state = "PAUSED";
    this.menus.show("none"); this.touch.el.classList.add("hidden"); this.builder.show(this.prevState === "TITLE" ? this.ship : this.battle.player.ship.isValid() ? this.ship : this.ship);
    GameManager.state = "BUILDER";
  }
  closeBuilder(): void {
    this.builder.hide();
    if (this.prevState === "TITLE") this.toTitle();
    else if (this.prevState === "ENDED") { GameManager.state = "ENDED"; this.menus.show("end"); }
    else { this.startRun(); } // applying a design mid-run restarts the sortie with the new ship
  }
  cycleQuality(): void {
    const order = ["auto", "low", "med", "high"] as const; const cur = SaveManager.s.quality; const nx = order[(order.indexOf(cur) + 1) % order.length];
    SaveManager.set("quality", nx); this.applyQuality(this.qualityPref());
  }
  applyQuality(q: Quality): void { this.r.setQuality(q); }
  cycleTouch(): void { const o = ["auto", "on", "off"] as const; SaveManager.set("touch", o[(o.indexOf(SaveManager.s.touch) + 1) % 3]); Params.touch = ""; }
  cyclePreset(): void { this.presetIdx = (this.presetIdx + 1) % 4; this.battle.player.core.applyPresetIndex(this.presetIdx); }
  onAction(a: string): void {
    const st = GameManager.state;
    if (a === "lang") { Loc.toggle(); return; }
    if (a === "pause") { if (this.builder.open) this.closeBuilder(); else this.togglePause(); return; }
    if (a === "builder") { this.builder.open ? this.closeBuilder() : this.openBuilder(); return; }
    if (st !== "PLAYING") return;
    const c = this.battle.player.core;
    if (a.startsWith("preset")) { this.presetIdx = Number(a.slice(6)) - 1; c.applyPresetIndex(this.presetIdx); }
    if (a === "nudgeW") c.nudge(0); if (a === "nudgeS") c.nudge(1); if (a === "nudgeE") c.nudge(2);
  }
  intent(): PlayerInput {
    if (this.override) { const o = { ...this.override }; this.override.swap = false; this.override.dash = false; return o; }
    const i = InputManager.poll(); const p = this.battle.player;
    let ax = 0, ay = 0;
    if (i.aimScreen) { const w = this.view.unproject(i.aimScreen.x, i.aimScreen.y); ax = w.x; ay = w.y; }
    else if (i.aimActive) { ax = p.x + i.aimDirX * 120; ay = p.y + i.aimDirY * 120; }
    return { mx: i.mx, my: i.my, ax, ay, aimActive: i.aimActive, fire: i.fire, fire2: i.fire2, dash: i.dash, overload: i.overload, swap: i.swap };
  }
  step(dt: number): void {
    const st = GameManager.state;
    if (st === "PLAYING" || st === "TITLE" || st === "ENDED") {
      const inp = st === "PLAYING" ? this.intent() : { mx: 0, my: st === "TITLE" ? -0.15 : 0, ax: 0, ay: 0, aimActive: false, fire: false, fire2: false, dash: false, overload: false };
      this.lastIntent = inp;
      this.battle.update(dt, inp); if (st === "PLAYING") GameManager.runTime += dt; this.simSteps++;
    }
  }
  loop = (now: number): void => {
    requestAnimationFrame(this.loop);
    const real = Math.min(0.1, (now - this.last) / 1000); this.last = now;
    this.frameMs = this.frameMs * 0.9 + real * 1000 * 0.1; this.fps = 1000 / Math.max(1, this.frameMs); this.frames++;
    if (this.builder.open) return;
    const ts = GameManager.timeScale; this.acc += real * ts; let n = 0;
    const maxSteps = Math.max(6, Math.ceil(ts * 6));
    while (this.acc >= STEP && n < maxSteps) { this.step(STEP); this.acc -= STEP; n++; }
    if (n >= maxSteps) this.acc = 0;
    const paused = GameManager.state === "PAUSED";
    this.view.update(paused ? 0 : real * Math.min(ts, 2));
    this.r.render();
    if (GameManager.state === "PLAYING" || paused) this.hud.update(this.fps, this.frameMs, this.r.gl.info.render.calls, this.view.particles.alive);
  };
}

async function boot(): Promise<void> {
  SaveManager.load(); if (Params.autotest) SaveManager.ephemeral = true;
  Loc.init(); if (Params.lang) Loc.set(Params.lang, false);
  const lt = document.getElementById("loading-text"); if (lt) lt.textContent = tr("LOADING");
  const bar = document.querySelector("#loading .lb i") as HTMLElement | null;
  await Assets.load((f) => { if (bar) bar.style.width = f * 100 + "%"; });
  await document.fonts?.ready;
  const g = new Game(); g.init();
  document.getElementById("loading")?.remove();
  (window as any).VS = g;
  if (Params.autotest) { const { runAutotest } = await import("./test/Autotest"); runAutotest(g); }
}
boot().catch((e) => { console.error("[BOOT] failed", e); const l = document.getElementById("loading"); if (l) l.textContent = "BOOT ERROR: " + e; });
