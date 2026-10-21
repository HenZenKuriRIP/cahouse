// Global typed event bus (mirrors the Godot EventBus autoload).
type Handler = (...args: any[]) => void;
export interface Events {
  weapon_fired: [id: string];
  enemy_killed: [type: string, x: number, y: number];
  player_damaged: [amount: number, fx: number, fy: number];
  player_died: [];
  synergy_triggered: [id: string, x: number, y: number];
  preset_changed: [name: string];
  core_overheated: [category: string, duration: number];
  module_destroyed: [id: string];
  wave_started: [index: number];
  ship_rebuilt: [];
  dash_used: [];
  explosion: [x: number, y: number, color: string, size: number];
  emp_blast: [x: number, y: number, r: number];
  float_text: [x: number, y: number, text: string, color: string, style: string];
  language_changed: [lang: string];
  run_ended: [won: boolean];
  shake: [amount: number];
}
class Bus {
  private h = new Map<string, Set<Handler>>();
  on<K extends keyof Events>(k: K, fn: (...a: Events[K]) => void): () => void {
    if (!this.h.has(k)) this.h.set(k, new Set());
    this.h.get(k)!.add(fn as Handler);
    return () => this.h.get(k)!.delete(fn as Handler);
  }
  emit<K extends keyof Events>(k: K, ...a: Events[K]): void {
    const s = this.h.get(k);
    if (s) for (const fn of [...s]) fn(...a);
  }
  clear(): void { this.h.clear(); }
}
export const EventBus = new Bus();
