// Title / pause / end screens (DOM). Buttons call back into main via the handlers object.
import { tr, Loc } from "../core/Loc";
import { EventBus } from "../core/EventBus";
import { SaveManager } from "../core/SaveManager";
import { AudioManager } from "../core/AudioManager";
import type { Battle } from "../sim/Battle";
export interface MenuHandlers { start(): void; resume(): void; restart(): void; quit(): void; builder(): void; quality(): void; touch(): void }
export class Menus {
  title: HTMLElement; pause: HTMLElement; end: HTMLElement; isTouch = () => false;
  private lastEnd: { b: Battle; won: boolean } | null = null;
  constructor(root: HTMLElement, private h: MenuHandlers) {
    const mk = (id: string, cls: string) => { const e = document.createElement("div"); e.id = id; e.className = "screen hidden " + cls; root.appendChild(e); return e; };
    this.title = mk("title", ""); this.pause = mk("pause", "dim"); this.end = mk("end", "dim");
    root.addEventListener("click", (e) => {
      const t = (e.target as HTMLElement).closest("[data-a]") as HTMLElement | null; if (!t) return;
      AudioManager.unlock(); AudioManager.play("ui_confirm"); const a = t.dataset.a!;
      if (a === "lang") Loc.toggle();
      else if (a === "flash") { SaveManager.set("reduceFlash", !SaveManager.s.reduceFlash); this.render(); }
      else if (a === "quality") { this.h.quality(); this.render(); }
      else if (a === "touch") { this.h.touch(); this.render(); }
      else (this.h as any)[a]?.();
    });
    EventBus.on("language_changed", () => this.render());
    this.render();
  }
  private opt(a: string, key: string, val: string): string { return `<button class="btn ghost" data-a="${a}">${tr(key, val)}</button>`; }
  private qualityLabel(): string { const q = SaveManager.s.quality; return tr(q === "auto" ? "Q_AUTO" : q === "low" ? "Q_LOW" : q === "med" ? "Q_MED" : "Q_HIGH"); }
  render(): void {
    const best = SaveManager.data.best.distance;
    this.title.innerHTML = `<div class="wrap">
      <div class="logo"><div class="yr disp">${tr("TITLE_YEAR")}</div><h1>VOID<br><em>SIGNAL</em></h1><div class="tag">${tr("TITLE_3D_TAG")}</div></div>
      <div class="menu">
        <button class="btn primary" data-a="start" id="btn-start">${tr("MENU_START")}</button>
        <button class="btn" data-a="builder" id="btn-builder">${tr("MENU_BUILDER")}</button>
        <div class="row"><button class="btn ghost" data-a="lang" id="btn-lang">中文 / EN</button><button class="btn ghost" data-a="quality">${tr("MENU_QUALITY", this.qualityLabel())}</button></div>
        <div class="help">${best > 0 ? tr("RES_BEST", best) + " · " : ""}${this.isTouch() ? tr("TITLE_TOUCH_HELP") : tr("TITLE_CONTROLS")}</div>
      </div></div>`;
    const tmode = SaveManager.s.touch; const tl = tmode === "auto" ? tr("Q_AUTO") : tr(tmode === "on" ? "MENU_ON" : "MENU_OFF");
    this.pause.innerHTML = `<div class="card panel scan"><h1 class="glow">${tr("MENU_PAUSED")}</h1><h2>${tr("MENU_PAUSED_SUB")}</h2>
      <button class="btn primary" data-a="resume" id="btn-resume">${tr("MENU_RESUME")}</button>
      <button class="btn" data-a="restart">${tr("MENU_RESTART")}</button>
      <button class="btn" data-a="builder">${tr("MENU_BUILDER")}</button>
      ${this.opt("lang", "MENU_LANGUAGE", tr("LANG_NAME"))}${this.opt("flash", "MENU_REDUCE_FLASH", tr(SaveManager.s.reduceFlash ? "MENU_ON" : "MENU_OFF"))}
      ${this.opt("quality", "MENU_QUALITY", this.qualityLabel())}${this.opt("touch", "MENU_TOUCH", tl)}
      <button class="btn warn" data-a="quit">${tr("MENU_TITLE")}</button></div>`;
    if (this.lastEnd) this.showEnd(this.lastEnd.b, this.lastEnd.won, false);
  }
  showEnd(b: Battle, won: boolean, show = true): void {
    this.lastEnd = { b, won };
    const t = Math.floor(b.time); const p = b.player;
    this.end.innerHTML = `<div class="card panel scan ${won ? "won" : "lost"}"><h1>${tr(won ? "END_WON_TITLE" : "END_LOST_TITLE")}</h1>
      <h2>${won ? tr("END_WON_SUB", Math.floor(b.distance()), b.kills) : tr("END_LOST_SUB", Math.floor(b.distance()), Math.floor(t / 60), t % 60, b.kills)}</h2>
      <div class="disp" style="color:var(--dim);letter-spacing:.3em;font-size:.8em">${tr("RES_GRADE")}</div><div class="grade" id="grade">${b.grade()}</div>
      <div class="stats">
        <div><span>${tr("RES_DISTANCE")}</span><b>${tr("RES_FMT_M", Math.floor(b.distance()))}</b></div>
        <div><span>${tr("RES_TIME")}</span><b>${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}</b></div>
        <div><span>${tr("RES_KILLS")}</span><b>${b.kills}</b></div><div><span>${tr("RES_SCRAP")}</span><b>${b.scrap}</b></div>
        <div><span>${tr("RES_SYNERGY")}</span><b>${b.synergy.total}</b></div><div><span>${tr("RES_MODULES")}</span><b>${p.ship.destroyedCount}</b></div>
      </div>
      <button class="btn primary" data-a="restart" id="btn-restart">${tr("MENU_RESTART")}</button>
      <button class="btn" data-a="builder">${tr("MENU_BUILDER")}</button>
      <button class="btn warn" data-a="quit">${tr("MENU_TITLE")}</button></div>`;
    if (show) this.show("end");
  }
  clearEnd(): void { this.lastEnd = null; }
  show(which: "title" | "pause" | "end" | "none"): void {
    this.title.classList.toggle("hidden", which !== "title"); this.pause.classList.toggle("hidden", which !== "pause"); this.end.classList.toggle("hidden", which !== "end");
  }
}
