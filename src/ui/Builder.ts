// Ship builder: DOM grid overlay (forward = up) on top of a live three.js preview of the same ShipModel.
import * as THREE from "three";
import { tr } from "../core/Loc";
import { EventBus } from "../core/EventBus";
import { AudioManager } from "../core/AudioManager";
import { ShipModel, CELL, key, unkey } from "../sim/ShipModel";
import { ShipView } from "../render/ShipView";
import { Data } from "../sim/Data";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";
const ORDER = ["core", "cockpit", "main_thruster", "side_thruster", "weapon_mount", "shield_gen", "armor", "radiator"];
const WEAPONS = ["pulse_cannon", "missile_swarm", "gravity_bomb", "emp_launcher"];
export class Builder {
  el: HTMLElement; model: ShipModel; open = false; mode3d = false;
  private gl: THREE.WebGLRenderer | null = null; private scene = new THREE.Scene(); private cam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 500);
  private pcam = new THREE.PerspectiveCamera(35, 1, 0.1, 500); private view = new ShipView(); private raf = 0; private t = 0;
  private drag: { id: string; weapon: string; from: string | null; ghost: HTMLElement; moved: boolean } | null = null;
  private canvas = Object.assign(document.createElement("canvas"), { className: "preview" });
  private tool = "armor"; private msg = "";
  constructor(root: HTMLElement, private onApply: (m: ShipModel) => void, private onClose: () => void) {
    this.el = document.createElement("div"); this.el.id = "builder"; this.el.className = "hidden"; root.appendChild(this.el);
    this.model = ShipModel.fromDefault();
    EventBus.on("language_changed", () => { if (this.open) this.render(); });
    addEventListener("resize", () => { if (this.open) this.layout(); });
  }
  show(current: ShipModel): void {
    this.model = current.clone(); this.open = true; this.el.classList.remove("hidden"); this.msg = tr("BLD_MSG_DRAG");
    this.render(); this.initGL(); this.loop();
  }
  hide(): void { this.open = false; this.el.classList.add("hidden"); cancelAnimationFrame(this.raf); }
  private initGL(): void {
    if (this.gl) { this.layout(); return; }
    this.gl = new THREE.WebGLRenderer({ canvas: this.canvas, antialias: true, alpha: true });
    this.gl.toneMapping = THREE.ACESFilmicToneMapping; this.gl.outputColorSpace = THREE.SRGBColorSpace; this.gl.setPixelRatio(Math.min(2, devicePixelRatio));
    if (!this.scene.environment) {
      const pm = new THREE.PMREMGenerator(this.gl); this.scene.environment = pm.fromScene(new RoomEnvironment(), 0.04).texture; this.scene.environmentIntensity = 0.6;
      this.scene.add(new THREE.HemisphereLight("#9fb6ff", "#0b0f20", 0.8));
      const k = new THREE.DirectionalLight("#EAF4FF", 2.6); k.position.set(-10, 30, 12); this.scene.add(k);
      const r = new THREE.DirectionalLight("#A78BFA", 1.4); r.position.set(14, 6, -20); this.scene.add(r);
      this.scene.add(this.view.group);
    }
    this.layout();
  }
  private layout(): void {
    const stage = this.el.querySelector(".stage") as HTMLElement; if (!stage || !this.gl) return;
    const w = stage.clientWidth, h = stage.clientHeight; this.gl.setSize(w, h, false);
    const G = this.model.gridSize; const cs = Math.floor(Math.min((w - 20) / G, (h - 20) / G, 64)) - 3; stage.style.setProperty("--cs", cs + "px");
    // ortho frustum so one grid cell (CELL world units) == cs+3 CSS px -> 3D modules sit under their DOM cells
    const ppu = (cs + 3) / CELL; const hw = w / 2 / ppu, hh = h / 2 / ppu;
    this.cam.left = -hw; this.cam.right = hw; this.cam.top = hh; this.cam.bottom = -hh; this.cam.updateProjectionMatrix();
    this.pcam.aspect = w / h; this.pcam.updateProjectionMatrix();
  }
  private loop = (): void => {
    if (!this.open || !this.gl) return; this.raf = requestAnimationFrame(this.loop); this.t += 1 / 60;
    const core = this.model.coreCell(); const G = this.model.gridSize;
    // grid centre in ship-local coords (core at origin)
    const cx = ((G - 1) / 2 - core[0]) * CELL, cz = ((G - 1) / 2 - core[1]) * CELL;
    if (!this.mode3d) { this.cam.position.set(cx, 100, cz); this.cam.up.set(1, 0, 0); this.cam.lookAt(cx, 0, cz); this.gl.render(this.scene, this.cam); }
    else { const a = this.t * 0.5; const r = 24; this.pcam.position.set(Math.cos(a) * r, 15, Math.sin(a) * r); this.pcam.lookAt(0, 0, 0); this.gl.render(this.scene, this.pcam); }
  };
  private cellToGrid(r: number, c: number): [number, number] { const G = this.model.gridSize; return [G - 1 - r, c]; }
  render(): void {
    const m = this.model; m.revalidate(); const G = m.gridSize; const defs = Data.modules;
    const cells: string[] = [];
    for (let r = 0; r < G; r++) for (let c = 0; c < G; c++) {
      const [x, y] = this.cellToGrid(r, c); const k = key(x, y); const cell = m.cells.get(k);
      const loose = cell && !m.connected.has(k);
      cells.push(`<div class="gcell ${cell ? "filled" : ""} ${loose ? "loose" : ""}" data-k="${k}" style="${cell ? `border-color:${defs[cell.id].color}88` : ""}">${cell ? `<span style="color:${defs[cell.id].color}">${tr("ABBR_" + cell.id.toUpperCase())}</span>${cell.weapon ? `<span class="mw">${tr("WPNA_" + cell.weapon.toUpperCase())}</span>` : ""}` : ""}</div>`);
    }
    const s = m.stats;
    const stat = (k: string, ...a: any[]) => `<div class="st">${tr(k, ...a)}</div>`;
    const errs = m.errors.map((e) => `<div class="err">✕ ${e === "ERR_DISCONNECTED" ? tr(e, m.looseCount) : e === "ERR_POWER" ? tr(e, -s.power) : tr(e)}</div>`).join("");
    this.el.innerHTML = `<header><h1 class="glow">${tr("BLD_TITLE").replace(" (TAB)", "").replace("（TAB）", "").replace(" (TAB)", "")}</h1><div class="disp" style="color:var(--cyan)">${tr("BLD_FORWARD")}</div></header>
      <div class="palette panel">${ORDER.map((id) => `<div class="pal ${this.tool === id ? "focus" : ""}" data-id="${id}" style="${this.tool === id ? "background:rgba(73,230,212,.16)" : ""}"><div class="ic" style="border-color:${defs[id].color};color:${defs[id].color}">${tr("ABBR_" + id.toUpperCase())}</div><div>${tr("MOD_" + id.toUpperCase())}<small>${defs[id].mass}t · ${defs[id].power > 0 ? "+" : ""}${defs[id].power}⚡</small></div></div>`).join("")}
        <div class="pal" data-id="erase" style="${this.tool === "erase" ? "background:rgba(255,82,104,.18)" : ""}"><div class="ic" style="border-color:var(--red);color:var(--red)">✕</div><div>${tr("BLD_ERASE")}</div></div></div>
      <div class="center"><div class="stage panel"><div class="grid" style="grid-template-columns:repeat(${G},var(--cs))">${cells.join("")}</div></div></div>
      <div class="side panel">${m.isValid() ? `<div class="ok">✓ ${tr("BLD_VALID")}</div>` : errs}
        ${stat("STAT_MASS", s.mass)}${stat("STAT_POWER", s.power)}${stat("STAT_ACCEL", s.accel)}${stat("STAT_SPEED", s.max_speed)}${stat("STAT_TURN", s.turn)}
        ${stat("STAT_HULL", s.hull)}${stat("STAT_SHIELD", s.shield, s.shield_regen)}${stat("STAT_ENERGY", s.energy)}${stat("STAT_COOLING", s.cooling)}${stat("STAT_MOUNTS", s.mounts)}</div>
      <footer><button class="btn primary" data-b="apply" id="bld-apply">${tr("BLD_APPLY")}</button><button class="btn" data-b="reset">${tr("BLD_RESET")}</button>
        <button class="btn ghost" data-b="view">${this.mode3d ? "GRID" : "3D"}</button><div class="msg">${this.msg}<br><small>${tr("BLD_TAP_HINT")}</small></div><button class="btn warn" data-b="close" id="bld-close">${tr("BLD_CLOSE")}</button></footer>`;
    (this.el.querySelector(".grid") as HTMLElement).style.visibility = this.mode3d ? "hidden" : "visible";
    this.view.build(m, { showAll: true, ghostLoose: true });
    this.bind();
    (this.el.querySelector(".stage") as HTMLElement).prepend(this.canvas);
    this.layout();
  }
  private bind(): void {
    this.el.querySelectorAll<HTMLElement>("[data-b]").forEach((b) => b.addEventListener("click", () => {
      AudioManager.play("ui"); const a = b.dataset.b;
      if (a === "apply") { this.model.revalidate(); if (this.model.isValid()) { this.onApply(this.model.clone()); this.msg = tr("BLD_MSG_APPLIED"); AudioManager.play("ui_confirm"); } else this.msg = tr("BLD_MSG_INVALID"); this.render(); }
      else if (a === "reset") { this.model = ShipModel.fromDefault(); this.render(); }
      else if (a === "view") { this.mode3d = !this.mode3d; this.render(); }
      else if (a === "close") this.onClose();
    }));
    this.el.querySelectorAll<HTMLElement>(".pal").forEach((p) => p.addEventListener("pointerdown", (e) => {
      e.preventDefault(); const id = p.dataset.id!; this.tool = id;
      if (id === "erase") { this.render(); return; }
      this.startDrag(e, id, id === "weapon_mount" ? "pulse_cannon" : "", null);
    }));
    this.el.querySelectorAll<HTMLElement>(".gcell").forEach((g) => g.addEventListener("pointerdown", (e) => {
      e.preventDefault(); const k = g.dataset.k!; const c = this.model.cells.get(k);
      if (this.tool === "erase" && c) { this.model.remove(...unkey(k)); this.msg = tr("BLD_MSG_REMOVED"); this.render(); return; }
      if (c) this.startDrag(e, c.id, c.weapon, k);
      else if (this.tool !== "erase") { this.model.place(...unkey(k), this.tool, this.tool === "weapon_mount" ? "pulse_cannon" : ""); this.msg = tr("BLD_MSG_PLACED", tr("MOD_" + this.tool.toUpperCase())); AudioManager.play("ui"); this.render(); }
    }));
  }
  private startDrag(e: PointerEvent, id: string, weapon: string, from: string | null): void {
    const ghost = document.createElement("div"); ghost.className = "dragghost"; ghost.textContent = tr("ABBR_" + id.toUpperCase()); ghost.style.borderColor = Data.modules[id].color; ghost.style.color = Data.modules[id].color;
    ghost.style.left = e.clientX + "px"; ghost.style.top = e.clientY + "px"; document.body.appendChild(ghost);
    const sx = e.clientX, sy = e.clientY;
    this.drag = { id, weapon, from, ghost, moved: false };
    const mv = (ev: PointerEvent) => { if (!this.drag) return; ghost.style.left = ev.clientX + "px"; ghost.style.top = ev.clientY + "px"; if (Math.hypot(ev.clientX - sx, ev.clientY - sy) > 8) this.drag.moved = true;
      this.el.querySelectorAll(".gcell.hover").forEach((x) => x.classList.remove("hover")); const t = document.elementFromPoint(ev.clientX, ev.clientY)?.closest(".gcell"); t?.classList.add("hover"); };
    const up = (ev: PointerEvent) => {
      removeEventListener("pointermove", mv); removeEventListener("pointerup", up); ghost.remove(); const d = this.drag; this.drag = null; if (!d) return;
      const t = document.elementFromPoint(ev.clientX, ev.clientY)?.closest(".gcell") as HTMLElement | null;
      if (!d.moved && d.from) { // tap on placed module: cycle weapon on mounts
        const c = this.model.cells.get(d.from)!; if (c.id === "weapon_mount") { c.weapon = WEAPONS[(WEAPONS.indexOf(c.weapon) + 1) % WEAPONS.length]; this.msg = tr("BLD_MOUNT", tr("WPN_" + c.weapon.toUpperCase())); }
        this.render(); return;
      }
      if (!d.moved) { this.render(); return; }
      if (d.from) this.model.remove(...unkey(d.from));
      if (t) { this.model.place(...unkey(t.dataset.k!), d.id, d.weapon); this.msg = tr("BLD_MSG_PLACED", tr("MOD_" + d.id.toUpperCase())); AudioManager.play("ui"); }
      else if (d.from) this.msg = tr("BLD_MSG_REMOVED");
      this.render();
    };
    addEventListener("pointermove", mv); addEventListener("pointerup", up);
  }
  /** Programmatic edit used by the autotest (same code path as a drop). */
  placeAt(x: number, y: number, id: string, weapon = ""): void { this.model.place(x, y, id, weapon); this.render(); }
}
