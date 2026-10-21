// Run-level state + URL parameters (the web equivalent of Godot's command-line user args).
import { SaveManager } from "./SaveManager";
export type GState = "TITLE" | "PLAYING" | "PAUSED" | "BUILDER" | "ENDED";
const q = new URLSearchParams(location.search);
const num = (k: string, d: number) => (q.has(k) ? Number(q.get(k)) : d);
export const Params = {
  autotest: q.has("autotest"),
  god: q.get("god") === "1",
  timescale: num("timescale", 1),
  seed: q.has("seed") ? num("seed", 3287) : q.has("autotest") ? 3287 : Math.floor(Math.random() * 1e9),
  lang: q.get("lang") || "",
  goal: num("goal", 7200),
  endless: q.has("endless"),
  lose: q.has("lose"),
  touch: q.get("touch") || "",
  quality: q.get("quality") || "",
  shots: q.has("shots"),
  seconds: num("seconds", 120),
  skipTitle: q.has("play") || q.has("autotest"),
};
class GM {
  state: GState = "TITLE";
  runTime = 0;
  kills = 0;
  scrap = 0;
  runSeed = Params.seed;
  timeScale = Params.timescale;
  newRun(): void { this.runTime = 0; this.kills = 0; this.scrap = 0; this.state = "PLAYING"; }
  get reduceFlash(): boolean { return SaveManager.s.reduceFlash; }
}
export const GameManager = new GM();
