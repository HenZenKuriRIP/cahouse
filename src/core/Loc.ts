// zh/en localisation from the Godot project's strings.csv (key,en,zh; RFC4180 quoting), printf-style formatting.
import csvText from "../data/strings.csv?raw";
import { EventBus } from "./EventBus";
import { SaveManager } from "./SaveManager";

export function parseCsv(text: string): string[][] {
  const rows: string[][] = []; let row: string[] = []; let cell = ""; let q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"') { if (text[i + 1] === '"') { cell += '"'; i++; } else q = false; } else cell += c;
    } else if (c === '"') q = true;
    else if (c === ",") { row.push(cell); cell = ""; }
    else if (c === "\n" || c === "\r") { if (c === "\r" && text[i + 1] === "\n") i++; row.push(cell); cell = ""; if (row.some((x) => x !== "")) rows.push(row); row = []; }
    else cell += c;
  }
  if (cell !== "" || row.length) { row.push(cell); rows.push(row); }
  return rows;
}
export function fmt(s: string, ...args: any[]): string {
  let i = 0;
  return s.replace(/%([+0-9.]*)([dsf%])/g, (m, flags: string, t: string) => {
    if (t === "%") return "%";
    const a = args[i++];
    if (t === "s") return String(a);
    const plus = flags.includes("+");
    if (t === "d") {
      const n = Math.trunc(Number(a)); const pad = /^0(\d+)$/.exec(flags.replace("+", ""));
      let r = Math.abs(n).toString(); if (pad) r = r.padStart(Number(pad[1]), "0");
      return (n < 0 ? "-" : plus ? "+" : "") + r;
    }
    const p = /\.(\d+)/.exec(flags); const r = Number(a).toFixed(p ? Number(p[1]) : 6);
    return (plus && Number(a) >= 0 ? "+" : "") + r;
  });
}
class Localization {
  table: Record<string, Record<string, string>> = { en: {}, zh: {} };
  keys: string[] = [];
  language = "en";
  constructor() {
    const rows = parseCsv(csvText);
    const header = rows[0];
    for (const r of rows.slice(1)) {
      this.keys.push(r[0]);
      for (let c = 1; c < header.length; c++) this.table[header[c]][r[0]] = r[c] ?? "";
    }
  }
  init(): void { this.language = SaveManager.s.language === "zh" ? "zh" : "en"; this.apply(); }
  has(key: string): boolean { return key in this.table.en; }
  tr(key: string, ...args: any[]): string {
    const s = this.table[this.language][key] ?? this.table.en[key] ?? key;
    return args.length ? fmt(s, ...args) : s;
  }
  set(lang: string, persist = true): void {
    this.language = lang === "zh" ? "zh" : "en";
    if (persist) SaveManager.set("language", this.language);
    this.apply();
    EventBus.emit("language_changed", this.language);
  }
  toggle(): void { this.set(this.language === "zh" ? "en" : "zh"); }
  private apply(): void { document.documentElement.lang = this.language === "zh" ? "zh-CN" : "en"; }
}
export const Loc = new Localization();
export const tr = (k: string, ...a: any[]) => Loc.tr(k, ...a);
