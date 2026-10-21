// Modular player ship: inertial flight, dash, mounts with firing arcs, shield, hull, module loss (port of player.gd).
import { EnergyCore } from "./EnergyCore";
import { ShipModel } from "./ShipModel";
import { Weapon } from "./Weapon";
import { Data } from "./Data";
import { EventBus } from "../core/EventBus";
import { AudioManager } from "../core/AudioManager";
import { Params } from "../core/GameManager";
import { rotateToward, angleDiff } from "../core/V2";
import type { Battle } from "./Battle";
export const DRAG = 2.4, DASH_SPEED = 420, DASH_TIME = 0.18, DASH_COOLDOWN = 1.2, MIN_ACCEL = 60;
export interface Mount { key: string; lx: number; ly: number; facing: number; arc: number; weapon: Weapon }
export interface PlayerInput { mx: number; my: number; ax: number; ay: number; aimActive: boolean; fire: boolean; fire2: boolean; dash: boolean; overload: boolean; swap?: boolean }
export class Player {
  x = 0; y = 0; vx = 0; vy = 0; heading = -Math.PI / 2; radius = 10;
  hull = 60; maxHull = 60; shield = 0; maxShield = 0; regenDelay = 0; alive = true;
  dashTimer = 0; dashCd = 0; hurtFlash = 0; god = Params.god;
  core: EnergyCore; ship!: ShipModel; mounts: Mount[] = []; weapons: Weapon[] = [];
  stats: Record<string, number> = {};
  aimX = 0; aimY = -1; aimPX = 0; aimPY = -120; secondaryIndex = 0;
  dashes = 0; damageTaken = 0; movedDistance = 0; thrusting = 0;
  constructor(private b: Battle, seed: number) { this.core = new EnergyCore(seed ^ 0x77); }
  setShip(m: ShipModel): void {
    this.ship = m; this.rebuild(true);
  }
  rebuild(full: boolean): void {
    const m = this.ship; this.stats = m.stats; this.core.coolingBonus = m.stats.cooling ?? 0;
    const old = new Map(this.mounts.map((x) => [x.key, x.weapon]));
    this.mounts = [];
    let i = 0;
    for (const k of m.activeCells("weapon_mount")) {
      const c = m.cells.get(k)!; if (!c.weapon || !Data.weapons[c.weapon]) continue;
      const p = m.localPos(k);
      this.mounts.push({ key: k, lx: p.x, ly: p.y, facing: m.mountFacing(k), arc: m.mountArc(k), weapon: old.get(k) ?? new Weapon(Data.weapons[c.weapon], 1000 + i++) });
    }
    this.weapons = this.mounts.map((x) => x.weapon);
    this.maxHull = m.stats.hull; this.maxShield = m.stats.shield;
    if (full) { this.hull = this.maxHull; this.shield = this.maxShield * this.core.mult("shield_capacity"); }
    else { this.hull = Math.min(this.hull, this.maxHull); }
    this.radius = Math.max(8, m.extentRadius() * 0.7);
    this.b.synergy.refresh(this.weapons.map((w) => w.id));
    EventBus.emit("ship_rebuilt");
  }
  weaponIds(): string[] { return this.weapons.map((w) => w.id); }
  update(dt: number, inp: PlayerInput): void {
    if (!this.alive) return;
    const c = this.core; c.setOverload(inp.overload); c.update(dt);
    this.hurtFlash = Math.max(0, this.hurtFlash - dt);
    const sideOff = c.isDisabled("side_thruster");
    const accel = Math.max(MIN_ACCEL, this.stats.accel * c.mult("engine_accel") * (sideOff ? 0.6 : 1));
    const maxSpeed = this.stats.max_speed * c.mult("engine_max_speed");
    const turn = (this.stats.turn * Math.PI / 180) * c.mult("engine_turn") * (sideOff ? 0.5 : 1);
    let mx = inp.mx, my = inp.my; const ml = Math.hypot(mx, my); if (ml > 1) { mx /= ml; my /= ml; }
    this.thrusting = Math.min(1, ml);
    // inertial flight (same integration as player.gd): accel, linear drag, dash, speed cap
    this.vx += mx * accel * dt; this.vy += my * accel * dt;
    this.vx -= this.vx * DRAG * dt; this.vy -= this.vy * DRAG * dt;
    this.dashCd = Math.max(0, this.dashCd - dt);
    if (inp.dash && this.dashCd <= 0) {
      let dx = mx, dy = my; if (ml < 0.1) { dx = this.aimX; dy = this.aimY; }
      const l = Math.hypot(dx, dy) || 1; this.vx = dx / l * DASH_SPEED; this.vy = dy / l * DASH_SPEED;
      this.dashTimer = DASH_TIME; this.dashCd = DASH_COOLDOWN * c.mult("engine_dash_cooldown"); this.dashes++;
      EventBus.emit("dash_used"); AudioManager.play("dash");
    }
    if (this.dashTimer > 0) this.dashTimer -= dt;
    else { const sp = Math.hypot(this.vx, this.vy); if (sp > maxSpeed) { this.vx *= maxSpeed / sp; this.vy *= maxSpeed / sp; } }
    const ox = this.x, oy = this.y;
    this.x += this.vx * dt; this.y += this.vy * dt;
    this.movedDistance += Math.hypot(this.x - ox, this.y - oy);
    this.b.constrainPlayer(this, dt);
    // Aim (aim point from mouse / stick / touch, see main.ts) -> rotate hull toward it at the module-derived turn rate
    if (inp.aimActive) { const tx = inp.ax - this.x, ty = inp.ay - this.y; const l = Math.hypot(tx, ty); if (l > 2) { this.aimX = tx / l; this.aimY = ty / l; } this.aimPX = inp.ax; this.aimPY = inp.ay; }
    else { this.aimPX = this.x + this.aimX * 120; this.aimPY = this.y + this.aimY * 120; }
    this.heading = rotateToward(this.heading, Math.atan2(this.aimY, this.aimX), turn * dt);
    if (inp.swap) this.cycleSecondary();
    // Shield regen
    const cap = this.maxShield * c.mult("shield_capacity");
    if (this.regenDelay > 0) this.regenDelay -= dt;
    else if (!c.isDisabled("shield_gen")) this.shield = Math.min(cap, this.shield + (this.stats.shield_regen ?? 0) * c.mult("shield_regen") * dt);
    this.shield = Math.min(this.shield, cap);
    // Weapons
    const wOff = c.isDisabled("weapon_mount");
    const diss = c.mult("weapon_heat_dissipation"); const dm = c.mult("weapon_damage"); const rm = c.mult("weapon_fire_rate");
    const sec = this.selectedSecondary();
    for (const m of this.mounts) {
      m.weapon.update(dt, diss);
      if (wOff) continue;
      const want = (m.weapon.slot === "primary" && inp.fire) || (m.weapon === sec && inp.fire2);
      if (!want) continue;
      const o = this.mountWorld(m); let dx = this.aimPX - o.x, dy = this.aimPY - o.y; const l = Math.hypot(dx, dy); if (l < 0.001) continue; dx /= l; dy /= l;
      // fire only if the aim direction lies inside the mount's firing arc (player.gd in_arc)
      if (Math.abs(angleDiff(this.heading + m.facing, Math.atan2(dy, dx))) > m.arc * 0.5) continue;
      const fired = m.weapon.tryFire(this.b, { x: o.x + dx * 3, y: o.y + dy * 3 }, { x: dx, y: dy }, { x: this.aimPX, y: this.aimPY }, dm, rm);
      if (fired) AudioManager.play(m.weapon.kind === "bullet" ? "shoot" : m.weapon.kind === "missile" ? "missile" : m.weapon.kind === "emp" ? "emp" : "bomb");
    }
  }
  secondaryMounts(): Mount[] { return this.mounts.filter((m) => m.weapon.slot === "secondary").sort((a, b) => (a.key < b.key ? -1 : 1)); }
  selectedSecondary(): Weapon | null { const s = this.secondaryMounts(); return s.length ? s[this.secondaryIndex % s.length].weapon : null; }
  cycleSecondary(): void { this.secondaryIndex++; EventBus.emit("ship_rebuilt"); }
  mountWorld(m: Mount): { x: number; y: number } {
    const ch = Math.cos(this.heading), sh = Math.sin(this.heading);
    return { x: this.x + m.lx * ch - m.ly * sh, y: this.y + m.lx * sh + m.ly * ch };
  }
  takeDamage(amount: number, fromX: number, fromY: number): void {
    if (!this.alive || this.dashTimer > 0 || this.god) return;
    this.damageTaken += amount; this.regenDelay = this.ship.base.shield_regen_delay ?? 2;
    let rest = amount;
    if (this.shield > 0) { const a = Math.min(this.shield, rest); this.shield -= a; rest -= a; }
    this.hurtFlash = 0.2;
    EventBus.emit("player_damaged", amount, fromX, fromY); EventBus.emit("shake", rest > 0 ? 5 : 2);
    if (rest <= 0) return;
    AudioManager.play("hurt");
    this.hull = Math.max(0, this.hull - rest);
    // Module damage: direction in ship-local space
    const dx = fromX - this.x, dy = fromY - this.y; const ch = Math.cos(-this.heading), sh = Math.sin(-this.heading);
    const lost = this.ship.damageFrom({ x: dx * ch - dy * sh, y: dx * sh + dy * ch }, rest * 0.6, this.hull / this.maxHull);
    if (lost) { EventBus.emit("explosion", this.x + dx * 0.3, this.y + dy * 0.3, "#FFCC66", 14); EventBus.emit("module_destroyed", lost); if (lost === "core" || lost === "cockpit") this.hull = 0; this.rebuild(false); }
    if (this.hull <= 0 || !this.ship.findFirst("core") || !this.ship.findFirst("cockpit")) this.die();
  }
  die(): void { if (!this.alive) return; this.alive = false; EventBus.emit("explosion", this.x, this.y, "#49E6D4", 40); AudioManager.play("big_explosion"); EventBus.emit("player_died"); }
}
