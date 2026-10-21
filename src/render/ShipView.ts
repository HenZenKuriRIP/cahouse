// Builds a 3D ship from a ShipModel: one GLB clone per module on the shared grid (gameplay local (x,y) -> three (x,0,y)).
import * as THREE from "three";
import { Assets } from "./Assets";
import { ShipModel, CELL, unkey } from "../sim/ShipModel";
export class ShipView {
  group = new THREE.Group();
  thrusters: THREE.Vector3[] = []; // local exhaust points of main thrusters
  sideThrusters: THREE.Vector3[] = [];
  modules = new Map<string, THREE.Object3D>();
  showLoose = false;
  build(m: ShipModel, opts: { showAll?: boolean; ghostLoose?: boolean } = {}): void {
    this.group.clear(); this.modules.clear(); this.thrusters = []; this.sideThrusters = [];
    const core = m.coreCell();
    for (const [k, c] of m.cells) {
      const live = m.connected.has(k);
      if (!live && !opts.showAll) continue;
      const [x, y] = unkey(k);
      const o = Assets.clone("mod_" + c.id); o.scale.setScalar(CELL);
      o.position.set((x - core[0]) * CELL, 0, (y - core[1]) * CELL);
      if (c.id === "weapon_mount") o.rotation.y = -m.mountFacing(k);
      if (!live && opts.ghostLoose) o.traverse((n) => { const me = n as THREE.Mesh; if (me.isMesh) { const mm = (me.material as THREE.MeshStandardMaterial).clone(); mm.transparent = true; mm.opacity = 0.35; mm.emissive = new THREE.Color("#FF5268"); mm.emissiveIntensity = 0.6; me.material = mm; } });
      this.group.add(o); this.modules.set(k, o);
      if (live && c.id === "main_thruster") this.thrusters.push(new THREE.Vector3(o.position.x - CELL * 0.55, 0.3, o.position.z));
      if (live && c.id === "side_thruster") this.sideThrusters.push(o.position.clone());
    }
  }
}
