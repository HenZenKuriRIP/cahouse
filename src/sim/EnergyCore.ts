// Dynamic Energy Core: WEAPON/SHIELD/ENGINE barycentric split, overload, overheat (port of energy_core.gd).
import { Data } from "./Data";
import { Rng } from "../core/Rng";
import { EventBus } from "../core/EventBus";
export type W3 = [number, number, number];
export class EnergyCore {
  cfg = Data.energy;
  target: W3 = [1 / 3, 1 / 3, 1 / 3];
  current: W3 = [1 / 3, 1 / 3, 1 / 3];
  overloadActive = false;
  overloadLocked = false;
  coreHeat = 0;
  coolingBonus = 0;
  disabledCategory = "";
  disabledTimer = 0;
  presetName = "BALANCED";
  stats = { presets: 0, nudges: 0, overload_time: 0, overheats: 0 };
  private rng: Rng;
  constructor(seed: number) { this.rng = new Rng(seed); }
  static normalize(v: W3, min: number): W3 {
    const a = v.map((x) => Math.max(x, min)) as W3; const s = a[0] + a[1] + a[2];
    return [a[0] / s, a[1] / s, a[2] / s];
  }
  setWeights(v: W3, immediate = false): void {
    this.target = EnergyCore.normalize(v, this.cfg.min_share); this.presetName = "CUSTOM";
    if (immediate) this.current = [...this.target];
  }
  applyPreset(name: string): void {
    const p = this.cfg.presets[name]; if (!p) return;
    this.target = EnergyCore.normalize([p[0], p[1], p[2]], this.cfg.min_share);
    this.presetName = name; this.stats.presets++;
    EventBus.emit("preset_changed", name);
  }
  applyPresetIndex(i: number): void { const o = this.cfg.preset_order; this.applyPreset(o[Math.max(0, Math.min(o.length - 1, i))]); }
  nudge(axis: number): void {
    const v = [...this.target] as W3; v[axis] += this.cfg.nudge_step;
    this.target = EnergyCore.normalize(v, this.cfg.min_share); this.presetName = "CUSTOM"; this.stats.nudges++;
  }
  setOverload(want: boolean): void { this.overloadActive = want && !this.overloadLocked; }
  update(dt: number): void {
    const k = Math.min(1, Math.max(0, this.cfg.transition_speed * dt));
    for (let i = 0; i < 3; i++) this.current[i] += (this.target[i] - this.current[i]) * k;
    if (this.overloadActive) {
      this.coreHeat += this.cfg.core_heat_rise * dt; this.stats.overload_time += dt;
      if (this.coreHeat >= this.cfg.overheat_at) this.overheat();
    } else {
      this.coreHeat = Math.max(0, this.coreHeat - (this.cfg.core_heat_cool + this.coolingBonus) * dt);
      if (this.overloadLocked && this.coreHeat <= this.cfg.overload_unlock_heat) this.overloadLocked = false;
    }
    if (this.disabledTimer > 0) { this.disabledTimer -= dt; if (this.disabledTimer <= 0) this.disabledCategory = ""; }
  }
  private overheat(): void {
    const cats = ["weapon_mount", "shield_gen", "side_thruster"];
    this.disabledCategory = cats[Math.floor(this.rng.randf() * cats.length) % cats.length];
    this.disabledTimer = this.cfg.overheat_disable_time;
    this.coreHeat = this.cfg.overheat_reset_heat;
    this.overloadLocked = true; this.overloadActive = false; this.stats.overheats++;
    EventBus.emit("core_overheated", this.disabledCategory, this.disabledTimer);
  }
  total(): number { return this.overloadActive ? this.cfg.overload_cap : 1; }
  mult(effect: string): number {
    const e = this.cfg.effects[effect];
    let share = effect.startsWith("weapon") ? this.current[0] : effect.startsWith("shield") ? this.current[1] : this.current[2];
    share *= this.total();
    return Math.max(0.1, (e[0] + e[1] * share * 3) / (e[0] + e[1]));
  }
  heatRatio(): number { return this.coreHeat / this.cfg.overheat_at; }
  isWarning(): boolean { return this.coreHeat >= this.cfg.warn_heat; }
  isDisabled(cat: string): boolean { return this.disabledCategory === cat && this.disabledTimer > 0; }
}
