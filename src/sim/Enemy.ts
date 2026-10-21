// Data-driven enemies (chase/strafe/bomber) with shields, EMP, stun, gravity wells + seeded wave director.
import { Rng } from "../core/Rng";
import { EventBus } from "../core/EventBus";
import { AudioManager } from "../core/AudioManager";
import { Data } from "./Data";
import type { Battle } from "./Battle";
let NEXT_ID = 1;
export class Enemy {
  id = NEXT_ID++;
  hp: number; radius: number; speed: number; accel: number; behavior: string;
  vx = 0; vy = 0; alive = true; flash = 0; fireTimer: number; orbitSign: number;
  shield: number; maxShield: number; empTimer = 0; stunTimer = 0; inWellTimer = 0; age = 0; heading = 0;
  private rng: Rng;
  constructor(public b: Battle, public type: string, public data: any, public x: number, public y: number, seed: number) {
    this.behavior = data.behavior; this.hp = data.hp; this.maxShield = data.shield ?? 0; this.shield = this.maxShield;
    this.radius = data.radius; this.speed = data.speed; this.accel = data.accel;
    this.rng = new Rng(seed); this.orbitSign = this.rng.randf() < 0.5 ? 1 : -1;
    this.fireTimer = this.rng.range(0.5, data.fire_interval ?? 2);
    this.heading = Math.PI / 2;
  }
  update(dt: number): void {
    if (!this.alive) return;
    this.age += dt;
    this.empTimer = Math.max(0, this.empTimer - dt); this.inWellTimer = Math.max(0, this.inWellTimer - dt); this.flash = Math.max(0, this.flash - dt);
    const p = this.b.player;
    if (this.stunTimer > 0) {
      this.stunTimer -= dt;
      const l = Math.hypot(this.vx, this.vy); const s = Math.max(0, l - 120 * dt);
      if (l > 0) { this.vx = this.vx / l * s; this.vy = this.vy / l * s; }
      this.x += this.vx * dt; this.y += this.vy * dt; return;
    }
    const tx = p.x - this.x, ty = p.y - this.y; const dist = Math.max(0.001, Math.hypot(tx, ty));
    const dx = tx / dist, dy = ty / dist; let wx = 0, wy = 0;
    if (this.behavior === "chase") { wx = dx * this.speed; wy = dy * this.speed; }
    else if (this.behavior === "strafe") {
      const k = Math.max(-1, Math.min(1, (dist - this.data.orbit_distance) / 40));
      let ax = dx * k - dy * this.orbitSign, ay = dy * k + dx * this.orbitSign; const l = Math.hypot(ax, ay) || 1;
      wx = ax / l * this.speed; wy = ay / l * this.speed;
    } else {
      const k = Math.max(-1, Math.min(1, (dist - this.data.keep_distance) / 60));
      wx = dx * k * this.speed - dy * this.orbitSign * this.speed * 0.4; wy = dy * k * this.speed + dx * this.orbitSign * this.speed * 0.4;
    }
    const step = this.accel * (this.inWellTimer > 0 ? 0.25 : 1) * dt;
    const ex = wx - this.vx, ey = wy - this.vy, el = Math.hypot(ex, ey);
    if (el <= step) { this.vx = wx; this.vy = wy; } else { this.vx += ex / el * step; this.vy += ey / el * step; }
    this.x += this.vx * dt; this.y += this.vy * dt;
    this.heading = this.behavior === "strafe" && Math.hypot(this.vx, this.vy) > 1 ? Math.atan2(this.vy, this.vx) : Math.atan2(dy, dx);
    if (this.data.fire_interval && p.alive) {
      this.fireTimer -= dt;
      if (this.fireTimer <= 0 && dist < 260) { this.fireTimer = this.data.fire_interval; this.fire(dx, dy); }
    }
    if (p.alive && dist < this.radius + p.radius) { p.takeDamage(this.data.contact_damage, this.x, this.y); this.takeDamage(this.data.contact_damage, false); }
  }
  private fire(dx: number, dy: number): void {
    const bs = this.data.bullet_speed, dmg = this.data.bullet_damage, col = this.data.color;
    if (this.behavior === "bomber") {
      const n = this.data.burst ?? 5;
      for (let i = 0; i < n; i++) { const a = (i - (n - 1) / 2) * 0.22; const c = Math.cos(a), s = Math.sin(a);
        this.b.projectiles.spawn(this.x, this.y, (dx * c - dy * s) * bs, (dx * s + dy * c) * bs, dmg, 2.5, 1, col, false); }
    } else this.b.projectiles.spawn(this.x, this.y, dx * bs, dy * bs, dmg, 2, 1, col, false);
    AudioManager.play("enemy_shoot");
  }
  takeDamage(amount: number, crit: boolean, source = "", silent = false): void {
    if (!this.alive) return;
    let rest = amount;
    if (this.shield > 0) { const a = Math.min(this.shield, rest); this.shield -= a; rest -= a; }
    this.hp -= rest;
    if (!silent) { this.flash = 0.08; this.b.damageNumber(this.x, this.y, amount, crit); }
    if (this.hp <= 0) this.die();
  }
  applyEmp(stun: number, mark: number): void { this.shield = 0; this.stunTimer = Math.max(this.stunTimer, stun); this.empTimer = Math.max(this.empTimer, mark); this.flash = 0.15; }
  die(): void {
    this.alive = false;
    EventBus.emit("explosion", this.x, this.y, this.data.color, this.radius * 3);
    EventBus.emit("enemy_killed", this.type, this.x, this.y);
    AudioManager.play("explosion");
    this.b.removeEnemy(this);
  }
}
export class EnemyDirector {
  rng: Rng; waves = Data.waves.waves as any[]; maxEnemies = Data.waves.max_enemies as number;
  waveIndex = -1; spawnTimer = 0; spawnedTotal = 0; culledTotal = 0;
  constructor(private b: Battle, seed: number) { this.rng = new Rng(seed); }
  tick(t: number, dt: number): void {
    const v = this.b.viewRect(); const cullY = v.y + v.h + 120;
    for (const e of [...this.b.enemies]) if (e.y > cullY) { this.culledTotal++; this.b.removeEnemy(e); }
    let idx = 0; this.waves.forEach((w, i) => { if (t >= w.start) idx = i; });
    if (idx !== this.waveIndex) { this.waveIndex = idx; this.spawnTimer = 0; EventBus.emit("wave_started", idx); }
    this.spawnTimer -= dt;
    if (this.spawnTimer <= 0) {
      const w = this.waves[this.waveIndex]; this.spawnTimer = w.interval;
      for (let i = 0; i < w.count; i++) { if (this.b.enemies.length >= this.maxEnemies) break; this.spawn(this.pick(w.weights)); }
    }
  }
  private pick(weights: Record<string, number>): string {
    let total = 0; for (const k in weights) total += weights[k];
    let r = this.rng.randf() * total; for (const k in weights) { r -= weights[k]; if (r <= 0) return k; }
    return Object.keys(weights)[0];
  }
  private spawn(type: string): void {
    const v = this.b.viewRect(); let x: number, y: number;
    if (this.rng.randf() < 0.7) { x = this.rng.range(v.x + 10, v.x + v.w - 10); y = v.y - 20; }
    else { const side = this.rng.randf() < 0.5 ? -1 : 1; x = side * (v.w / 2 + 16); y = this.rng.range(v.y + 20, v.y + v.h / 2); }
    this.spawnedTotal++;
    this.b.enemies.push(new Enemy(this.b, type, Data.enemies[type], x, y, this.rng.randi()));
  }
}
