// DOM HUD: vitals, distance, energy triangle (SVG), weapons, synergies, banners, damage numbers, alerts.
import { tr, Loc } from "../core/Loc";
import { EventBus } from "../core/EventBus";
import { GameManager } from "../core/GameManager";
import type { Battle } from "../sim/Battle";
import type { GameView } from "../render/GameView";
const $ = (sel: string, root: ParentNode = document) => root.querySelector(sel) as HTMLElement;
const TRI = { w: [60, 8], s: [8, 96], e: [112, 96] }; // SVG vertices for W(top) S(bottom-left) E(bottom-right)
export class Hud {
  el: HTMLElement; b: Battle | null = null; private floats: HTMLElement; private banner: HTMLElement; private lastBanner = 0;
  private bars: Record<string, { fill: HTMLElement; ghost: HTMLElement; v: HTMLElement; root: HTMLElement }> = {};
  private synHot: Record<string, number> = {};
  private ftCount = 0; showPerf = false;
  constructor(root: HTMLElement, private view: GameView) {
    this.el = document.createElement("div"); this.el.id = "hud"; root.appendChild(this.el);
    this.el.innerHTML = `
      <div id="vignette"></div><div id="floats"></div><div id="banner"></div><div id="alert"></div><pre id="perf" class="hidden"></pre>
      <div class="top">
        <div class="panel vitals scan">
          ${["hull", "shld", "dash"].map((k) => `<div class="bar ${k}"><label data-k="${k}"></label><div class="track"><div class="ghost"></div><div class="fill"></div><div class="ticks"></div></div><span class="v"></span></div>`).join("")}
        </div>
        <div class="panel progress scan"><div class="dist"></div><div class="ptrack"><i></i></div><div class="meta"><span class="kills"></span><span class="scrap"></span></div></div>
        <div class="pausebtn interactive panel" id="pausebtn" role="button" aria-label="pause"></div>
      </div>
      <div id="weapons" class="panel scan"><div class="wl"></div><div id="synergies"></div></div>
      <div id="energy" class="panel scan">
        <div class="preset"></div>
        <svg viewBox="0 0 120 104">
          <polygon points="60,8 8,96 112,96" fill="rgba(73,230,212,0.05)" stroke="rgba(73,230,212,0.45)" stroke-width="1"/>
          <polygon class="inner" points="60,8 8,96 112,96" fill="none" stroke="rgba(73,230,212,0.14)" stroke-width="0.6" transform="translate(60 66.7) scale(0.5) translate(-60 -66.7)"/>
          <polygon class="share" points="" fill="rgba(73,230,212,0.28)" stroke="#49E6D4" stroke-width="1.4"/>
          <circle class="dot" r="4" fill="#EAF4FF"/>
          <text x="60" y="4" text-anchor="middle" class="lw" fill="#FF5268" font-size="9" font-weight="800"></text>
          <text x="2" y="104" class="ls" fill="#49E6D4" font-size="9" font-weight="800"></text>
          <text x="118" y="104" text-anchor="end" class="le" fill="#FFCC66" font-size="9" font-weight="800"></text>
        </svg>
        <div class="heat"><i></i><b style="left:65%"></b></div>
        <div class="state"></div>
      </div>`;
    for (const k of ["hull", "shld", "dash"]) { const r = $(`.bar.${k}`, this.el); this.bars[k] = { root: r, fill: $(".fill", r), ghost: $(".ghost", r), v: $(".v", r) }; }
    this.floats = $("#floats", this.el); this.banner = $("#banner", this.el);
    EventBus.on("float_text", (x, y, text, color, style) => this.float(x, y, text, color, style));
    EventBus.on("synergy_triggered", (id, x, y) => { this.synHot[id] = performance.now(); this.float(x, y - 10, tr("SYN_" + id.toUpperCase()), "#A78BFA", "syn"); if (this.b && this.b.synergy.counts[id] === 1) this.showBanner(tr("BANNER_SYNERGY", tr("SYN_" + id.toUpperCase())), "syn"); });
    EventBus.on("wave_started", (i) => { if (i > 0) this.showBanner(tr("BANNER_WAVE", i + 1), "warn"); });
    EventBus.on("preset_changed", (n) => this.showBanner(tr("BANNER_PRESET", tr("PRESET_" + n)), ""));
    EventBus.on("language_changed", () => { this.relabel(); this.showBanner(tr("BANNER_LANGUAGE", tr("LANG_NAME")), ""); });
    EventBus.on("player_damaged", () => { const v = $("#vignette", this.el); if (GameManager.reduceFlash) return; v.classList.add("hurt"); setTimeout(() => v.classList.remove("hurt"), 160); });
    EventBus.on("module_destroyed", (id) => { if (this.b) this.float(this.b.player.x, this.b.player.y - 14, tr("FT_MODULE_LOST", tr("MOD_" + id.toUpperCase())), "#FF5268", "syn"); });
    EventBus.on("ship_rebuilt", () => this.buildWeapons());
    this.relabel();
  }
  relabel(): void {
    const l = (k: string, t: string) => { const e = this.el.querySelector(`label[data-k="${k}"]`); if (e) e.textContent = t; };
    l("hull", tr("HUD_HULL")); l("shld", tr("HUD_SHIELD")); l("dash", tr("HUD_DASH"));
    $(".lw", this.el).textContent = tr("EN_W"); $(".ls", this.el).textContent = tr("EN_S"); $(".le", this.el).textContent = tr("EN_E");
    this.buildWeapons();
  }
  attach(b: Battle): void { this.b = b; this.floats.innerHTML = ""; this.synHot = {}; this.buildWeapons(); }
  private buildWeapons(): void {
    if (!this.b) return; const p = this.b.player;
    $(".wl", this.el).innerHTML = p.mounts.map((m, i) => `<div class="wpn" data-i="${i}"><div class="sw" style="background:${m.weapon.data.color};box-shadow:0 0 8px ${m.weapon.data.color}"></div><div class="nm">${tr("WPN_" + m.weapon.id.toUpperCase())}</div><div class="ht"><i style="background:${m.weapon.data.color}"></i></div></div>`).join("");
    $("#synergies", this.el).innerHTML = [...this.b.synergy.active].map((s) => `<div class="syn" data-s="${s}">${tr("SYN_" + s.toUpperCase())}</div>`).join("");
  }
  float(x: number, y: number, text: string, color: string, style: string): void {
    if (this.ftCount > 40) return;
    const s = this.view.project(x, y, 4); if (s.x < -50 || s.y < -50 || s.x > innerWidth + 50 || s.y > innerHeight + 50) return;
    const d = document.createElement("div"); d.className = "ft " + style; d.textContent = text; d.style.color = color; d.style.left = s.x + "px"; d.style.top = s.y + "px";
    this.floats.appendChild(d); this.ftCount++; setTimeout(() => { d.remove(); this.ftCount--; }, 720);
  }
  showBanner(text: string, cls: string): void {
    const now = performance.now(); if (now - this.lastBanner < 300 && cls === "") return; this.lastBanner = now;
    this.banner.innerHTML = ""; const d = document.createElement("div"); d.className = "b " + cls; d.textContent = text; this.banner.appendChild(d);
  }
  update(fps: number, ms: number, draws: number, particles: number): void {
    const b = this.b; if (!b) return; const p = b.player; const c = p.core;
    const set = (k: string, r: number, txt: string) => { const o = this.bars[k]; const t = `scaleX(${Math.max(0, Math.min(1, r))})`; o.fill.style.transform = t; o.ghost.style.transform = t; o.v.textContent = txt; };
    set("hull", p.hull / p.maxHull, String(Math.max(0, Math.ceil(p.hull)))); this.bars.hull.root.classList.toggle("low", p.hull / p.maxHull < 0.3);
    const cap = p.maxShield * c.mult("shield_capacity"); set("shld", cap > 0 ? p.shield / cap : 0, String(Math.round(p.shield)));
    const dcd = 1.2 * c.mult("engine_dash_cooldown"); set("dash", 1 - p.dashCd / dcd, p.dashCd > 0 ? p.dashCd.toFixed(1) : "OK");
    const dist = Math.floor(b.distance()); const goal = b.goal;
    $(".dist", this.el).innerHTML = isFinite(goal) ? `${dist}<small> / ${goal}m</small>` : `${dist}<small>m · ${tr("HUD_ENDLESS")}</small>`;
    ($(".ptrack i", this.el)).style.width = (isFinite(goal) ? Math.min(100, (dist / goal) * 100) : 100) + "%";
    $(".kills", this.el).textContent = tr("HUD_KILLS", b.kills); $(".scrap", this.el).textContent = tr("HUD_SCRAP", b.scrap);
    // energy triangle
    const w = c.current; const pt = (k: "w" | "s" | "e", f: number) => [60 + (TRI[k][0] - 60) * f, 66.7 + (TRI[k][1] - 66.7) * f];
    const k = c.total(); const pts = [pt("w", w[0] * 3 * k / 1.4 * 0.7 + 0.12), pt("s", w[1] * 3 * k / 1.4 * 0.7 + 0.12), pt("e", w[2] * 3 * k / 1.4 * 0.7 + 0.12)];
    $(".share", this.el).setAttribute("points", pts.map((q) => q.join(",")).join(" "));
    const dx = TRI.w[0] * w[0] + TRI.s[0] * w[1] + TRI.e[0] * w[2], dy = TRI.w[1] * w[0] + TRI.s[1] * w[1] + TRI.e[1] * w[2];
    const dot = $(".dot", this.el); dot.setAttribute("cx", String(dx)); dot.setAttribute("cy", String(dy));
    const en = $("#energy", this.el); en.classList.toggle("ovl", c.overloadActive); en.classList.toggle("crit", c.overloadActive && c.isWarning());
    $(".share", this.el).setAttribute("stroke", c.overloadActive ? "#FFCC66" : "#49E6D4"); $(".share", this.el).setAttribute("fill", c.overloadActive ? "rgba(255,204,102,0.3)" : "rgba(73,230,212,0.28)");
    $(".preset", en).textContent = c.overloadActive ? tr("HUD_OVERLOAD", Math.round(c.total() * 100)) : tr("PRESET_" + c.presetName);
    ($(".heat i", en)).style.transform = `scaleX(${c.heatRatio()})`;
    $(".state", en).textContent = c.overloadLocked ? tr("HUD_OVERLOAD_LOCKED") : `${tr("HUD_CORE")} ${Math.round(c.coreHeat)}°`;
    const alert = $("#alert", this.el);
    if (c.disabledCategory) alert.textContent = tr("HUD_OVERHEAT_WARN", tr("MOD_" + c.disabledCategory.toUpperCase()), Math.ceil(c.disabledTimer));
    else if (c.overloadActive && c.isWarning()) alert.textContent = tr("HUD_HEAT_CRITICAL"); else alert.textContent = "";
    $("#vignette", this.el).classList.toggle("ovl", c.overloadActive && !GameManager.reduceFlash);
    // weapons
    const rows = this.el.querySelectorAll<HTMLElement>(".wpn"); const off = c.isDisabled("weapon_mount");
    p.mounts.forEach((m, i) => { const r = rows[i]; if (!r) return; (r.querySelector(".ht i") as HTMLElement).style.transform = `scaleX(${m.weapon.heatRatio()})`; r.classList.toggle("oh", m.weapon.overheated); r.classList.toggle("off", off); });
    const now = performance.now();
    this.el.querySelectorAll<HTMLElement>(".syn").forEach((s) => s.classList.toggle("hot", now - (this.synHot[s.dataset.s!] ?? -1e9) < 500));
    const perf = $("#perf", this.el); perf.classList.toggle("hidden", !this.showPerf);
    if (this.showPerf) perf.textContent = tr("PERF_TEXT", fps, ms, b.enemies.length, b.projectiles.list.length, b.projectiles.pool.available, draws, (performance as any).memory ? (performance as any).memory.usedJSHeapSize / 1048576 : 0, particles, b.field.chunks.size);
    void Loc;
  }
}
