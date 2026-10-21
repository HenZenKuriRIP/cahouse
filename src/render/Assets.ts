// GLB asset loading (models authored by blender/build_models.py). Each model is normalized into a template Group.
import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
export const MODEL_NAMES = [
  "mod_core", "mod_cockpit", "mod_main_thruster", "mod_side_thruster", "mod_weapon_mount", "mod_shield_gen", "mod_armor", "mod_radiator",
  "enemy_scout", "enemy_interceptor", "enemy_bomber", "asteroid_a", "asteroid_b", "asteroid_c", "asteroid_ore", "proj_bullet", "proj_missile", "proj_bomb",
] as const;
export type ModelName = (typeof MODEL_NAMES)[number];
export interface MeshPart { geometry: THREE.BufferGeometry; material: THREE.MeshStandardMaterial; matrix: THREE.Matrix4 }
class AssetStore {
  models = new Map<string, THREE.Group>();
  parts = new Map<string, MeshPart[]>();
  tris = new Map<string, number>();
  loaded = 0;
  async load(onProgress?: (f: number) => void): Promise<void> {
    const loader = new GLTFLoader();
    await Promise.all(MODEL_NAMES.map(async (n) => {
      const g = await loader.loadAsync(`./models/${n}.glb`);
      const root = g.scene; root.updateMatrixWorld(true);
      const parts: MeshPart[] = []; let tris = 0;
      root.traverse((o) => {
        const m = o as THREE.Mesh;
        if (m.isMesh) {
          const mat = m.material as THREE.MeshStandardMaterial;
          mat.envMapIntensity = 0.9;
          // art-direction pass: keep light hull panels from washing out under ACES + env lighting
          if (mat.name.startsWith("hull_light")) { mat.color.set("#8392AD"); mat.roughness = 0.38; mat.metalness = 0.6; }
          if (mat.name.startsWith("hull_dark")) { mat.color.set("#1A2238"); }
          parts.push({ geometry: m.geometry, material: mat, matrix: m.matrixWorld.clone() });
          tris += (m.geometry.index ? m.geometry.index.count : m.geometry.attributes.position.count) / 3;
        }
      });
      this.models.set(n, root); this.parts.set(n, parts); this.tris.set(n, tris);
      this.loaded++; onProgress?.(this.loaded / MODEL_NAMES.length);
    }));
  }
  clone(n: string): THREE.Object3D { return this.models.get(n)!.clone(true); }
}
export const Assets = new AssetStore();

/** One InstancedMesh per sub-mesh of a model; set(i, matrix) places a full model instance. */
export class InstancedModel {
  meshes: THREE.InstancedMesh[] = [];
  private parts: MeshPart[];
  private tmp = new THREE.Matrix4();
  count = 0;
  constructor(name: string, public capacity: number, scene: THREE.Object3D, colorize = false) {
    this.parts = Assets.parts.get(name)!;
    for (const p of this.parts) {
      const im = new THREE.InstancedMesh(p.geometry, p.material, capacity);
      im.instanceMatrix.setUsage(THREE.DynamicDrawUsage); im.count = 0; im.frustumCulled = false;
      if (colorize) { im.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(capacity * 3).fill(1), 3); }
      scene.add(im); this.meshes.push(im);
    }
  }
  begin(): void { this.count = 0; }
  push(m: THREE.Matrix4, color?: THREE.Color): void {
    if (this.count >= this.capacity) return;
    for (let k = 0; k < this.parts.length; k++) {
      this.tmp.multiplyMatrices(m, this.parts[k].matrix);
      this.meshes[k].setMatrixAt(this.count, this.tmp);
      if (color && this.meshes[k].instanceColor) this.meshes[k].setColorAt(this.count, color);
    }
    this.count++;
  }
  end(): void {
    for (const im of this.meshes) { im.count = this.count; im.instanceMatrix.needsUpdate = true; if (im.instanceColor) im.instanceColor.needsUpdate = true; }
  }
}
