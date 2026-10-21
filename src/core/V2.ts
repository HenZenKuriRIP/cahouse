// Minimal 2D vector helpers. Gameplay runs on a 2D plane (x right, y down = backwards); the renderer maps (x, y) -> three.js (x, 0, y).
export interface V { x: number; y: number }
export const v = (x = 0, y = 0): V => ({ x, y });
export const len = (a: V) => Math.hypot(a.x, a.y);
export const dist = (a: V, b: V) => Math.hypot(a.x - b.x, a.y - b.y);
export const dist2 = (a: V, b: V) => (a.x - b.x) ** 2 + (a.y - b.y) ** 2;
export const norm = (a: V): V => { const l = Math.hypot(a.x, a.y); return l > 1e-6 ? { x: a.x / l, y: a.y / l } : { x: 0, y: 0 }; };
export const limit = (a: V, m: number): V => { const l = Math.hypot(a.x, a.y); return l > m ? { x: a.x / l * m, y: a.y / l * m } : { x: a.x, y: a.y }; };
export const rot = (a: V, ang: number): V => { const c = Math.cos(ang), s = Math.sin(ang); return { x: a.x * c - a.y * s, y: a.x * s + a.y * c }; };
export const fromAngle = (a: number, m = 1): V => ({ x: Math.cos(a) * m, y: Math.sin(a) * m });
export const angle = (a: V) => Math.atan2(a.y, a.x);
export const clamp = (x: number, a: number, b: number) => Math.min(b, Math.max(a, x));
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
export const angleDiff = (a: number, b: number) => { let d = (b - a) % (Math.PI * 2); if (d > Math.PI) d -= Math.PI * 2; if (d < -Math.PI) d += Math.PI * 2; return d; };
export const rotateToward = (from: number, to: number, step: number) => { const d = angleDiff(from, to); return Math.abs(d) <= step ? to : from + Math.sign(d) * step; };
export const moveToward = (a: V, b: V, step: number): V => { const dx = b.x - a.x, dy = b.y - a.y, l = Math.hypot(dx, dy); return l <= step || l < 1e-6 ? { x: b.x, y: b.y } : { x: a.x + dx / l * step, y: a.y + dy / l * step }; };
