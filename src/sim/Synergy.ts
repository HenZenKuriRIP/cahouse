// Weapon synergy system (port of synergy_system.gd + gravity_well.gd).
import { Data } from "./Data";
import { EventBus } from "../core/EventBus";
import { AudioManager } from "../core/AudioManager";
import type { Battle } from "./Battle";
import type { Enemy } from "./Enemy";
import type { Projectile } from "./Projectiles";
export interface Well { x: number; y: number; r: number; t: number; dur: number; pull: number; dps: number; ion: boolean; stunTick: number; id: number }
let WID = 1;
export class SynergySystem {
  defs = Data.synergies;
  active = new Set<string>();
  counts: Record<string, number> = { gravity_missile: 0, emp_crit: 0, ion_vortex: 0 };
  total = 0;
  constructor(private b: Battle) {}
  refresh(weaponIds: string[]): void {
    this.active.clear();
    for (const id in this.defs) {
      const d = this.defs[id];
      const all = d.weapons.every((w: string) => weaponIds.includes(w));
      const any = d.any_of.length === 0 || d.any_of.some((w: string) => weaponIds.includes(w));
      if (all && any) this.active.add(id);
    }
  }
  trigger(id: string, x: number, y: number): void {
    this.counts[id]++; this.total++;
    EventBus.emit("synergy_triggered", id, x, y);
    if (this.counts[id] === 1 || this.counts[id] % 8 === 0) AudioManager.play("synergy");
  }
  inWell(e: Enemy): Well | null { for (const w of this.b.wells) if ((e.x - w.x) ** 2 + (e.y - w.y) ** 2 < w.r * w.r) return w; return null; }
  onPlayerHit(p: Projectile, e: Enemy): void {
    let dmg = p.damage; let crit = p.crit;
    if (this.active.has("gravity_missile") && p.kind === "missile" && this.inWell(e)) { dmg *= this.defs.gravity_missile.damage_mult; this.trigger("gravity_missile", e.x, e.y); }
    if (this.active.has("emp_crit") && (p.kind === "bullet" || p.kind === "missile") && e.empTimer > 0) {
      const base = p.data ? p.data.damage * (p.crit ? 1 : 1) : dmg; void base;
      if (!crit) dmg = dmg * this.defs.emp_crit.crit_mult; else dmg = dmg / (p.data?.critical_multiplier ?? 2) * this.defs.emp_crit.crit_mult;
      crit = true; this.trigger("emp_crit", e.x, e.y);
    }
    if (p.kind === "bomb" || p.kind === "emp") return; // area effect handles damage
    e.takeDamage(dmg, crit, p.weapon);
    AudioManager.play("hit");
  }
  missileTarget(x: number, y: number, vx: number, vy: number): Enemy | null {
    let best: Enemy | null = null; let bs = Infinity; const l = Math.hypot(vx, vy) || 1;
    for (const e of this.b.enemies) {
      if (!e.alive) continue; const dx = e.x - x, dy = e.y - y; const d = Math.hypot(dx, dy); if (d > 480) continue;
      let s = d - ((dx * vx + dy * vy) / l / Math.max(d, 1)) * 60;
      if (this.active.has("gravity_missile") && this.inWell(e)) s -= 400;
      if (s < bs) { bs = s; best = e; }
    }
    return best;
  }
  spawnWell(x: number, y: number, d: any): Well {
    const w: Well = { x, y, r: d.well_radius, t: 0, dur: d.well_duration, pull: d.well_pull, dps: d.well_dps, ion: false, stunTick: 0, id: WID++ };
    this.b.wells.push(w); AudioManager.play("bomb"); EventBus.emit("shake", 3); return w;
  }
  onEmpBlast(x: number, y: number, r: number): void {
    if (!this.active.has("ion_vortex")) return;
    for (const w of this.b.wells) {
      if (Math.hypot(w.x - x, w.y - y) < w.r + r) {
        if (!w.ion) { w.ion = true; w.dps += this.defs.ion_vortex.dps; } w.dur += this.defs.ion_vortex.extend;
        this.trigger("ion_vortex", w.x, w.y);
      }
    }
  }
  updateWells(dt: number): void {
    const keep: Well[] = [];
    for (const w of this.b.wells) {
      w.t += dt; w.stunTick -= dt;
      for (const e of this.b.enemies) {
        if (!e.alive) continue; const dx = w.x - e.x, dy = w.y - e.y; const d = Math.hypot(dx, dy);
        if (d < w.r) {
          e.inWellTimer = 0.2; const f = w.pull * (1 - (d / w.r) * 0.6);
          if (d > 0.5) { e.vx += (dx / d) * f * dt; e.vy += (dy / d) * f * dt; }
          e.takeDamage(w.dps * dt, false, "well", true);
          if (w.ion && w.stunTick <= 0) e.stunTimer = Math.max(e.stunTimer, 0.3);
        }
      }
      if (w.stunTick <= 0) w.stunTick = 0.25;
      if (w.t < w.dur) keep.push(w);
    }
    this.b.wells = keep;
  }
}
