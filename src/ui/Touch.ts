// Touch dual-stick controls. Each pointer is tracked by pointerId: left half = floating move stick, right half = aim+fire stick.
import { InputManager } from "../core/InputManager";
import { tr } from "../core/Loc";
import { EventBus } from "../core/EventBus";
interface Stick { id: number; ox: number; oy: number; x: number; y: number; el: HTMLElement; knob: HTMLElement; home: () => [number, number] }
export class Touch {
  el: HTMLElement; enabled = false; move: Stick; aim: Stick; private btns: Record<string, HTMLElement> = {};
  events = { down: 0, move: 0, up: 0 };
  constructor(root: HTMLElement, private onPause: () => void, private onPreset: () => void) {
    this.el = document.createElement("div"); this.el.id = "touch"; this.el.className = "hidden"; root.appendChild(this.el);
    const mk = (cls: string, label: string) => { const e = document.createElement("div"); e.className = "stick idle " + cls; e.innerHTML = `<i></i><label>${label}</label>`; this.el.appendChild(e); return e; };
    const sab = () => parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--sab")) || 0;
    const em = () => parseFloat(getComputedStyle(this.el).fontSize) || 12;
    const me = mk("move", tr("TOUCH_MOVE")), ae = mk("aim", tr("TOUCH_AIM"));
    this.move = { id: -1, ox: 0, oy: 0, x: 0, y: 0, el: me, knob: me.querySelector("i")!, home: () => [em() * 6.5, innerHeight - em() * 7 - sab()] };
    this.aim = { id: -1, ox: 0, oy: 0, x: 0, y: 0, el: ae, knob: ae.querySelector("i")!, home: () => [innerWidth - em() * 6.5, innerHeight - em() * 7 - sab()] };
    const bw = document.createElement("div"); bw.className = "tbtns"; this.el.appendChild(bw);
    for (const [k, key] of [["preset", "TOUCH_PRESET"], ["swap", "TOUCH_SWAP"], ["ovl", "TOUCH_OVL"], ["sec", "TOUCH_SEC"], ["dash", "TOUCH_DASH"]] as const) {
      const b = document.createElement("div"); b.className = "tbtn"; b.dataset.k = k; b.dataset.key = key; b.textContent = tr(key); bw.appendChild(b); this.btns[k] = b;
      b.addEventListener("pointerdown", (e) => { e.stopPropagation(); e.preventDefault(); this.button(k, true); this.events.down++; });
      b.addEventListener("pointerup", (e) => { e.stopPropagation(); this.button(k, false); });
      b.addEventListener("pointercancel", () => this.button(k, false));
    }
    this.el.addEventListener("pointerdown", (e) => this.down(e));
    this.el.addEventListener("pointermove", (e) => this.moveEv(e));
    this.el.addEventListener("pointerup", (e) => this.up(e)); this.el.addEventListener("pointercancel", (e) => this.up(e));
    EventBus.on("language_changed", () => { me.querySelector("label")!.textContent = tr("TOUCH_MOVE"); ae.querySelector("label")!.textContent = tr("TOUCH_AIM"); for (const k in this.btns) this.btns[k].textContent = tr(this.btns[k].dataset.key!); });
    addEventListener("resize", () => this.place());
    this.place();
  }
  private button(k: string, on: boolean): void {
    const t = InputManager.touch; t.active = true;
    if (k === "dash" && on) t.dash = true;
    if (k === "sec") t.fire2 = on;
    if (k === "swap" && on) t.swap = true;
    if (k === "ovl" && on) t.overload = !t.overload;
    if (k === "preset" && on) this.onPreset();
    this.btns[k].classList.toggle("on", k === "ovl" ? t.overload : on && k !== "preset" && k !== "swap");
  }
  setEnabled(on: boolean): void { this.enabled = on; this.el.classList.toggle("hidden", !on); document.body.classList.toggle("touch", on); if (!on) this.reset(); }
  reset(): void { const t = InputManager.touch; t.mx = t.my = t.ax = t.ay = 0; t.aimOn = false; t.fire2 = false; t.overload = false; this.move.id = this.aim.id = -1; this.place(); for (const k in this.btns) this.btns[k].classList.remove("on"); }
  private place(): void { for (const s of [this.move, this.aim]) if (s.id < 0) { const [x, y] = s.home(); s.ox = x; s.oy = y; this.draw(s, x, y); s.el.classList.add("idle"); } }
  private draw(s: Stick, x: number, y: number): void {
    s.el.style.left = s.ox + "px"; s.el.style.top = s.oy + "px";
    s.knob.style.transform = `translate(${x - s.ox}px, ${y - s.oy}px)`;
  }
  private radius(): number { return (parseFloat(getComputedStyle(this.el).fontSize) || 12) * 4; }
  private down(e: PointerEvent): void {
    if (!this.enabled) return; e.preventDefault(); this.events.down++;
    InputManager.touch.active = true;
    const s = e.clientX < innerWidth / 2 ? this.move : this.aim; if (s.id >= 0) return;
    s.id = e.pointerId; s.ox = e.clientX; s.oy = e.clientY; s.x = e.clientX; s.y = e.clientY; s.el.classList.remove("idle"); this.draw(s, s.x, s.y);
    try { this.el.setPointerCapture(e.pointerId); } catch { /* synthetic */ }
    this.apply(s);
  }
  private moveEv(e: PointerEvent): void {
    for (const s of [this.move, this.aim]) if (s.id === e.pointerId) {
      this.events.move++;
      const R = this.radius(); let dx = e.clientX - s.ox, dy = e.clientY - s.oy; const l = Math.hypot(dx, dy);
      if (l > R) { // drag the base along so the stick follows the thumb
        s.ox += (dx / l) * (l - R); s.oy += (dy / l) * (l - R); dx = e.clientX - s.ox; dy = e.clientY - s.oy; }
      s.x = e.clientX; s.y = e.clientY; this.draw(s, s.x, s.y); this.apply(s);
    }
  }
  private up(e: PointerEvent): void {
    for (const s of [this.move, this.aim]) if (s.id === e.pointerId) { this.events.up++; s.id = -1; const t = InputManager.touch; if (s === this.move) { t.mx = t.my = 0; } else { t.aimOn = false; } this.place(); }
  }
  private apply(s: Stick): void {
    const R = this.radius(); const dx = (s.x - s.ox) / R, dy = (s.y - s.oy) / R; const l = Math.hypot(dx, dy); const t = InputManager.touch;
    if (s === this.move) { const k = l < 0.12 ? 0 : Math.min(1, l) / l; t.mx = dx * k; t.my = dy * k; }
    else { if (l > 0.25) { t.ax = dx / l; t.ay = dy / l; t.aimOn = true; } else t.aimOn = false; }
  }
}
