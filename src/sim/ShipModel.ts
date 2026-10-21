// Data-driven modular ship (port of ship_model.gd): grid, connectors, validation, stats, module damage.
import { Data } from "./Data";
import type { V } from "../core/V2";
export const DIRS: Record<string, [number, number]> = { N: [0, -1], E: [1, 0], S: [0, 1], W: [-1, 0] };
const OPP: Record<string, string> = { N: "S", E: "W", S: "N", W: "E" };
export const CELL = 3; // world units per grid cell (same as Godot CELL_PX)
export interface Cell { id: string; weapon: string; hp: number; maxHp: number }
export const key = (x: number, y: number) => x + "," + y;
export const unkey = (k: string): [number, number] => k.split(",").map(Number) as [number, number];
export class ShipModel {
  defs = Data.modules;
  base: any = {};
  gridSize = 7;
  cells = new Map<string, Cell>();
  errors: string[] = [];
  looseCount = 0;
  connected = new Set<string>();
  stats: Record<string, number> = {};
  destroyedCount = 0;
  static fromDict(d: any): ShipModel { const m = new ShipModel(); m.loadDict(d); return m; }
  static fromDefault(): ShipModel { return ShipModel.fromDict(Data.defaultShip); }
  loadDict(d: any): void {
    this.base = d.base; this.gridSize = d.grid_size; this.cells.clear();
    for (const e of d.modules) this.place(e.x, e.y, e.id, e.weapon ?? "");
    this.revalidate();
  }
  toDict(): any {
    const modules = [...this.cells].map(([k, c]) => { const [x, y] = unkey(k); const m: any = { x, y, id: c.id }; if (c.weapon) m.weapon = c.weapon; return m; });
    return { name: "CUSTOM", grid_size: this.gridSize, base: this.base, modules };
  }
  clone(): ShipModel { return ShipModel.fromDict(this.toDict()); }
  inBounds(x: number, y: number): boolean { return x >= 0 && y >= 0 && x < this.gridSize && y < this.gridSize; }
  place(x: number, y: number, id: string, weapon = ""): boolean {
    if (!this.inBounds(x, y) || !this.defs[id]) return false;
    const hp = this.defs[id].hp; this.cells.set(key(x, y), { id, weapon, hp, maxHp: hp }); return true;
  }
  remove(x: number, y: number): void { this.cells.delete(key(x, y)); }
  findFirst(id: string): [number, number] | null { for (const [k, c] of this.cells) if (c.id === id) return unkey(k); return null; }
  coreCell(): [number, number] { return this.findFirst("core") ?? [Math.floor(this.gridSize / 2), Math.floor(this.gridSize / 2)]; }
  links(a: [number, number], b: [number, number]): boolean {
    for (const s in DIRS) {
      if (a[0] + DIRS[s][0] === b[0] && a[1] + DIRS[s][1] === b[1]) {
        return this.defs[this.cells.get(key(...a))!.id].connectors.includes(s) && this.defs[this.cells.get(key(...b))!.id].connectors.includes(OPP[s]);
      }
    }
    return false;
  }
  revalidate(): void {
    this.errors = []; this.connected.clear();
    let cores = 0, cockpits = 0;
    for (const c of this.cells.values()) { if (c.id === "core") cores++; else if (c.id === "cockpit") cockpits++; }
    if (cores === 0) this.errors.push("ERR_NO_CORE"); else if (cores > 1) this.errors.push("ERR_MULTI_CORE");
    if (cockpits === 0) this.errors.push("ERR_NO_COCKPIT");
    if (cores >= 1) {
      const start = this.coreCell(); const queue = [start]; this.connected.add(key(...start));
      while (queue.length) {
        const cur = queue.shift()!;
        for (const s in DIRS) {
          const n: [number, number] = [cur[0] + DIRS[s][0], cur[1] + DIRS[s][1]]; const nk = key(...n);
          if (this.cells.has(nk) && !this.connected.has(nk) && this.links(cur, n)) { this.connected.add(nk); queue.push(n); }
        }
      }
      const loose = this.cells.size - this.connected.size;
      if (loose > 0) { this.errors.push("ERR_DISCONNECTED"); this.looseCount = loose; }
    }
    let thrusters = 0;
    for (const k of this.connected) {
      const c = this.cells.get(k)!; const d = this.defs[c.id];
      if (c.id === "main_thruster") {
        const [x, y] = unkey(k); const e = DIRS[d.exhaust];
        if (this.cells.has(key(x + e[0], y + e[1]))) this.errors.push("ERR_EXHAUST"); else thrusters++;
      }
    }
    if (thrusters === 0) this.errors.push("ERR_NO_THRUST");
    this.computeStats();
    if (this.stats.power < 0) this.errors.push("ERR_POWER");
  }
  isValid(): boolean { return this.errors.length === 0; }
  private computeStats(): void {
    const s: Record<string, number> = { mass: 0, power: 0, thrust: 0, turn: this.base.turn ?? 100, shield: 0, shield_regen: 0, energy: 0, cooling: 0, hull: this.base.hull ?? 50, mounts: 0 };
    for (const k of this.connected) {
      const c = this.cells.get(k)!; const d = this.defs[c.id];
      s.mass += d.mass; s.power += d.power;
      if (c.id === "main_thruster") { const [x, y] = unkey(k); const e = DIRS[d.exhaust]; if (this.cells.has(key(x + e[0], y + e[1]))) continue; }
      for (const st in d.stats) s[st] = (s[st] ?? 0) + d.stats[st];
      if (c.id === "weapon_mount") s.mounts++;
    }
    const mass = Math.max(1, s.mass);
    s.accel = s.thrust / mass * (this.base.accel_per_thrust ?? 0.6) * 4;
    s.max_speed = 60 + s.thrust / mass * (this.base.max_speed_per_thrust ?? 0.17) * 4;
    s.turn = s.turn * 6 / (mass * 0.5 + 3);
    this.stats = s;
  }
  activeCells(cat: string): string[] { return [...this.connected].filter((k) => this.cells.get(k)!.id === cat); }
  localPos(k: string): V { const [x, y] = unkey(k); const c = this.coreCell(); return { x: (x - c[0]) * CELL, y: (y - c[1]) * CELL }; }
  mountFacing(k: string): number {
    const [x, y] = unkey(k); const c = this.coreCell(); const ox = x - c[0], oy = y - c[1];
    if (Math.hypot(ox, oy) < 0.01) return 0;
    const a = Math.atan2(oy, ox); let d = (0 - a) % (Math.PI * 2); if (d > Math.PI) d -= Math.PI * 2; if (d < -Math.PI) d += Math.PI * 2;
    return a + d * 0.5;
  }
  mountArc(k: string): number { return ((this.defs[this.cells.get(k)!.id].arc ?? 360) * Math.PI) / 180; }
  damageFrom(dir: V, amount: number, hullRatio: number): string {
    let best: string | null = null; let bestScore = -Infinity; const l = Math.hypot(dir.x, dir.y) || 1;
    for (const k of this.connected) {
      const d = this.defs[this.cells.get(k)!.id];
      if (d.protected && hullRatio >= 0.3) continue;
      const p = this.localPos(k); const score = (p.x * dir.x + p.y * dir.y) / l + Math.hypot(p.x, p.y) * 0.2;
      if (score > bestScore) { bestScore = score; best = k; }
    }
    if (!best) return "";
    const cell = this.cells.get(best)!; cell.hp -= amount;
    if (cell.hp <= 0) { this.cells.delete(best); this.destroyedCount++; this.revalidate(); return cell.id; }
    return "";
  }
  extentRadius(): number { let r = 3; for (const k of this.connected) { const p = this.localPos(k); r = Math.max(r, Math.hypot(p.x, p.y) + 2); } return r; }
}
