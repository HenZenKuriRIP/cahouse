// WebGL renderer + post chain (selective-by-threshold bloom, FXAA/MSAA, ACES output) + quality presets.
import * as THREE from "three";
import { EffectComposer } from "three/examples/jsm/postprocessing/EffectComposer.js";
import { RenderPass } from "three/examples/jsm/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/examples/jsm/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/examples/jsm/postprocessing/OutputPass.js";
import { FXAAPass } from "three/examples/jsm/postprocessing/FXAAPass.js";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";
export type Quality = "low" | "med" | "high";
export interface QualityCfg { dpr: number; bloom: boolean; bloomHalf: boolean; msaa: number; fxaa: boolean; particles: number; lights: number; stars: number }
export const QUALITY: Record<Quality, QualityCfg> = {
  low: { dpr: 1, bloom: false, bloomHalf: true, msaa: 0, fxaa: true, particles: 600, lights: 0, stars: 500 },
  med: { dpr: 1.5, bloom: true, bloomHalf: true, msaa: 0, fxaa: true, particles: 1500, lights: 2, stars: 1100 },
  high: { dpr: 2, bloom: true, bloomHalf: false, msaa: 4, fxaa: false, particles: 3000, lights: 4, stars: 1800 },
};
export function detectQuality(gl: WebGLRenderer2): Quality {
  const ctx = gl.getContext(); let rendererName = "";
  const ext = ctx.getExtension("WEBGL_debug_renderer_info");
  if (ext) rendererName = String(ctx.getParameter(ext.UNMASKED_RENDERER_WEBGL));
  if (/swiftshader|llvmpipe|software/i.test(rendererName)) return "low";
  const mobile = /Android|iPhone|iPad|Mobile/i.test(navigator.userAgent) || matchMedia("(pointer: coarse)").matches;
  return mobile ? "med" : "high";
}
type WebGLRenderer2 = THREE.WebGLRenderer;
export class Renderer {
  gl: THREE.WebGLRenderer; scene = new THREE.Scene(); camera: THREE.PerspectiveCamera;
  composer!: EffectComposer; bloom: UnrealBloomPass | null = null; quality: Quality = "med"; cfg: QualityCfg = QUALITY.med;
  gpuName = "";
  constructor(public canvas: HTMLCanvasElement) {
    this.gl = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: "high-performance", preserveDrawingBuffer: false });
    this.gl.toneMapping = THREE.ACESFilmicToneMapping; this.gl.toneMappingExposure = 1.05;
    this.gl.outputColorSpace = THREE.SRGBColorSpace; this.gl.info.autoReset = false;
    this.camera = new THREE.PerspectiveCamera(42, 1, 5, 3000);
    const pm = new THREE.PMREMGenerator(this.gl);
    this.scene.environment = pm.fromScene(new RoomEnvironment(), 0.04).texture;
    this.scene.environmentIntensity = 0.55;
    this.scene.background = new THREE.Color("#080C18");
    const ctx = this.gl.getContext(); const ext = ctx.getExtension("WEBGL_debug_renderer_info");
    this.gpuName = ext ? String(ctx.getParameter(ext.UNMASKED_RENDERER_WEBGL)) : "unknown";
  }
  setQuality(q: Quality): void {
    this.quality = q; this.cfg = QUALITY[q];
    const w = innerWidth, h = innerHeight; const dpr = Math.min(devicePixelRatio || 1, this.cfg.dpr, 2);
    this.gl.setPixelRatio(dpr); this.gl.setSize(w, h, false);
    const rt = new THREE.WebGLRenderTarget(w * dpr, h * dpr, { type: THREE.HalfFloatType, samples: this.cfg.msaa });
    this.composer?.dispose();
    this.composer = new EffectComposer(this.gl, rt);
    this.composer.setPixelRatio(dpr); this.composer.setSize(w, h);
    this.composer.addPass(new RenderPass(this.scene, this.camera));
    this.bloom = null;
    if (this.cfg.bloom) {
      const s = this.cfg.bloomHalf ? 0.5 : 1;
      this.bloom = new UnrealBloomPass(new THREE.Vector2(w * s, h * s), 0.55, 0.45, 0.92);
      this.composer.addPass(this.bloom);
    }
    this.composer.addPass(new OutputPass());
    if (this.cfg.fxaa) this.composer.addPass(new FXAAPass());
    this.resize();
  }
  resize(): void {
    const w = innerWidth, h = innerHeight;
    this.gl.setSize(w, h, false); this.composer.setSize(w, h);
    if (this.bloom) { const s = this.cfg.bloomHalf ? 0.5 : 1; this.bloom.resolution.set(w * s, h * s); }
    this.camera.aspect = w / h; this.camera.updateProjectionMatrix();
  }
  render(): void { this.gl.info.reset(); this.composer.render(); }
}
