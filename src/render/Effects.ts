// Cheap GPU-friendly effects: additive point particles, nebula sky, parallax stars, fresnel shields, wells, rings, trails.
import * as THREE from "three";

/** Ring-buffer additive particle system rendered as a single THREE.Points draw call. */
export class Particles {
  points: THREE.Points; private pos: Float32Array; private col: Float32Array; private size: Float32Array; private alpha: Float32Array;
  private vel: Float32Array; private life: Float32Array; private maxLife: Float32Array; private drag: Float32Array; private s0: Float32Array;
  private head = 0; alive = 0;
  constructor(public cap: number, scene: THREE.Scene) {
    const g = new THREE.BufferGeometry();
    this.pos = new Float32Array(cap * 3); this.col = new Float32Array(cap * 3); this.size = new Float32Array(cap); this.alpha = new Float32Array(cap);
    this.vel = new Float32Array(cap * 3); this.life = new Float32Array(cap); this.maxLife = new Float32Array(cap); this.drag = new Float32Array(cap); this.s0 = new Float32Array(cap);
    g.setAttribute("position", new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute("color", new THREE.BufferAttribute(this.col, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute("size", new THREE.BufferAttribute(this.size, 1).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute("alpha", new THREE.BufferAttribute(this.alpha, 1).setUsage(THREE.DynamicDrawUsage));
    const m = new THREE.ShaderMaterial({
      uniforms: { uScale: { value: 400 } }, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
      vertexShader: `attribute float size; attribute float alpha; varying vec3 vC; varying float vA; uniform float uScale;
        void main(){ vC=color; vA=alpha; vec4 mv=modelViewMatrix*vec4(position,1.0); gl_PointSize=size*uScale/-mv.z; gl_Position=projectionMatrix*mv; }`,
      fragmentShader: `varying vec3 vC; varying float vA; void main(){ vec2 d=gl_PointCoord-0.5; float r=dot(d,d)*4.0; if(r>1.0) discard;
        float a=(1.0-r); a*=a; gl_FragColor=vec4(vC*(1.6+2.0*a)*vA*a, 1.0); }`,
      vertexColors: true,
    });
    this.points = new THREE.Points(g, m); this.points.frustumCulled = false; scene.add(this.points);
  }
  setScale(px: number): void { (this.points.material as THREE.ShaderMaterial).uniforms.uScale.value = px; }
  emit(x: number, y: number, z: number, vx: number, vy: number, vz: number, life: number, size: number, c: THREE.Color, drag = 2): void {
    const i = this.head; this.head = (this.head + 1) % this.cap;
    this.pos[i * 3] = x; this.pos[i * 3 + 1] = y; this.pos[i * 3 + 2] = z;
    this.vel[i * 3] = vx; this.vel[i * 3 + 1] = vy; this.vel[i * 3 + 2] = vz;
    this.col[i * 3] = c.r; this.col[i * 3 + 1] = c.g; this.col[i * 3 + 2] = c.b;
    this.life[i] = life; this.maxLife[i] = life; this.s0[i] = size; this.drag[i] = drag;
  }
  burst(x: number, z: number, n: number, speed: number, life: number, size: number, c: THREE.Color, rng = Math.random): void {
    for (let k = 0; k < n; k++) {
      const a = rng() * Math.PI * 2, s = speed * (0.3 + rng() * 0.7), up = (rng() - 0.3) * speed * 0.5;
      this.emit(x, 2, z, Math.cos(a) * s, up, Math.sin(a) * s, life * (0.5 + rng() * 0.5), size * (0.6 + rng() * 0.6), c);
    }
  }
  update(dt: number): void {
    let alive = 0;
    for (let i = 0; i < this.cap; i++) {
      if (this.life[i] <= 0) { this.alpha[i] = 0; this.size[i] = 0; continue; }
      alive++; this.life[i] -= dt; const t = Math.max(0, this.life[i] / this.maxLife[i]); const d = Math.max(0, 1 - this.drag[i] * dt);
      this.vel[i * 3] *= d; this.vel[i * 3 + 1] *= d; this.vel[i * 3 + 2] *= d;
      this.pos[i * 3] += this.vel[i * 3] * dt; this.pos[i * 3 + 1] += this.vel[i * 3 + 1] * dt; this.pos[i * 3 + 2] += this.vel[i * 3 + 2] * dt;
      this.alpha[i] = t; this.size[i] = this.s0[i] * (0.4 + 0.6 * t);
    }
    this.alive = alive;
    const g = this.points.geometry;
    for (const k of ["position", "color", "size", "alpha"]) g.attributes[k].needsUpdate = true;
  }
  clear(): void { this.life.fill(0); }
}

const NOISE = `
float h(vec3 p){ p=fract(p*0.3183099+.1); p*=17.0; return fract(p.x*p.y*p.z*(p.x+p.y+p.z)); }
float n3(vec3 x){ vec3 i=floor(x); vec3 f=fract(x); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(h(i),h(i+vec3(1,0,0)),f.x),mix(h(i+vec3(0,1,0)),h(i+vec3(1,1,0)),f.x),f.y),
            mix(mix(h(i+vec3(0,0,1)),h(i+vec3(1,0,1)),f.x),mix(h(i+vec3(0,1,1)),h(i+vec3(1,1,1)),f.x),f.y),f.z); }
float fbm(vec3 p){ float v=0.0,a=0.5; for(int i=0;i<5;i++){ v+=a*n3(p); p*=2.03; a*=0.5; } return v; }`;

/** Large background plane under the play field with a procedural nebula (scrolls slower = parallax). */
export function makeNebula(): THREE.Mesh {
  const m = new THREE.ShaderMaterial({
    uniforms: { uOff: { value: 0 }, uTime: { value: 0 } }, depthWrite: false,
    vertexShader: `varying vec2 vUv; void main(){ vUv=uv; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0); }`,
    fragmentShader: NOISE + `varying vec2 vUv; uniform float uOff; uniform float uTime;
      void main(){ vec2 p=vUv*vec2(3.0,6.0); p.y+=uOff;
        float n=fbm(vec3(p,uTime*0.02)); float n2=fbm(vec3(p*1.7+4.0,1.3));
        vec3 base=vec3(0.0024,0.0037,0.0091);
        vec3 c=base + vec3(0.05,0.022,0.12)*pow(n,2.6)*1.1 + vec3(0.006,0.07,0.075)*pow(n2,3.2)*1.0;
        float v=smoothstep(0.0,0.35,vUv.x)*smoothstep(1.0,0.65,vUv.x);
        c*=0.45+0.55*v; gl_FragColor=vec4(c,1.0); }`,
  });
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(1600, 2400), m);
  mesh.rotation.x = -Math.PI / 2; mesh.position.y = -260; mesh.renderOrder = -10; return mesh;
}

/** Layered starfield; layers at different depths + per-layer drift factor give parallax. Stars wrap around the camera in the vertex shader. */
export class Starfield {
  layers: THREE.Points[] = []; mats: THREE.ShaderMaterial[] = [];
  constructor(count: number, scene: THREE.Scene) {
    const depths = [-50, -130, -230]; const drift = [0.15, 0.35, 0.55]; const sizes = [2.6, 1.9, 1.4];
    depths.forEach((d, li) => {
      const n = Math.floor(count / 3); const pos = new Float32Array(n * 3); const col = new Float32Array(n * 3);
      for (let i = 0; i < n; i++) {
        pos[i * 3] = (Math.random() - 0.5) * 1000; pos[i * 3 + 1] = d + (Math.random() - 0.5) * 20; pos[i * 3 + 2] = Math.random() * 1600;
        const t = Math.random(); const c = new THREE.Color(t < 0.12 ? "#A78BFA" : t < 0.26 ? "#49E6D4" : t < 0.32 ? "#FFCC66" : "#EAF4FF");
        const b = (0.35 + Math.random() * 0.9) * (1 - li * 0.2); col[i * 3] = c.r * b; col[i * 3 + 1] = c.g * b; col[i * 3 + 2] = c.b * b;
      }
      const g = new THREE.BufferGeometry(); g.setAttribute("position", new THREE.BufferAttribute(pos, 3)); g.setAttribute("color", new THREE.BufferAttribute(col, 3));
      const m = new THREE.ShaderMaterial({
        uniforms: { uCam: { value: 0 }, uDrift: { value: drift[li] }, uSize: { value: sizes[li] }, uDpr: { value: 1 } }, vertexColors: true,
        transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
        vertexShader: `uniform float uCam; uniform float uDrift; uniform float uSize; uniform float uDpr; varying vec3 vC;
          void main(){ vC=color; vec3 p=position; float base=uCam*(1.0-uDrift);
            p.z = mod(p.z - base, 1600.0) - 800.0 + uCam; gl_PointSize=uSize*uDpr; gl_Position=projectionMatrix*modelViewMatrix*vec4(p,1.0); }`,
        fragmentShader: `varying vec3 vC; void main(){ vec2 d=gl_PointCoord-0.5; float r=dot(d,d)*4.0; if(r>1.0) discard; gl_FragColor=vec4(vC*(1.0-r),1.0); }`,
      });
      const p = new THREE.Points(g, m); p.frustumCulled = false; p.renderOrder = -5; scene.add(p); this.layers.push(p); this.mats.push(m);
    });
  }
  update(camZ: number, dpr: number): void { for (const m of this.mats) { m.uniforms.uCam.value = camZ; m.uniforms.uDpr.value = dpr; } }
}

/** Fresnel energy shield with up to 4 hit ripples. */
export function makeShieldMaterial(color: string): THREE.ShaderMaterial {
  return new THREE.ShaderMaterial({
    uniforms: { uColor: { value: new THREE.Color(color) }, uStrength: { value: 1 }, uTime: { value: 0 },
      uHits: { value: [new THREE.Vector4(), new THREE.Vector4(), new THREE.Vector4(), new THREE.Vector4()] } },
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.FrontSide,
    vertexShader: `varying vec3 vN; varying vec3 vV; varying vec3 vL; void main(){ vL=normalize(position); vec4 mv=modelViewMatrix*vec4(position,1.0);
      vN=normalize(normalMatrix*normal); vV=normalize(-mv.xyz); gl_Position=projectionMatrix*mv; }`,
    fragmentShader: `uniform vec3 uColor; uniform float uStrength; uniform float uTime; uniform vec4 uHits[4]; varying vec3 vN; varying vec3 vV; varying vec3 vL;
      void main(){ float f=pow(1.0-abs(dot(vN,vV)),2.5); float a=f*0.55*uStrength;
        float hex=0.5+0.5*sin(vL.x*40.0+uTime*2.0)*sin(vL.z*40.0);
        a+=f*hex*0.12*uStrength;
        for(int i=0;i<4;i++){ vec4 h=uHits[i]; if(h.w<=0.0) continue; float d=distance(vL,normalize(h.xyz)); float ring=1.0-smoothstep(0.0,0.18,abs(d-(1.0-h.w)*1.2));
          a+=ring*h.w*1.4; }
        gl_FragColor=vec4(uColor*a*1.6, 1.0); }`,
  });
}
/** Per-instance fresnel shield for enemies (InstancedMesh; alpha via instance color brightness). */
export function makeEnemyShieldMaterial(): THREE.ShaderMaterial {
  return new THREE.ShaderMaterial({
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
    vertexShader: `varying vec3 vN; varying vec3 vV; varying vec3 vC; void main(){ vC=instanceColor; vec4 mv=modelViewMatrix*instanceMatrix*vec4(position,1.0);
      vN=normalize(normalMatrix*mat3(instanceMatrix)*normal); vV=normalize(-mv.xyz); gl_Position=projectionMatrix*mv; }`,
    fragmentShader: `varying vec3 vN; varying vec3 vV; varying vec3 vC; void main(){ float f=pow(1.0-abs(dot(vN,vV)),2.2); gl_FragColor=vec4(vC*f*0.55,1.0); }`,
  });
}
/** Gravity well / ion vortex swirl disc. */
export function makeWellMaterial(): THREE.ShaderMaterial {
  return new THREE.ShaderMaterial({
    uniforms: { uTime: { value: 0 }, uIon: { value: 0 }, uFade: { value: 1 } }, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
    vertexShader: `varying vec2 vUv; void main(){ vUv=uv; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0); }`,
    fragmentShader: `uniform float uTime; uniform float uIon; uniform float uFade; varying vec2 vUv;
      void main(){ vec2 p=vUv*2.0-1.0; float r=length(p); if(r>1.0) discard; float a=atan(p.y,p.x);
        float sw=0.5+0.5*sin(a*3.0+r*14.0-uTime*6.0); float rim=smoothstep(0.8,1.0,r)*(1.0-smoothstep(0.97,1.0,r));
        float core=1.0-smoothstep(0.0,0.35,r);
        vec3 c1=vec3(0.50,0.36,0.98); vec3 c2=vec3(0.5,0.82,1.0); vec3 col=mix(c1,c2,uIon);
        float i=(sw*(1.0-r)*(1.0-r)*0.16 + rim*0.4 + core*0.05)*uFade; i*=1.0+uIon*0.35;
        gl_FragColor=vec4(col*i, 1.0); }`,
  });
}
/** Expanding ring (EMP blast, explosion shockwave, meteor warning). */
export function makeRingMaterial(color: string): THREE.ShaderMaterial {
  return new THREE.ShaderMaterial({
    uniforms: { uColor: { value: new THREE.Color(color) }, uT: { value: 0 } }, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
    vertexShader: `varying vec2 vUv; void main(){ vUv=uv; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0); }`,
    fragmentShader: `uniform vec3 uColor; uniform float uT; varying vec2 vUv; void main(){ float r=length(vUv*2.0-1.0); float w=0.08+0.1*(1.0-uT);
      float ring=1.0-smoothstep(0.0,w,abs(r-mix(0.2,1.0,uT))); float fill=(1.0-r)*0.15*(1.0-uT); float a=(ring+fill)*(1.0-uT);
      gl_FragColor=vec4(uColor*a*2.2,1.0); }`,
  });
}

/** Camera-facing-ish ribbon trail on the XZ plane (flat ribbon, width tapers, additive). */
export class Trail {
  mesh: THREE.Mesh; private pts: THREE.Vector3[] = []; private geo: THREE.BufferGeometry; private pos: Float32Array; private a: Float32Array;
  constructor(public n: number, public width: number, color: string, scene: THREE.Scene) {
    this.geo = new THREE.BufferGeometry(); this.pos = new Float32Array(n * 2 * 3); this.a = new Float32Array(n * 2);
    const idx: number[] = []; for (let i = 0; i < n - 1; i++) { const k = i * 2; idx.push(k, k + 1, k + 2, k + 1, k + 3, k + 2); }
    this.geo.setIndex(idx); this.geo.setAttribute("position", new THREE.BufferAttribute(this.pos, 3)); this.geo.setAttribute("a", new THREE.BufferAttribute(this.a, 1));
    const m = new THREE.ShaderMaterial({ uniforms: { uColor: { value: new THREE.Color(color) } }, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
      vertexShader: `attribute float a; varying float vA; void main(){ vA=a; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0); }`,
      fragmentShader: `uniform vec3 uColor; varying float vA; void main(){ gl_FragColor=vec4(uColor*vA*vA*2.0,1.0); }` });
    this.mesh = new THREE.Mesh(this.geo, m); this.mesh.frustumCulled = false; scene.add(this.mesh);
  }
  private ages: number[] = [];
  /** Adds a sample (spaced by distance) and ages old ones; trail length is time-bounded so low FPS can't stretch it. */
  push(p: THREE.Vector3, intensity: number, dt = 1 / 60, maxAge = 0.32): void {
    for (let i = 0; i < this.ages.length; i++) this.ages[i] += dt;
    const head = this.pts[0];
    if (!head || head.distanceToSquared(p) > 0.5) { this.pts.unshift(p.clone()); this.ages.unshift(0); } else head.copy(p);
    while (this.pts.length > this.n || (this.ages.length && this.ages[this.ages.length - 1] > maxAge)) { this.pts.pop(); this.ages.pop(); }
    const N = this.pts.length;
    for (let i = 0; i < this.n; i++) {
      const q = this.pts[Math.min(i, N - 1)] ?? p; const q2 = this.pts[Math.min(i + 1, N - 1)] ?? p;
      let dx = q.x - q2.x, dz = q.z - q2.z; const l = Math.hypot(dx, dz) || 1; dx /= l; dz /= l;
      const age = i < N ? this.ages[i] / maxAge : 1; const t = Math.max(0, 1 - age); const w = this.width * (0.35 + 0.65 * t);
      this.pos.set([q.x - dz * w, q.y, q.z + dx * w], i * 6); this.pos.set([q.x + dz * w, q.y, q.z - dx * w], i * 6 + 3);
      const al = i < N - 1 ? t * intensity : 0; this.a[i * 2] = al; this.a[i * 2 + 1] = al;
    }
    this.geo.attributes.position.needsUpdate = true; this.geo.attributes.a.needsUpdate = true;
  }
  reset(): void { this.pts = []; this.ages = []; this.a.fill(0); this.geo.attributes.a.needsUpdate = true; }
}
