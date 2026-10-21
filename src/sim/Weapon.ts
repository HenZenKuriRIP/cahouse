// Data-driven weapon: fire rate, heat/overheat, kinds bullet/missile/bomb/emp (port of weapon.gd).
import { Rng } from "../core/Rng";
import { EventBus } from "../core/EventBus";
import { rot, type V } from "../core/V2";
import type { Battle } from "./Battle";
export class Weapon {
  id: string; kind: string; slot: string;
  cooldown = 0; heat = 0; overheated = false; shots = 0;
  private rng: Rng;
  constructor(public data: any, seed: number) { this.id = data.id; this.kind = data.kind; this.slot = data.slot; this.rng = new Rng(seed); }
  update(dt: number, diss = 1): void {
    this.cooldown = Math.max(0, this.cooldown - dt);
    this.heat = Math.max(0, this.heat - this.data.heat_dissipation * diss * dt);
    if (this.overheated && this.heat <= this.data.overheat_recover) this.overheated = false;
  }
  heatRatio(): number { return this.heat / this.data.overheat_threshold; }
  readyRatio(): number { return 1 - this.cooldown * this.data.fire_rate; }
  tryFire(b: Battle, origin: V, dir: V, target: V, dmgMult = 1, rateMult = 1): boolean {
    if (this.cooldown > 0 || this.overheated) return false;
    const d = this.data;
    this.cooldown = 1 / (d.fire_rate * rateMult);
    this.heat += d.heat_generation;
    if (this.heat >= d.overheat_threshold) { this.heat = d.overheat_threshold; this.overheated = true; }
    const speed = d.projectile_speed; let life = d.projectile_lifetime;
    if (this.kind === "bullet") life = Math.min(life, d.range / speed);
    else if (this.kind === "bomb" || this.kind === "emp") life = Math.min(Math.max(Math.hypot(target.x - origin.x, target.y - origin.y), 30), d.range) / speed;
    const count = d.count ?? 1; const spread = (d.spread_deg * Math.PI) / 180;
    for (let i = 0; i < count; i++) {
      const a = count === 1 ? this.rng.range(-spread, spread) : -spread + (2 * spread * i) / Math.max(1, count - 1);
      const dd = rot(dir, a); const crit = this.rng.randf() < d.critical_chance;
      const dmg = d.damage * dmgMult * (crit ? d.critical_multiplier : 1);
      b.projectiles.spawn(origin.x, origin.y, dd.x * speed, dd.y * speed, dmg, life, 0, d.color, crit, this.kind, this.id, d);
    }
    this.shots++;
    EventBus.emit("weapon_fired", this.id);
    return true;
  }
}
