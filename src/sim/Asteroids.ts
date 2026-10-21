// Chunked asteroid field with explosive ore chains, rock splitting, scrap, meteors (port of asteroid_field.gd).
import { Data } from "./Data";
import { Rng, hash2 } from "../core/Rng";
import { EventBus } from "../core/EventBus";
import { AudioManager } from "../core/AudioManager";
import type { Battle } from "./Battle";
let AID = 1;
export interface Asteroid { id: number; x: number; y: number; r: number; hp: number; vx: number; vy: number; spin: number; rot: number; ore: boolean; fuse: number; chained: boolean; variant: number; chunk: number; alive: boolean; meteor: boolean }
export interface Pickup { x: number; y: number; vx: number; vy: number; value: number; t: number }
export interface MeteorWarn { x: number; t: number; dir: number }
export class AsteroidField {
  cfg = Data.asteroidField;
  rocks: Asteroid[] = [];
  pickups: Pickup[] = [];
  warns: MeteorWarn[] = [];
  chunks = new Set<number>();
  meteorTimer: number; destroyed = 0; oreChains = 0; oreDetonations = 0; meteorsSpawned = 0; maxChunks = 0; collected = 0;
  private rng: Rng;
  constructor(private b: Battle, private seed: number) { this.rng = new Rng(seed ^ 0x5bd1); this.meteorTimer = this.cfg.meteor_interval; }
  update(dt: number): void {
    const v = this.b.viewRect(); const ch = this.cfg.chunk_height;
    const top = Math.floor(v.y / ch) - this.cfg.chunks_ahead; const bottom = Math.floor((v.y + v.h + this.cfg.cull_below) / ch);
    for (let c = top; c <= Math.min(bottom, 0); c++) if (!this.chunks.has(c)) this.genChunk(c);
    for (const c of [...this.chunks]) if (c > bottom) { this.chunks.delete(c); this.rocks = this.rocks.filter((r) => r.chunk !== c || r.meteor); }
    this.maxChunks = Math.max(this.maxChunks, this.chunks.size);
    const half = this.b.bandHalf;
    for (const r of this.rocks) {
      if (!r.alive) continue;
      r.x += r.vx * dt; r.y += r.vy * dt; r.rot += r.spin * dt;
      if (!r.meteor && Math.abs(r.x) > half - r.r) { r.x = Math.sign(r.x) * (half - r.r); r.vx = -r.vx; }
      if (r.fuse > 0) { r.fuse -= dt; if (r.fuse <= 0) this.detonate(r); }
    }
    this.rocks = this.rocks.filter((r) => r.alive && !(r.meteor && r.y > v.y + v.h + 200));
    this.collide(dt); this.updatePickups(dt); this.updateMeteors(dt);
  }
  private genChunk(c: number): void {
    this.chunks.add(c); const rng = new Rng(hash2(this.seed, c));
    const ch = this.cfg.chunk_height; const y0 = c * ch; const half = this.b.bandHalf;
    for (let i = 0; i < this.cfg.per_chunk; i++) {
      const r = rng.range(this.cfg.min_radius, this.cfg.max_radius); const x = rng.range(-half + r, half - r); const y = rng.range(y0, y0 + ch);
      if (c === 0 && Math.hypot(x, y - this.b.player.y) < this.cfg.safe_radius + r) continue;
      if (y > -60 && c === 0) continue;
      const ore = rng.randf() < this.cfg.ore_chance;
      this.add(x, y, ore ? Math.min(r, 10) : r, ore, c, rng);
    }
  }
  private add(x: number, y: number, r: number, ore: boolean, chunk: number, rng: Rng, meteor = false): Asteroid {
    const a = rng.randf() * Math.PI * 2; const d = this.cfg.drift;
    const rock: Asteroid = { id: AID++, x, y, r, hp: r * this.cfg.hp_per_radius, vx: Math.cos(a) * d * rng.randf(), vy: Math.sin(a) * d * rng.randf(), spin: rng.range(-1, 1), rot: rng.randf() * 6, ore, fuse: 0, chained: false, variant: rng.randi() % 3, chunk, alive: true, meteor };
    this.rocks.push(rock); return rock;
  }
  asteroidAt(x: number, y: number, pr: number): Asteroid | null {
    for (const r of this.rocks) { if (!r.alive) continue; const rr = r.r + pr; if ((x - r.x) ** 2 + (y - r.y) ** 2 < rr * rr) return r; }
    return null;
  }
  damageAsteroid(r: Asteroid, dmg: number): void {
    if (!r.alive) return;
    if (r.ore) { if (r.fuse <= 0) r.fuse = this.cfg.ore_fuse * (r.chained ? 0.5 : 1); return; }
    r.hp -= dmg; if (r.hp <= 0) this.breakRock(r);
  }
  private breakRock(r: Asteroid): void {
    r.alive = false; this.destroyed++;
    EventBus.emit("explosion", r.x, r.y, "#8a94a8", r.r * 2);
    if (r.r >= 12 && !r.meteor) {
      for (let i = 0; i < 2; i++) { const c = this.add(r.x + (i ? 4 : -4), r.y, r.r * 0.55, false, r.chunk, this.rng); c.vx = (i ? 1 : -1) * 30; }
    }
    const n = Math.max(1, Math.round(r.r * this.cfg.scrap_per_radius));
    for (let i = 0; i < n; i++) { const a = this.rng.randf() * 6.283; this.pickups.push({ x: r.x, y: r.y, vx: Math.cos(a) * 40, vy: Math.sin(a) * 40, value: 1, t: 0 }); }
  }
  private detonate(r: Asteroid): void {
    if (!r.alive) return; r.alive = false; this.oreDetonations++; this.destroyed++;
    const R = this.cfg.ore_blast_radius, D = this.cfg.ore_blast_damage;
    EventBus.emit("explosion", r.x, r.y, "#FFCC66", R); EventBus.emit("shake", 6); AudioManager.play("big_explosion");
    for (const e of [...this.b.enemies]) if (e.alive && Math.hypot(e.x - r.x, e.y - r.y) < R + e.radius) e.takeDamage(D, false, "ore");
    const p = this.b.player; if (p.alive && Math.hypot(p.x - r.x, p.y - r.y) < R + p.radius) p.takeDamage(D * 0.5, r.x, r.y);
    for (const o of this.rocks) {
      if (o === r || !o.alive || Math.hypot(o.x - r.x, o.y - r.y) > R + o.r) continue;
      if (o.ore) { if (o.fuse <= 0) { o.chained = true; o.fuse = this.cfg.ore_fuse * 0.5; this.oreChains++; } }
      else this.damageAsteroid(o, D);
    }
  }
  private collide(dt: number): void {
    const p = this.b.player; if (!p.alive) return;
    for (const r of this.rocks) {
      if (!r.alive) continue; const dx = p.x - r.x, dy = p.y - r.y; const d = Math.hypot(dx, dy); const min = r.r + p.radius * 0.8;
      if (d < min && d > 0.01) {
        const nx = dx / d, ny = dy / d; p.x = r.x + nx * min; p.y = r.y + ny * min;
        const vn = p.vx * nx + p.vy * ny;
        if (r.meteor) { p.takeDamage(20, r.x, r.y); this.breakRock(r); continue; }
        if (vn < 0) { if (-vn > 90) p.takeDamage(8, r.x, r.y); p.vx -= vn * nx * 1.4; p.vy -= vn * ny * 1.4; r.vx -= nx * 20 * dt; r.vy -= ny * 20 * dt; }
      }
    }
  }
  private updatePickups(dt: number): void {
    const p = this.b.player;
    this.pickups = this.pickups.filter((k) => {
      k.t += dt; const dx = p.x - k.x, dy = p.y - k.y; const d = Math.hypot(dx, dy);
      if (d < 60) { k.vx += dx / d * 600 * dt; k.vy += dy / d * 600 * dt; } else { k.vx *= 0.96; k.vy *= 0.96; }
      k.x += k.vx * dt; k.y += k.vy * dt;
      if (d < p.radius + 3) { this.collected += k.value; this.b.onScrap(k.value); AudioManager.play("pickup"); return false; }
      return k.t < 12;
    });
  }
  private updateMeteors(dt: number): void {
    this.meteorTimer -= dt;
    if (this.meteorTimer <= 0) { this.meteorTimer = this.cfg.meteor_interval; this.warns.push({ x: this.rng.range(-this.b.bandHalf + 20, this.b.bandHalf - 20), t: this.cfg.meteor_warning, dir: this.rng.range(-0.25, 0.25) }); }
    this.warns = this.warns.filter((w) => {
      w.t -= dt; if (w.t > 0) return true;
      const v = this.b.viewRect(); const m = this.add(w.x, v.y - 30, this.cfg.meteor_radius, false, 0, this.rng, true);
      m.vx = Math.sin(w.dir) * this.cfg.meteor_speed; m.vy = Math.cos(w.dir) * this.cfg.meteor_speed; m.hp = 9999; this.meteorsSpawned++;
      return false;
    });
  }
}
