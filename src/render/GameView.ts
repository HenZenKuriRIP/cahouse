// Renders the Battle simulation. Logic lives on the 2D plane (x, y) which maps to three (x, 0, y); this class only reads it.
import * as THREE from "three";
import { Renderer } from "./Renderer";
import { Assets, InstancedModel } from "./Assets";
import { ShipView } from "./ShipView";
import { Particles, Starfield, Trail, makeNebula, makeShieldMaterial, makeEnemyShieldMaterial, makeWellMaterial, makeRingMaterial } from "./Effects";
import { EventBus } from "../core/EventBus";
import { GameManager } from "../core/GameManager";
import type { Battle } from "../sim/Battle";
import { VIEW_W, VIEW_H, BAND_HALF } from "../sim/Battle";

const C = (h: string, k = 1) => new THREE.Color(h).multiplyScalar(k);
/** Visual scale vs collision size: readable silhouettes on a phone without changing balance. */
export const SHIP_VIS = 1.9, ENEMY_VIS = 1.8;
const TILT = THREE.MathUtils.degToRad(60);
interface Ring { mesh: THREE.Mesh; t: number; dur: number; r: number; active: boolean }
interface Flash { light: THREE.PointLight; t: number }
export class GameView {
  scene: THREE.Scene; cam: THREE.PerspectiveCamera;
  root = new THREE.Group();
  ship = new ShipView(); shipShield: THREE.Mesh; shieldMat: THREE.ShaderMaterial;
  enemies: Record<string, InstancedModel> = {};
  enemyShield: THREE.InstancedMesh;
  rocks: InstancedModel[] = [];
  bullets: THREE.InstancedMesh; missiles: InstancedModel; bombs: InstancedModel;
  pickups: THREE.InstancedMesh;
  particles: Particles; stars: Starfield; nebula: THREE.Mesh; grid: THREE.Mesh; walls: THREE.Mesh;
  wells: { mesh: THREE.Mesh; mat: THREE.ShaderMaterial }[] = [];
  rings: Ring[] = []; flashes: Flash[] = [];
  warnMeshes: THREE.Mesh[] = [];
  trails: Trail[] = [];
  shakeAmt = 0; time = 0; camTarget = new THREE.Vector3();
  hits: { dir: THREE.Vector3; t: number }[] = [];
  private m4 = new THREE.Matrix4(); private q = new THREE.Quaternion(); private s = new THREE.Vector3(); private p = new THREE.Vector3(); private col = new THREE.Color();
  private yAxis = new THREE.Vector3(0, 1, 0);
  private offs: (() => void)[] = [];
  b: Battle | null = null;
  constructor(public r: Renderer) {
    this.scene = r.scene; this.cam = r.camera; this.scene.add(this.root);
    // Lighting: cool key + violet rim + hemisphere fill. Dynamic point lights only for explosions (quality-limited).
    const hemi = new THREE.HemisphereLight("#9fb6ff", "#0b0f20", 0.7); this.root.add(hemi);
    const key = new THREE.DirectionalLight("#EAF4FF", 2.4); key.position.set(-120, 260, 80); key.target.position.set(0, 0, 0); this.root.add(key, key.target);
    const rim = new THREE.DirectionalLight("#A78BFA", 1.2); rim.position.set(140, 60, -200); this.root.add(rim);
    this.keyLight = key;
    for (let i = 0; i < r.cfg.lights; i++) { const l = new THREE.PointLight("#FFCC66", 0, 90, 1.6); l.position.y = 12; this.root.add(l); this.flashes.push({ light: l, t: 0 }); }
    this.nebula = makeNebula(); this.root.add(this.nebula);
    this.stars = new Starfield(r.cfg.stars, this.scene);
    this.grid = this.makeGrid(); this.root.add(this.grid);
    this.walls = this.makeWalls(); this.root.add(this.walls);
    this.root.add(this.ship.group);
    this.shieldMat = makeShieldMaterial("#49E6D4");
    this.shipShield = new THREE.Mesh(new THREE.SphereGeometry(1, 32, 16), this.shieldMat); this.shipShield.scale.set(1, 0.55, 1); this.root.add(this.shipShield);
    for (const t of ["scout", "interceptor", "bomber"]) this.enemies[t] = new InstancedModel("enemy_" + t, 64, this.root, true);
    this.enemyShield = new THREE.InstancedMesh(new THREE.SphereGeometry(1, 20, 12), makeEnemyShieldMaterial(), 64);
    this.enemyShield.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(64 * 3), 3); this.enemyShield.frustumCulled = false; this.root.add(this.enemyShield);
    for (const n of ["asteroid_a", "asteroid_b", "asteroid_c", "asteroid_ore"]) this.rocks.push(new InstancedModel(n, 160, this.root, true));
    const bp = Assets.parts.get("proj_bullet")![0];
    this.bullets = new THREE.InstancedMesh(bp.geometry, new THREE.MeshBasicMaterial({ color: C("#ffffff", 2.6), toneMapped: true }), 800);
    this.bullets.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(800 * 3), 3); this.bullets.frustumCulled = false; this.root.add(this.bullets);
    this.missiles = new InstancedModel("proj_missile", 200, this.root); this.bombs = new InstancedModel("proj_bomb", 40, this.root, true);
    this.pickups = new THREE.InstancedMesh(new THREE.OctahedronGeometry(1.4), new THREE.MeshBasicMaterial({ color: C("#FFCC66", 2.2) }), 200); this.pickups.frustumCulled = false; this.root.add(this.pickups);
    this.particles = new Particles(r.cfg.particles, this.scene);
    for (let i = 0; i < 12; i++) { const mat = makeWellMaterial(); const mesh = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), mat); mesh.rotation.x = -Math.PI / 2; mesh.visible = false; this.root.add(mesh); this.wells.push({ mesh, mat }); }
    for (let i = 0; i < 16; i++) { const mesh = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), makeRingMaterial("#7fd1ff")); mesh.rotation.x = -Math.PI / 2; mesh.visible = false; this.root.add(mesh); this.rings.push({ mesh, t: 0, dur: 0.5, r: 10, active: false }); }
    for (let i = 0; i < 4; i++) {
      const m = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), new THREE.ShaderMaterial({ uniforms: { uT: { value: 0 } }, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
        vertexShader: `varying vec2 vUv; void main(){ vUv=uv; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0); }`,
        fragmentShader: `uniform float uT; varying vec2 vUv; void main(){ float e=1.0-abs(vUv.x*2.0-1.0); float stripe=step(0.5,fract(vUv.y*10.0+uT*4.0));
          float a=e*e*e*(0.12+0.22*stripe)*(0.6+0.4*sin(uT*30.0))*smoothstep(0.0,0.3,vUv.y); gl_FragColor=vec4(vec3(1.0,0.32,0.4)*a*1.8,1.0); }` }));
      m.rotation.x = -Math.PI / 2; m.visible = false; this.root.add(m); this.warnMeshes.push(m);
    }
    this.offs.push(
      EventBus.on("explosion", (x, y, color, size) => this.explode(x, y, color, size)),
      EventBus.on("emp_blast", (x, y, rad) => { this.ring(x, y, rad, "#7fd1ff", 0.45); this.particles.burst(x, y, 26, rad * 2.2, 0.45, 3, C("#7fd1ff")); this.flash(x, y, "#7fd1ff", 2.5); }),
      EventBus.on("synergy_triggered", (id, x, y) => { const c = id === "ion_vortex" ? "#7fd1ff" : id === "emp_crit" ? "#FFCC66" : "#A78BFA"; this.particles.burst(x, y, 10, 60, 0.4, 3.2, C(c)); }),
      EventBus.on("shake", (a) => { if (!GameManager.reduceFlash) this.shakeAmt = Math.min(10, this.shakeAmt + a); }),
      EventBus.on("player_damaged", (_a, fx, fy) => { if (!this.b) return; const p = this.b.player; this.hits.unshift({ dir: new THREE.Vector3(fx - p.x, 0, fy - p.y).normalize(), t: 1 }); this.hits.length = Math.min(4, this.hits.length); }),
      EventBus.on("ship_rebuilt", () => { if (this.b) this.ship.build(this.b.player.ship); }),
    );
  }
  keyLight: THREE.DirectionalLight;
  dispose(): void { for (const o of this.offs) o(); }
  attach(b: Battle): void {
    this.b = b; this.ship.build(b.player.ship); this.particles.clear();
    for (const t of this.trails) { this.scene.remove(t.mesh); }
    this.trails = this.ship.thrusters.map(() => new Trail(28, 1.6, "#FFCC66", this.scene));
    this.hits = [];
  }
  private makeGrid(): THREE.Mesh {
    const mat = new THREE.ShaderMaterial({ uniforms: { uHalf: { value: BAND_HALF } }, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
      vertexShader: `varying vec3 vW; void main(){ vec4 w=modelMatrix*vec4(position,1.0); vW=w.xyz; gl_Position=projectionMatrix*viewMatrix*w; }`,
      fragmentShader: `uniform float uHalf; varying vec3 vW; void main(){ vec2 g=abs(fract(vW.xz/40.0)-0.5); float l=1.0-smoothstep(0.0,0.03,min(g.x,g.y));
        vec2 g2=abs(fract(vW.xz/8.0)-0.5); float d=1.0-smoothstep(0.0,0.06,max(g2.x,g2.y)-0.44); 
        float inside=1.0-smoothstep(uHalf-6.0,uHalf+2.0,abs(vW.x));
        float a=(l*0.035)*inside; gl_FragColor=vec4(vec3(0.29,0.9,0.83)*a,1.0); }` });
    const m = new THREE.Mesh(new THREE.PlaneGeometry(BAND_HALF * 2 + 20, 1600), mat); m.rotation.x = -Math.PI / 2; m.position.y = -14; return m;
  }
  private makeWalls(): THREE.Mesh {
    const mat = new THREE.ShaderMaterial({ uniforms: { uHalf: { value: BAND_HALF }, uTime: { value: 0 } }, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
      vertexShader: `varying vec3 vW; void main(){ vec4 w=modelMatrix*vec4(position,1.0); vW=w.xyz; gl_Position=projectionMatrix*viewMatrix*w; }`,
      fragmentShader: `uniform float uHalf; uniform float uTime; varying vec3 vW; void main(){ float d=abs(vW.x)-uHalf; 
        float line=1.0-smoothstep(0.0,0.9,abs(d)); float out_=smoothstep(0.0,40.0,d)*0.0;
        float dash=step(0.55,fract(vW.z/24.0)); float tick=(1.0-smoothstep(0.0,0.8,abs(d+3.0)))*dash;
        float glow=exp(-max(d,0.0)*0.25)*step(0.0,d)*0.10;
        float a=line*0.75+tick*0.3+glow+out_; gl_FragColor=vec4(vec3(0.29,0.9,0.83)*a,1.0); }` });
    const m = new THREE.Mesh(new THREE.PlaneGeometry(BAND_HALF * 2 + 160, 1600), mat); m.rotation.x = -Math.PI / 2; m.position.y = -0.5; return m;
  }
  explode(x: number, y: number, color: string, size: number): void {
    const c = C(color); const big = size > 12;
    this.particles.burst(x, y, big ? 34 : 6, big ? size * 3 : 40, big ? 0.7 : 0.25, big ? 4.2 : 2.2, c);
    if (big) { this.particles.burst(x, y, 12, size * 1.2, 1.0, 6, C("#FFCC66", 0.7)); this.ring(x, y, size * 1.4, color, 0.4); this.flash(x, y, color, 3); }
  }
  ring(x: number, y: number, r: number, color: string, dur: number): void {
    const g = this.rings.find((k) => !k.active) ?? this.rings[0];
    g.active = true; g.t = 0; g.dur = dur; g.r = r; g.mesh.visible = true; g.mesh.position.set(x, 1, y);
    (g.mesh.material as THREE.ShaderMaterial).uniforms.uColor.value.set(color);
  }
  flash(x: number, y: number, color: string, k: number): void {
    if (!this.flashes.length || GameManager.reduceFlash) return;
    const f = this.flashes.reduce((a, b) => (a.t < b.t ? a : b)); f.t = 0.25; f.light.color.set(color); f.light.intensity = k * 260; f.light.position.set(x, 14, y);
  }
  /** Map a gameplay (x,y) point to CSS pixels on screen. */
  project(x: number, y: number, h = 0): { x: number; y: number } {
    this.p.set(x, h, y).project(this.cam); return { x: (this.p.x * 0.5 + 0.5) * innerWidth, y: (-this.p.y * 0.5 + 0.5) * innerHeight };
  }
  /** Inverse: CSS pixel -> gameplay plane point (ray vs y=0). */
  unproject(sx: number, sy: number): { x: number; y: number } {
    const ndc = new THREE.Vector3((sx / innerWidth) * 2 - 1, -(sy / innerHeight) * 2 + 1, 0.5).unproject(this.cam);
    const dir = ndc.sub(this.cam.position).normalize(); const t = -this.cam.position.y / dir.y;
    return { x: this.cam.position.x + dir.x * t, y: this.cam.position.z + dir.z * t };
  }
  updateCamera(dt: number): void {
    const b = this.b; if (!b) return;
    const v = b.viewRect(); const cz = v.y + v.h * 0.5 + 14;
    const aspect = innerWidth / innerHeight; const t = Math.tan(THREE.MathUtils.degToRad(this.cam.fov) / 2);
    const dW = (BAND_HALF * 2 + 12) / (2 * t * aspect); const dH = (VIEW_H * Math.sin(TILT) * 0.92) / (2 * t);
    const d = Math.max(dW, dH);
    this.camTarget.set(b.player.x * (aspect > 1 ? 0.25 : 0.1), 0, cz);
    const sx = (Math.random() - 0.5) * this.shakeAmt, sz = (Math.random() - 0.5) * this.shakeAmt; this.shakeAmt = Math.max(0, this.shakeAmt - dt * 30);
    this.cam.position.set(this.camTarget.x + sx, Math.sin(TILT) * d, cz + Math.cos(TILT) * d + sz);
    this.cam.lookAt(this.camTarget.x + sx * 0.5, 0, cz + sz * 0.5);
    this.keyLight.position.set(-120, 260, cz + 80); this.keyLight.target.position.set(0, 0, cz);
    this.particles.setScale(innerHeight * this.r.gl.getPixelRatio() / (2 * t));
  }
  lastDt = 1 / 60;
  update(dt: number): void {
    const b = this.b; if (!b) return; this.time += dt; this.lastDt = dt;
    this.updateCamera(dt);
    const cz = this.camTarget.z;
    this.nebula.position.z = cz * 0.55 - 200; (this.nebula.material as THREE.ShaderMaterial).uniforms.uOff.value = cz * 0.00025 * 6; (this.nebula.material as THREE.ShaderMaterial).uniforms.uTime.value = this.time;
    this.nebula.position.z = cz - 300; this.nebula.position.x = this.camTarget.x;
    this.stars.update(cz, this.r.gl.getPixelRatio());
    this.grid.position.z = cz; this.walls.position.z = cz; (this.walls.material as THREE.ShaderMaterial).uniforms.uTime.value = this.time;
    this.syncPlayer(dt); this.syncEnemies(); this.syncRocks(); this.syncProjectiles(dt); this.syncWells(); this.syncRings(dt); this.syncWarns();
    for (const f of this.flashes) { f.t = Math.max(0, f.t - dt); f.light.intensity *= f.t > 0 ? 0.86 : 0; }
    this.particles.update(dt);
  }
  private syncPlayer(dt: number): void {
    const p = this.b!.player; const g = this.ship.group;
    g.visible = p.alive; g.position.set(p.x, 0, p.y); g.rotation.set(0, -p.heading, 0); g.scale.setScalar(SHIP_VIS);
    // bank into turns / lateral motion for a sense of mass
    const lat = -Math.sin(p.heading) * p.vx + Math.cos(p.heading) * p.vy;
    g.rotation.x = THREE.MathUtils.clamp(-lat / 400, -0.35, 0.35);
    const cap = p.maxShield * p.core.mult("shield_capacity");
    const sr = cap > 0 ? p.shield / cap : 0;
    this.shipShield.visible = p.alive && sr > 0.02; this.shipShield.position.set(p.x, 1, p.y); this.shipShield.scale.set(p.radius * 1.25 * SHIP_VIS, p.radius * 0.5, p.radius * 1.25 * SHIP_VIS);
    this.shieldMat.uniforms.uStrength.value = 0.35 + sr * 0.65 + (p.hurtFlash > 0 ? 0.8 : 0); this.shieldMat.uniforms.uTime.value = this.time;
    this.shieldMat.uniforms.uColor.value.set(p.core.overloadActive ? "#FFCC66" : "#49E6D4");
    for (let i = 0; i < 4; i++) {
      const h = this.hits[i]; const u = this.shieldMat.uniforms.uHits.value[i] as THREE.Vector4;
      if (h) { h.t = Math.max(0, h.t - dt * 2.2); u.set(h.dir.x, 0, h.dir.z, h.t); } else u.w = 0;
    }
    const ch = Math.cos(p.heading), sh = Math.sin(p.heading);
    const thrust = 0.35 + p.thrusting * 0.65 + (p.dashTimer > 0 ? 1 : 0) + (p.core.overloadActive ? 0.4 : 0);
    this.ship.thrusters.forEach((t, i) => {
      const wx = p.x + (t.x * ch - t.z * sh) * SHIP_VIS, wz = p.y + (t.x * sh + t.z * ch) * SHIP_VIS;
      this.trails[i]?.push(new THREE.Vector3(wx, 0.6, wz), p.alive ? Math.min(1, thrust) : 0, this.lastDt);
      if (p.alive && Math.random() < 0.6 * thrust) this.particles.emit(wx, 0.6, wz, -ch * 70 + (Math.random() - 0.5) * 12, 0, -sh * 70 + (Math.random() - 0.5) * 12, 0.22, 2.4 * thrust, p.core.overloadActive ? C("#FF5268") : C("#FFCC66"), 3);
    });
    if (p.dashTimer > 0) for (const t of this.ship.sideThrusters) { const wx = p.x + t.x * ch - t.z * sh, wz = p.y + t.x * sh + t.z * ch; this.particles.emit(wx, 0.5, wz, 0, 0, 0, 0.3, 3, C("#49E6D4"), 0); }
  }
  private syncEnemies(): void {
    const b = this.b!; for (const k in this.enemies) this.enemies[k].begin(); let sc = 0;
    for (const e of b.enemies) {
      const im = this.enemies[e.type]; if (!im) continue;
      const warp = Math.min(1, e.age / 0.35); const s = e.radius * ENEMY_VIS * (0.3 + 0.7 * warp);
      this.q.setFromAxisAngle(this.yAxis, -e.heading); this.s.setScalar(s); this.p.set(e.x, 0, e.y);
      this.m4.compose(this.p, this.q, this.s);
      const f = e.flash > 0 ? 3.5 : e.stunTimer > 0 ? 1.6 : 1; this.col.setRGB(f, f, e.stunTimer > 0 ? f * 1.4 : f);
      im.push(this.m4, this.col);
      if (e.age < 0.05) this.particles.burst(e.x, e.y, 6, 50, 0.3, 3, C(e.data.color));
      if (e.shield > 0 && sc < 64) {
        const ratio = e.shield / e.maxShield; this.s.set(e.radius * ENEMY_VIS * 1.2, e.radius * 0.7, e.radius * ENEMY_VIS * 1.2); this.m4.compose(this.p, this.q, this.s);
        this.enemyShield.setMatrixAt(sc, this.m4); this.col.set("#7fd1ff").multiplyScalar(0.3 + 0.7 * ratio); this.enemyShield.setColorAt(sc, this.col); sc++;
      }
      if (e.empTimer > 0 && Math.random() < 0.3) this.particles.emit(e.x + (Math.random() - 0.5) * e.radius * 2, 3, e.y + (Math.random() - 0.5) * e.radius * 2, 0, 12, 0, 0.25, 2, C("#7fd1ff"), 1);
    }
    for (const k in this.enemies) this.enemies[k].end();
    this.enemyShield.count = sc; this.enemyShield.instanceMatrix.needsUpdate = true; if (this.enemyShield.instanceColor) this.enemyShield.instanceColor.needsUpdate = true;
  }
  private syncRocks(): void {
    const f = this.b!.field; for (const r of this.rocks) r.begin();
    for (const a of f.rocks) {
      if (!a.alive) continue;
      const im = a.ore ? this.rocks[3] : this.rocks[a.variant];
      this.q.setFromEuler(new THREE.Euler(a.rot * 0.6, a.rot, a.rot * 0.3)); this.s.setScalar(a.r); this.p.set(a.x, 0, a.y); this.m4.compose(this.p, this.q, this.s);
      if (a.fuse > 0) { const k = 1 + 2.5 * (0.5 + 0.5 * Math.sin(this.time * 40)); this.col.setRGB(k, k * 0.6, k * 0.4); } else if (a.meteor) this.col.setRGB(1.6, 0.8, 0.6); else this.col.setRGB(1, 1, 1);
      im.push(this.m4, this.col);
      if (a.meteor) this.particles.emit(a.x, 2, a.y - a.r * 0.6, (Math.random() - 0.5) * 20, 0, -40, 0.5, 6, C("#FF5268", 0.8), 1);
    }
    for (const r of this.rocks) r.end();
    let n = 0;
    for (const k of f.pickups) { if (n >= 200) break; this.q.setFromAxisAngle(this.yAxis, this.time * 3 + n); this.s.setScalar(1); this.p.set(k.x, 1.5 + Math.sin(this.time * 5 + n) * 0.6, k.y); this.m4.compose(this.p, this.q, this.s); this.pickups.setMatrixAt(n++, this.m4); }
    this.pickups.count = n; this.pickups.instanceMatrix.needsUpdate = true;
  }
  private syncProjectiles(_dt: number): void {
    const list = this.b!.projectiles.list; let nb = 0; this.missiles.begin(); this.bombs.begin();
    for (const p of list) {
      const a = Math.atan2(p.vy, p.vx); this.q.setFromAxisAngle(this.yAxis, -a); this.p.set(p.x, 1.2, p.y);
      if (p.kind === "bullet") {
        if (nb >= 800) continue;
        const s = p.team === 0 ? 2.6 : 3.2; this.s.set(s * 1.6, s * 0.7, s * 0.7); this.m4.compose(this.p, this.q, this.s);
        this.bullets.setMatrixAt(nb, this.m4); this.col.set(p.team === 0 ? (p.crit ? "#FFCC66" : p.color) : p.color); if (p.team !== 0) this.col.multiplyScalar(1.2);
        this.bullets.setColorAt(nb++, this.col);
      } else if (p.kind === "missile") {
        this.s.setScalar(3.2); this.m4.compose(this.p, this.q, this.s); this.missiles.push(this.m4);
        if (Math.random() < 0.7) this.particles.emit(p.x - Math.cos(a) * 3, 1.2, p.y - Math.sin(a) * 3, 0, 0, 0, 0.35, 2.2, C("#FFCC66", 0.8), 0);
      } else {
        this.s.setScalar(3.6); this.q.setFromAxisAngle(this.yAxis, this.time * 4); this.m4.compose(this.p, this.q, this.s);
        this.bombs.push(this.m4, p.kind === "emp" ? this.col.setRGB(0.6, 1.4, 2) : this.col.setRGB(1, 1, 1));
        this.particles.emit(p.x, 1.2, p.y, 0, 0, 0, 0.3, 3.5, p.kind === "emp" ? C("#7fd1ff") : C("#A78BFA"), 0);
      }
    }
    this.bullets.count = nb; this.bullets.instanceMatrix.needsUpdate = true; if (this.bullets.instanceColor) this.bullets.instanceColor.needsUpdate = true;
    this.missiles.end(); this.bombs.end();
  }
  private syncWells(): void {
    const ws = this.b!.wells;
    this.wells.forEach((w, i) => {
      const d = ws[i]; w.mesh.visible = !!d; if (!d) return;
      w.mesh.position.set(d.x, 0.8, d.y); w.mesh.scale.setScalar(d.r * Math.min(1, d.t / 0.2));
      w.mat.uniforms.uTime.value = this.time; w.mat.uniforms.uIon.value = d.ion ? 1 : 0; w.mat.uniforms.uFade.value = Math.min(1, (d.dur - d.t) / 0.4);
      if (Math.random() < 0.5) { const a = Math.random() * 6.283; const rr = d.r * (0.6 + Math.random() * 0.4);
        this.particles.emit(d.x + Math.cos(a) * rr, 1, d.y + Math.sin(a) * rr, -Math.cos(a) * rr * 1.5 - Math.sin(a) * 40, 0, -Math.sin(a) * rr * 1.5 + Math.cos(a) * 40, 0.5, 2.2, d.ion ? C("#7fd1ff") : C("#A78BFA"), 0.5); }
    });
  }
  private syncRings(dt: number): void {
    for (const g of this.rings) {
      if (!g.active) continue; g.t += dt; const u = g.t / g.dur;
      if (u >= 1) { g.active = false; g.mesh.visible = false; continue; }
      (g.mesh.material as THREE.ShaderMaterial).uniforms.uT.value = u; g.mesh.scale.setScalar(g.r);
    }
  }
  private syncWarns(): void {
    const f = this.b!.field; const v = this.b!.viewRect();
    this.warnMeshes.forEach((m, i) => {
      const w = f.warns[i]; m.visible = !!w; if (!w) return;
      m.position.set(w.x, 0.5, v.y + v.h * 0.5); m.scale.set(22, v.h * 1.4, 1); m.rotation.z = -w.dir;
      (m.material as THREE.ShaderMaterial).uniforms.uT.value = this.time;
    });
  }
}
