// Gameplay data copied verbatim from the Godot project (data/), so balance matches.
import energy from "../data/energy.json";
import modules from "../data/modules.json";
import synergies from "../data/synergies.json";
import waves from "../data/waves.json";
import enemies from "../data/enemies/enemies.json";
import asteroidField from "../data/environments/asteroid_field.json";
import defaultShip from "../data/ships/default_ship.json";
import pulse from "../data/weapons/pulse_cannon.json";
import missile from "../data/weapons/missile_swarm.json";
import bomb from "../data/weapons/gravity_bomb.json";
import emp from "../data/weapons/emp_launcher.json";
export const Data = {
  energy: energy as any, modules: modules as Record<string, any>, synergies: synergies as Record<string, any>,
  waves: waves as any, enemies: enemies as Record<string, any>, asteroidField: asteroidField as any,
  defaultShip: defaultShip as any,
  weapons: { pulse_cannon: pulse, missile_swarm: missile, gravity_bomb: bomb, emp_launcher: emp } as Record<string, any>,
};
