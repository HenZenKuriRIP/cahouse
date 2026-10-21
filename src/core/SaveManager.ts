// Versioned localStorage save (settings, custom ship, best run). Unknown/old versions are migrated or reset.
export interface Settings { language: string; reduceFlash: boolean; touch: "auto" | "on" | "off"; quality: "auto" | "low" | "med" | "high"; sfx: number }
export interface SaveData { version: number; settings: Settings; ship: any | null; best: { distance: number; kills: number } }
const KEY = "voidsignal3d.save";
export const SAVE_VERSION = 2;
function defaults(): SaveData {
  const zh = (navigator.language || "en").toLowerCase().startsWith("zh");
  return { version: SAVE_VERSION, settings: { language: zh ? "zh" : "en", reduceFlash: false, touch: "auto", quality: "auto", sfx: 0.6 }, ship: null, best: { distance: 0, kills: 0 } };
}
export function migrate(raw: any): SaveData {
  const d = defaults();
  if (!raw || typeof raw !== "object") return d;
  if (raw.version === 1) { raw.settings = { ...raw.settings, quality: "auto" }; raw.version = 2; }
  if (raw.version !== SAVE_VERSION) return d;
  return { ...d, ...raw, settings: { ...d.settings, ...(raw.settings || {}) }, best: { ...d.best, ...(raw.best || {}) } };
}
class Save {
  data: SaveData = defaults();
  ephemeral = false;
  load(): void {
    try { this.data = migrate(JSON.parse(localStorage.getItem(KEY) || "null")); } catch { this.data = defaults(); }
  }
  save(): void { if (this.ephemeral) return; try { localStorage.setItem(KEY, JSON.stringify(this.data)); } catch { /* private mode */ } }
  set<K extends keyof Settings>(k: K, v: Settings[K]): void { this.data.settings[k] = v; this.save(); }
  get s(): Settings { return this.data.settings; }
}
export const SaveManager = new Save();
