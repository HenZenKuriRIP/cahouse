// Battle orchestration: vertical endless scroll, band clamp, goal, grading (port of battle.gd). Pure logic, no rendering.
import { Player, type PlayerInput } from "./Player";
import { ShipModel } from "./ShipModel";
import { ProjectileSystem } from "./Projectiles";
import { Enemy, EnemyDirector } from "./Enemy";
import { SynergySystem, type Well } from "./Synergy";
import { AsteroidField } from "./Asteroids";
import { EventBus } from "../core/EventBus";
import { AudioManager } from "../core/AudioManager";
import { GameManager, Params } from "../core/GameManager";
export const BAND_HALF = 118, BASE_SCROLL = 40, PUSH_MARGIN = 100, VIEW_W = 270, VIEW_H = 480;
export class Battle {
  bandHalf = BAND_HALF; scrollY = 0; scrollSpeed = BASE_SCROLL; time = 0;
  goal = Params.endless ? Infinity : Params.goal;
  enemies: Enemy[] = []; wells: Well[] = [];
  player: Player; projectiles: ProjectileSystem; synergy: SynergySystem; director: EnemyDirector; field: AsteroidField;
  ended = false; won = false; attract = false; directorPaused = false; private offs: (() => void)[] = []; kills = 0; scrap = 0; empBlasts = 0; viewH = VIEW_H;
  constructor(seed: number, ship?: ShipModel) {
    this.synergy = new SynergySystem(this);
    this.projectiles = new ProjectileSystem(this);
    this.player = new Player(this, seed);
    this.player.setShip(ship ?? ShipModel.fromDefault());
    this.director = new EnemyDirector(this, seed ^ 0x1234);
    this.field = new AsteroidField(this, seed);
    this.offs.push(EventBus.on("enemy_killed", () => { this.kills++; GameManager.kills = this.kills; }));
  }
  distance(): number { return Math.max(0, -this.scrollY); }
  viewRect() { return { x: -VIEW_W / 2, y: this.scrollY - this.viewH / 2, w: VIEW_W, h: this.viewH }; }
  /** battle.gd constrain_player: soft walls at the band edge and the scroll window, hard clamp slightly outside. */
  constrainPlayer(p: Player, dt: number): void {
    const bh = this.bandHalf; const x = p.x;
    if (Math.abs(x) > bh) p.vx -= Math.sign(x) * (Math.abs(x) - bh) * 40 * dt;
    p.x = Math.max(-bh - 12, Math.min(bh + 12, x));
    const top = this.scrollY - 205, bottom = this.scrollY + 140;
    if (p.y > bottom) p.vy -= (p.y - bottom) * 40 * dt; else if (p.y < top) p.vy += (top - p.y) * 40 * dt;
    p.y = Math.max(top - 15, Math.min(bottom + 25, p.y));
  }
  update(dt: number, inp: PlayerInput): void {
    if (this.ended) return;
    this.time += dt;
    const p = this.player;
    // Scroll (battle.gd): constant base speed; flying above the push line drags the camera along
    this.scrollY -= BASE_SCROLL * dt; this.scrollSpeed = BASE_SCROLL;
    p.update(dt, inp);
    if (p.alive) { const push = this.scrollY - PUSH_MARGIN; if (p.y < push) { this.scrollSpeed += (push - p.y) / dt; this.scrollY -= push - p.y; } }
    if (!this.attract && !this.directorPaused) this.director.tick(this.time, dt);
    for (const e of [...this.enemies]) e.update(dt);
    this.projectiles.update(dt);
    this.synergy.updateWells(dt);
    this.field.update(dt);
    if (Params.lose && this.time > 3 && p.alive) { p.god = false; p.hull = 0.01; p.takeDamage(999, p.x, p.y - 10); }
    if (this.attract) return;
    if (!p.alive) this.end(false);
    else if (this.distance() >= this.goal) this.end(true);
  }
  dispose(): void { for (const o of this.offs) o(); this.projectiles.clear(); }
  end(won: boolean): void { if (this.ended) return; this.ended = true; this.won = won; GameManager.state = "ENDED"; EventBus.emit("run_ended", won); if (won) AudioManager.play("ui_confirm"); }
  grade(): string { const s = this.distance() / 100 + this.kills * 0.5 + this.synergy.total * 0.2; return s > 260 ? "S" : s > 180 ? "A" : s > 100 ? "B" : "C"; }
  removeEnemy(e: Enemy): void { const i = this.enemies.indexOf(e); if (i >= 0) this.enemies.splice(i, 1); }
  spawnWell(x: number, y: number, d: any): void { this.synergy.spawnWell(x, y, d); }
  empBlast(x: number, y: number, d: any, dmg: number): void {
    const r = d.blast_radius; this.empBlasts++;
    EventBus.emit("emp_blast", x, y, r); AudioManager.play("emp");
    for (const e of [...this.enemies]) if (e.alive && Math.hypot(e.x - x, e.y - y) < r + e.radius) { e.applyEmp(d.stun_time, d.emp_mark_time); e.takeDamage(dmg, false, "emp"); }
    this.synergy.onEmpBlast(x, y, r);
  }
  fxHit(x: number, y: number, color: string): void { EventBus.emit("explosion", x, y, color, 4); }
  damageNumber(x: number, y: number, amt: number, crit: boolean): void {
    EventBus.emit("float_text", x, y, String(Math.round(amt)), crit ? "#FFCC66" : "#EAF4FF", crit ? "crit" : "dmg");
  }
  onScrap(v: number): void { this.scrap += v; GameManager.scrap = this.scrap; }
}
