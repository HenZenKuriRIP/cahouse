// Pooled projectile simulation (struct-of-objects + free list). Rendered with InstancedMesh per kind.
import { ObjectPool } from "../core/ObjectPool";
import type { Battle } from "./Battle";
import type { Enemy } from "./Enemy";
export interface Projectile {
  x: number; y: number; vx: number; vy: number; damage: number; life: number; maxLife: number; radius: number;
  team: number; color: string; crit: boolean; kind: string; weapon: string; data: any; target: Enemy | null; retarget: number; active: boolean;
}
export class ProjectileSystem {
  list: Projectile[] = [];
  pool = new ObjectPool<Projectile>(() => ({ x: 0, y: 0, vx: 0, vy: 0, damage: 0, life: 0, maxLife: 0, radius: 2, team: 0, color: "#fff", crit: false, kind: "bullet", weapon: "", data: null, target: null, retarget: 0, active: false }));
  constructor(private b: Battle) {}
  spawn(x: number, y: number, vx: number, vy: number, dmg: number, life: number, team: number, color: string, crit: boolean, kind = "bullet", weapon = "", data: any = null): void {
    const p = this.pool.get();
    Object.assign(p, { x, y, vx, vy, damage: dmg, life, maxLife: life, team, color, crit, kind, weapon, data, target: null, retarget: 0, active: true });
    p.radius = team === 0 ? 2 : 3; if (kind === "bomb" || kind === "emp") p.radius = 3;
    this.list.push(p);
  }
  private release(p: Projectile): void { p.active = false; p.target = null; this.pool.release(p); }
  update(dt: number): void {
    const b = this.b; const keep: Projectile[] = [];
    for (const p of this.list) {
      if (!p.active) continue;
      if (p.kind === "missile") this.home(p, dt);
      p.x += p.vx * dt; p.y += p.vy * dt; p.life -= dt;
      if (p.life <= 0) { this.expire(p); continue; }
      const ast = b.field.asteroidAt(p.x, p.y, p.radius);
      if (ast) { b.field.damageAsteroid(ast, p.damage); this.impact(p); continue; }
      let hit = false;
      if (p.team === 0) {
        for (const e of b.enemies) {
          const rr = p.radius + e.radius;
          if (e.alive && (p.x - e.x) ** 2 + (p.y - e.y) ** 2 < rr * rr) { b.synergy.onPlayerHit(p, e); this.impact(p); hit = true; break; }
        }
      } else {
        const pl = b.player; const rr = p.radius + pl.radius;
        if (pl.alive && (p.x - pl.x) ** 2 + (p.y - pl.y) ** 2 < rr * rr) {
          const l = Math.hypot(p.vx, p.vy) || 1;
          pl.takeDamage(p.damage, p.x - (p.vx / l) * 40, p.y - (p.vy / l) * 40); this.release(p); hit = true;
        }
      }
      if (!hit) keep.push(p);
    }
    this.list = keep;
  }
  private home(p: Projectile, dt: number): void {
    p.retarget -= dt;
    if (!p.target || !p.target.alive || p.retarget <= 0) { p.retarget = 0.25; p.target = this.b.synergy.missileTarget(p.x, p.y, p.vx, p.vy); }
    if (p.target) {
      const want = Math.atan2(p.target.y - p.y, p.target.x - p.x); const cur = Math.atan2(p.vy, p.vx);
      let d = want - cur; while (d > Math.PI) d -= Math.PI * 2; while (d < -Math.PI) d += Math.PI * 2;
      const step = (p.data?.turn_rate ?? 4) * dt; const a = Math.abs(d) <= step ? want : cur + Math.sign(d) * step;
      const s = Math.hypot(p.vx, p.vy); p.vx = Math.cos(a) * s; p.vy = Math.sin(a) * s;
    }
  }
  private impact(p: Projectile): void {
    if (p.kind === "bomb") this.b.spawnWell(p.x, p.y, p.data);
    else if (p.kind === "emp") this.b.empBlast(p.x, p.y, p.data, p.damage);
    else this.b.fxHit(p.x, p.y, p.team === 0 ? p.color : "#FF5268");
    this.release(p);
  }
  private expire(p: Projectile): void { if (p.kind === "bomb" || p.kind === "emp") this.impact(p); else this.release(p); }
  clear(): void { for (const p of this.list) this.release(p); this.list = []; }
}
