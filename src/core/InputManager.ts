// Unified input: keyboard + mouse, gamepad, touch dual sticks (fed by ui/Touch.ts). Produces device-agnostic intents.
export type Device = "kbm" | "pad" | "touch";
export interface Intent { mx: number; my: number; aimDirX: number; aimDirY: number; aimScreen: { x: number; y: number } | null; aimActive: boolean; fire: boolean; fire2: boolean; dash: boolean; overload: boolean; swap: boolean }
type Action = "pause" | "preset1" | "preset2" | "preset3" | "preset4" | "nudgeW" | "nudgeS" | "nudgeE" | "lang" | "builder" | "confirm";
class Input {
  keys = new Set<string>(); mouse = { x: 0, y: 0, l: false, r: false, moved: false };
  device: Device = "kbm";
  touch = { mx: 0, my: 0, ax: 0, ay: 0, aimOn: false, fire2: false, dash: false, overload: false, swap: false, active: false };
  private actions: Action[] = []; private dashLatch = false; private swapLatch = false; private padPrev: boolean[] = [];
  listeners: ((a: Action) => void)[] = [];
  init(el: HTMLElement): void {
    addEventListener("keydown", (e) => {
      if (e.repeat) return; this.device = "kbm"; this.keys.add(e.code);
      const map: Record<string, Action> = { Escape: "pause", KeyP: "pause", Digit1: "preset1", Digit2: "preset2", Digit3: "preset3", Digit4: "preset4", KeyZ: "nudgeW", KeyX: "nudgeS", KeyC: "nudgeE", KeyL: "lang", KeyB: "builder", Enter: "confirm" };
      if (map[e.code]) this.act(map[e.code]);
      if (e.code === "ShiftLeft" || e.code === "ShiftRight") this.dashLatch = true;
      if (e.code === "KeyQ") this.swapLatch = true;
      if (["Space", "Tab"].includes(e.code)) e.preventDefault();
    });
    addEventListener("keyup", (e) => this.keys.delete(e.code));
    addEventListener("blur", () => { this.keys.clear(); this.mouse.l = this.mouse.r = false; });
    el.addEventListener("pointermove", (e) => { if (e.pointerType === "mouse") { this.mouse.x = e.clientX; this.mouse.y = e.clientY; this.mouse.moved = true; this.device = "kbm"; } });
    el.addEventListener("pointerdown", (e) => { if (e.pointerType !== "mouse") return; this.device = "kbm"; this.mouse.x = e.clientX; this.mouse.y = e.clientY; if (e.button === 0) this.mouse.l = true; if (e.button === 2) this.mouse.r = true; });
    addEventListener("pointerup", (e) => { if (e.pointerType !== "mouse") return; if (e.button === 0) this.mouse.l = false; if (e.button === 2) this.mouse.r = false; });
    el.addEventListener("contextmenu", (e) => e.preventDefault());
  }
  act(a: Action): void { this.actions.push(a); for (const l of this.listeners) l(a); }
  onAction(fn: (a: Action) => void): void { this.listeners.push(fn); }
  dash(): void { this.dashLatch = true; }
  private pad(): Gamepad | null { const ps = navigator.getGamepads ? navigator.getGamepads() : []; for (const p of ps) if (p && p.connected) return p; return null; }
  poll(): Intent {
    const k = this.keys; const out: Intent = { mx: 0, my: 0, aimDirX: 0, aimDirY: 0, aimScreen: null, aimActive: false, fire: false, fire2: false, dash: false, overload: false, swap: false };
    out.mx = (k.has("KeyD") || k.has("ArrowRight") ? 1 : 0) - (k.has("KeyA") || k.has("ArrowLeft") ? 1 : 0);
    out.my = (k.has("KeyS") || k.has("ArrowDown") ? 1 : 0) - (k.has("KeyW") || k.has("ArrowUp") ? 1 : 0);
    out.fire = this.mouse.l || k.has("KeyJ"); out.fire2 = this.mouse.r || k.has("KeyK"); out.overload = k.has("Space");
    if (this.mouse.moved && this.device === "kbm") { out.aimScreen = { x: this.mouse.x, y: this.mouse.y }; out.aimActive = true; }
    const p = this.pad();
    if (p) {
      const dz = (v: number) => (Math.abs(v) < 0.18 ? 0 : v);
      const lx = dz(p.axes[0] ?? 0), ly = dz(p.axes[1] ?? 0), rx = dz(p.axes[2] ?? 0), ry = dz(p.axes[3] ?? 0);
      const btn = (i: number) => !!p.buttons[i]?.pressed;
      const any = lx || ly || rx || ry || p.buttons.some((b) => b.pressed);
      if (any) this.device = "pad";
      if (this.device === "pad") {
        out.mx = lx; out.my = ly;
        if (Math.hypot(rx, ry) > 0.3) { out.aimDirX = rx; out.aimDirY = ry; out.aimActive = true; out.aimScreen = null; out.fire = true; }
        out.fire = out.fire || btn(7); out.fire2 = btn(6); out.overload = btn(5);
        const edge = (i: number) => btn(i) && !this.padPrev[i];
        if (edge(0) || edge(4)) this.dashLatch = true;
        if (edge(9)) this.act("pause"); if (edge(12)) this.act("preset1"); if (edge(13)) this.act("preset2"); if (edge(14)) this.act("preset3"); if (edge(15)) this.act("preset4");
        if (edge(1)) this.act("confirm"); if (edge(3)) this.swapLatch = true;
        this.padPrev = p.buttons.map((b) => b.pressed);
      }
    }
    const t = this.touch;
    if (t.active) {
      this.device = "touch";
      out.mx = t.mx; out.my = t.my;
      if (t.aimOn) { out.aimDirX = t.ax; out.aimDirY = t.ay; out.aimActive = true; out.aimScreen = null; out.fire = true; }
      out.fire2 = t.fire2; out.overload = t.overload; if (t.dash) { this.dashLatch = true; t.dash = false; } if (t.swap) { this.swapLatch = true; t.swap = false; }
    }
    out.dash = this.dashLatch; this.dashLatch = false; out.swap = this.swapLatch; this.swapLatch = false;
    return out;
  }
}
export const InputManager = new Input();
export type { Action };
