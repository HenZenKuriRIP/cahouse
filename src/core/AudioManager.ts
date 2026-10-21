// Procedural WebAudio SFX (no audio files). The context is created/resumed on the first user gesture.
import { SaveManager } from "./SaveManager";
type Sfx = "shoot" | "missile" | "bomb" | "emp" | "hit" | "explosion" | "big_explosion" | "dash" | "ui" | "ui_confirm" | "enemy_shoot" | "overheat" | "synergy" | "pickup" | "hurt";
class Audio {
  ctx: AudioContext | null = null;
  master: GainNode | null = null;
  private noise: AudioBuffer | null = null;
  private last = new Map<string, number>();
  muted = false;
  unlock(): void {
    if (this.ctx) { if (this.ctx.state === "suspended") this.ctx.resume(); return; }
    try {
      this.ctx = new AudioContext();
      this.master = this.ctx.createGain();
      this.master.gain.value = SaveManager.s.sfx * 0.5;
      this.master.connect(this.ctx.destination);
      const len = this.ctx.sampleRate * 0.5;
      this.noise = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
      const d = this.noise.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    } catch { this.ctx = null; }
  }
  private tone(type: OscillatorType, f0: number, f1: number, dur: number, vol: number, delay = 0): void {
    const c = this.ctx!; const t = c.currentTime + delay;
    const o = c.createOscillator(); const g = c.createGain();
    o.type = type; o.frequency.setValueAtTime(f0, t); o.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t + dur);
    g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(this.master!); o.start(t); o.stop(t + dur + 0.02);
  }
  private burst(dur: number, vol: number, freq: number, q = 1): void {
    const c = this.ctx!; const t = c.currentTime;
    const s = c.createBufferSource(); s.buffer = this.noise;
    const f = c.createBiquadFilter(); f.type = "lowpass"; f.frequency.setValueAtTime(freq, t); f.frequency.exponentialRampToValueAtTime(60, t + dur); f.Q.value = q;
    const g = c.createGain(); g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    s.connect(f).connect(g).connect(this.master!); s.start(t); s.stop(t + dur);
  }
  play(name: Sfx): void {
    if (!this.ctx || this.muted || this.ctx.state !== "running") return;
    const now = performance.now(); const minGap = name === "shoot" ? 45 : name === "hit" ? 30 : 20;
    if (now - (this.last.get(name) ?? 0) < minGap) return;
    this.last.set(name, now);
    switch (name) {
      case "shoot": this.tone("square", 880, 440, 0.06, 0.05); break;
      case "enemy_shoot": this.tone("sawtooth", 300, 160, 0.1, 0.04); break;
      case "missile": this.burst(0.18, 0.08, 2400); this.tone("triangle", 400, 900, 0.15, 0.03); break;
      case "bomb": this.tone("sine", 160, 60, 0.35, 0.15); break;
      case "emp": this.tone("sawtooth", 1400, 120, 0.3, 0.06); this.burst(0.2, 0.06, 5000); break;
      case "hit": this.tone("square", 220, 110, 0.04, 0.03); break;
      case "explosion": this.burst(0.35, 0.22, 1800); this.tone("sine", 120, 40, 0.3, 0.12); break;
      case "big_explosion": this.burst(0.8, 0.35, 1200); this.tone("sine", 90, 30, 0.7, 0.2); break;
      case "dash": this.burst(0.2, 0.08, 6000, 4); this.tone("sine", 300, 900, 0.18, 0.05); break;
      case "ui": this.tone("sine", 1200, 1500, 0.05, 0.05); break;
      case "ui_confirm": this.tone("sine", 900, 1800, 0.12, 0.07); break;
      case "overheat": this.tone("square", 520, 260, 0.4, 0.08); this.tone("square", 520, 260, 0.4, 0.06, 0.15); break;
      case "synergy": this.tone("triangle", 660, 1320, 0.25, 0.07); this.tone("triangle", 990, 1980, 0.25, 0.05, 0.08); break;
      case "pickup": this.tone("sine", 1500, 2200, 0.05, 0.03); break;
      case "hurt": this.tone("sawtooth", 200, 70, 0.25, 0.1); break;
    }
  }
}
export const AudioManager = new Audio();
