"""VOID SIGNAL 3D - procedural hard-surface models (original assets).
Run: blender -b -P blender/build_models.py -- <out_dir>
Conventions (so three.js can assemble the modular ship on a grid):
  * Blender +X = ship forward, +Z = up. glTF export -> three.js: forward +X, up +Y.
  * Player modules fit a 1.0 x 1.0 cell centred on the origin (three.js scales by CELL=3 world units).
  * Enemies / asteroids / projectiles are normalised to radius 1 (three.js scales by gameplay radius).
  * Materials are Principled BSDF -> glTF PBR; emissive accents use the game palette.
Writes <out_dir>/<name>.glb and <out_dir>/manifest.json (triangle counts)."""
import bpy, bmesh, sys, os, json, math, random
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0] if argv else "public/models")
os.makedirs(OUT, exist_ok=True)

def hexc(h, a=1.0):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, a)

MATS = {}
def mat(name, base, metal=0.5, rough=0.4, emit=None, strength=0.0):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = hexc(base)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = hexc(emit)
        b.inputs["Emission Strength"].default_value = strength
    MATS[name] = m
    return m

def M():
    return {
        "hull": mat("hull_light", "#B8C4D9", 0.55, 0.32),
        "dark": mat("hull_dark", "#222B44", 0.6, 0.45),
        "trim": mat("trim", "#56637F", 0.7, 0.35),
        "accent": mat("accent_emit", "#49E6D4", 0.0, 0.3, "#49E6D4", 3.0),
        "danger": mat("danger_emit", "#FF5268", 0.0, 0.3, "#FF5268", 3.0),
        "energy": mat("energy_emit", "#FFCC66", 0.0, 0.3, "#FFCC66", 3.0),
        "rare": mat("rare_emit", "#A78BFA", 0.0, 0.3, "#A78BFA", 3.0),
        "glass": mat("glass", "#0E2233", 0.2, 0.08, "#7FD1FF", 0.6),
        "rock": mat("rock", "#3B4566", 0.05, 0.85),
        "rock2": mat("rock_dark", "#262D44", 0.05, 0.9),
        "ore": mat("ore_rock", "#5E4E35", 0.1, 0.8),
        "white": mat("white_emit", "#EAF4FF", 0.0, 0.2, "#EAF4FF", 2.0),
    }

def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes,):
        for x in list(block):
            if x.users == 0:
                block.remove(x)

def finish(o, material, bevel=0.0, segs=2, smooth=False):
    o.data.materials.clear()
    o.data.materials.append(material)
    if bevel > 0:
        md = o.modifiers.new("bevel", "BEVEL")
        md.width = bevel
        md.segments = segs
        md.limit_method = "ANGLE"
        md.harden_normals = False
    if smooth:
        for p in o.data.polygons:
            p.use_smooth = True
    return o

def box(size, loc, material, bevel=0.03, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    return finish(o, material, bevel)

def cyl(r, depth, loc, material, verts=12, rot=(0, 0, 0), bevel=0.02, r2=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=depth, location=loc, rotation=rot)
    o = bpy.context.object
    bpy.ops.object.transform_apply(rotation=True)
    return finish(o, material, bevel, smooth=verts >= 12)

def sphere(r, loc, material, scale=(1, 1, 1), sub=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=r, location=loc)
    o = bpy.context.object
    o.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return finish(o, material, 0, smooth=True)

def torus(R, r, loc, material, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=24, minor_segments=8, location=loc, rotation=rot)
    o = bpy.context.object
    bpy.ops.object.transform_apply(rotation=True)
    return finish(o, material, 0, smooth=True)

def wedge(pts_xy, z0, z1, material, bevel=0.03):
    """Extruded polygon (top view outline, +X forward)."""
    me = bpy.data.meshes.new("wedge")
    bm = bmesh.new()
    bot = [bm.verts.new((x, y, z0)) for x, y in pts_xy]
    top = [bm.verts.new((x, y, z1)) for x, y in pts_xy]
    bm.faces.new(list(reversed(bot)))
    bm.faces.new(top)
    n = len(pts_xy)
    for i in range(n):
        bm.faces.new([bot[i], bot[(i + 1) % n], top[(i + 1) % n], top[i]])
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("wedge", me)
    bpy.context.collection.objects.link(o)
    return finish(o, material, bevel)

MANIFEST = {}
def export(name, kind):
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    for o in objs:
        bpy.context.view_layer.objects.active = o
        for md in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=md.name)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = name
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_materials="EXPORT")
    MANIFEST[name] = {"kind": kind, "tris": tris, "bytes": os.path.getsize(path)}
    print("[MODEL] %-16s tris=%5d bytes=%d" % (name, tris, os.path.getsize(path)))
    clear()

# ---------------- player modules (1x1 cell) ----------------
def deck(m, h=0.12, col="dark"):
    """Common floor plate that keeps modules visually connected on the grid."""
    box((0.94, 0.94, h), (0, 0, h / 2), m[col], 0.04)

def mod_core(m):
    deck(m)
    cyl(0.40, 0.22, (0, 0, 0.22), m["trim"], 8, bevel=0.03)
    cyl(0.30, 0.08, (0, 0, 0.36), m["hull"], 8, bevel=0.02)
    sphere(0.17, (0, 0, 0.44), m["accent"], sub=2)
    for a in range(4):
        ang = a * math.pi / 2 + math.pi / 4
        box((0.14, 0.06, 0.06), (math.cos(ang) * 0.33, math.sin(ang) * 0.33, 0.36), m["accent"], 0.01, rot=(0, 0, ang))

def mod_cockpit(m):
    deck(m)
    wedge([(0.47, 0), (0.2, 0.38), (-0.45, 0.4), (-0.45, -0.4), (0.2, -0.38)], 0.12, 0.34, m["hull"], 0.04)
    sphere(0.26, (0.02, 0, 0.36), m["glass"], scale=(1.5, 0.95, 0.55))
    box((0.5, 0.04, 0.03), (-0.1, 0.34, 0.35), m["accent"], 0.0)
    box((0.5, 0.04, 0.03), (-0.1, -0.34, 0.35), m["accent"], 0.0)

def mod_main_thruster(m):
    deck(m)
    box((0.7, 0.72, 0.26), (0.08, 0, 0.25), m["hull"], 0.05)
    cyl(0.28, 0.42, (-0.3, 0, 0.26), m["trim"], 16, rot=(0, math.pi / 2, 0), r2=0.34)
    cyl(0.22, 0.04, (-0.52, 0, 0.26), m["energy"], 16, rot=(0, math.pi / 2, 0))
    box((0.5, 0.06, 0.04), (0.15, 0.3, 0.39), m["energy"], 0.0)
    box((0.5, 0.06, 0.04), (0.15, -0.3, 0.39), m["energy"], 0.0)

def mod_side_thruster(m):
    deck(m)
    box((0.6, 0.5, 0.2), (0, 0, 0.22), m["hull"], 0.05)
    for s in (1, -1):
        cyl(0.11, 0.24, (-0.05, s * 0.33, 0.22), m["trim"], 12, rot=(math.pi / 2, 0, 0), r2=0.14)
        cyl(0.08, 0.02, (-0.05, s * 0.46, 0.22), m["energy"], 12, rot=(math.pi / 2, 0, 0))
    cyl(0.1, 0.3, (-0.38, 0, 0.22), m["trim"], 12, rot=(0, math.pi / 2, 0), r2=0.13)

def mod_weapon_mount(m):
    deck(m)
    cyl(0.32, 0.16, (0, 0, 0.2), m["trim"], 12, bevel=0.03)
    box((0.42, 0.36, 0.18), (0.02, 0, 0.36), m["hull"], 0.05)
    cyl(0.06, 0.55, (0.38, 0.09, 0.38), m["dark"], 10, rot=(0, math.pi / 2, 0))
    cyl(0.06, 0.55, (0.38, -0.09, 0.38), m["dark"], 10, rot=(0, math.pi / 2, 0))
    box((0.06, 0.38, 0.03), (-0.12, 0, 0.46), m["danger"], 0.0)

def mod_shield_gen(m):
    deck(m)
    cyl(0.3, 0.2, (0, 0, 0.22), m["hull"], 10, bevel=0.03)
    torus(0.32, 0.04, (0, 0, 0.38), m["rare"])
    sphere(0.14, (0, 0, 0.42), m["rare"], sub=2)
    for a in range(3):
        ang = a * 2 * math.pi / 3
        box((0.05, 0.05, 0.22), (math.cos(ang) * 0.22, math.sin(ang) * 0.22, 0.38), m["trim"], 0.01)

def mod_armor(m):
    deck(m, 0.14, "trim")
    wedge([(0.44, 0.3), (0.3, 0.44), (-0.3, 0.44), (-0.44, 0.3), (-0.44, -0.3), (-0.3, -0.44), (0.3, -0.44), (0.44, -0.3)], 0.14, 0.34, m["hull"], 0.05)
    box((0.6, 0.12, 0.04), (0, 0, 0.36), m["dark"], 0.01)
    box((0.12, 0.6, 0.04), (0, 0, 0.36), m["dark"], 0.01)

def mod_radiator(m):
    deck(m)
    box((0.8, 0.3, 0.1), (0, 0, 0.17), m["trim"], 0.02)
    for i in range(7):
        x = -0.36 + i * 0.12
        box((0.04, 0.82, 0.26), (x, 0, 0.3), m["hull"], 0.01)
    box((0.76, 0.06, 0.03), (0, 0, 0.44), m["accent"], 0.0)

# ---------------- enemies (radius 1, nose +X) ----------------
def en_scout(m):
    wedge([(1.0, 0), (-0.55, 0.75), (-0.3, 0), (-0.55, -0.75)], -0.15, 0.15, m["hull"], 0.04)
    wedge([(0.55, 0), (-0.2, 0.25), (-0.2, -0.25)], 0.15, 0.32, m["dark"], 0.03)
    box((0.08, 0.5, 0.06), (-0.35, 0.42, 0.12), m["danger"], 0.0, rot=(0, 0, 0.5))
    box((0.08, 0.5, 0.06), (-0.35, -0.42, 0.12), m["danger"], 0.0, rot=(0, 0, -0.5))
    sphere(0.12, (0.2, 0, 0.3), m["danger"], sub=1)
    cyl(0.12, 0.05, (-0.34, 0, 0.0), m["danger"], 10, rot=(0, math.pi / 2, 0))

def en_interceptor(m):
    box((1.3, 0.34, 0.26), (0.1, 0, 0), m["hull"], 0.06)
    for s in (1, -1):
        wedge([(0.25, s * 0.15), (-0.6, s * 1.0), (-0.85, s * 0.95), (-0.35, s * 0.15)], -0.06, 0.06, m["dark"], 0.03)
        box((0.5, 0.05, 0.05), (-0.45, s * 0.7, 0.07), m["rare"], 0.0, rot=(0, 0, -s * 0.9))
        cyl(0.07, 0.4, (0.35, s * 0.24, -0.02), m["trim"], 8, rot=(0, math.pi / 2, 0))
    sphere(0.16, (0.45, 0, 0.16), m["glass"], scale=(1.6, 0.9, 0.6))
    cyl(0.13, 0.04, (-0.57, 0, 0), m["rare"], 10, rot=(0, math.pi / 2, 0))

def en_bomber(m):
    wedge([(0.75, 0.35), (0.5, 0.7), (-0.6, 0.7), (-0.8, 0.45), (-0.8, -0.45), (-0.6, -0.7), (0.5, -0.7), (0.75, -0.35)], -0.25, 0.22, m["hull"], 0.06)
    box((0.9, 0.7, 0.16), (-0.05, 0, 0.3), m["dark"], 0.05)
    for s in (1, -1):
        cyl(0.2, 0.9, (-0.05, s * 0.85, -0.05), m["trim"], 12, rot=(0, math.pi / 2, 0))
        cyl(0.15, 0.04, (-0.52, s * 0.85, -0.05), m["energy"], 12, rot=(0, math.pi / 2, 0))
        box((0.5, 0.05, 0.04), (0.1, s * 0.5, 0.25), m["energy"], 0.0)
    sphere(0.18, (0.45, 0, 0.3), m["energy"], sub=1)

# ---------------- asteroids / projectiles ----------------
def rock(m, seed, ore=False):
    random.seed(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0)
    o = bpy.context.object
    for v in o.data.vertices:
        n = v.co.normalized()
        k = 0.78 + random.random() * 0.28
        v.co = n * k
        v.co.z *= 0.75
    finish(o, m["ore"] if ore else m["rock"], 0)
    if ore:
        for i in range(5):
            a = random.random() * math.tau
            el = random.uniform(-0.3, 0.6)
            d = Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el)))
            cyl(0.12, 0.55, tuple(d * 0.75), m["energy"], 5, r2=0.0, bevel=0)
            c = bpy.context.object
            c.rotation_mode = "QUATERNION"
            c.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d)
            bpy.ops.object.transform_apply(rotation=True)
    else:
        for i in range(3):
            a = random.random() * math.tau
            sphere(0.28, (math.cos(a) * 0.62, math.sin(a) * 0.62, 0.32), m["rock2"], scale=(1, 1, 0.35), sub=1)

def proj_bullet(m):
    sphere(0.5, (0, 0, 0), m["white"], scale=(2.2, 0.55, 0.55), sub=2)

def proj_missile(m):
    cyl(0.18, 1.3, (0, 0, 0), m["hull"], 10, rot=(0, math.pi / 2, 0), bevel=0)
    cyl(0.18, 0.4, (0.85, 0, 0), m["danger"], 10, rot=(0, math.pi / 2, 0), r2=0.0, bevel=0)
    for a in range(4):
        ang = a * math.pi / 2
        box((0.35, 0.03, 0.22), (-0.5, math.cos(ang) * 0.2, math.sin(ang) * 0.2), m["trim"], 0.0, rot=(ang, 0, 0))
    cyl(0.13, 0.05, (-0.67, 0, 0), m["energy"], 10, rot=(0, math.pi / 2, 0), bevel=0)

def proj_bomb(m):
    sphere(0.6, (0, 0, 0), m["dark"], sub=2)
    torus(0.62, 0.08, (0, 0, 0), m["rare"])
    torus(0.62, 0.08, (0, 0, 0), m["rare"], rot=(math.pi / 2, 0, 0))

BUILD = [
    ("mod_core", "module", mod_core), ("mod_cockpit", "module", mod_cockpit), ("mod_main_thruster", "module", mod_main_thruster),
    ("mod_side_thruster", "module", mod_side_thruster), ("mod_weapon_mount", "module", mod_weapon_mount),
    ("mod_shield_gen", "module", mod_shield_gen), ("mod_armor", "module", mod_armor), ("mod_radiator", "module", mod_radiator),
    ("enemy_scout", "enemy", en_scout), ("enemy_interceptor", "enemy", en_interceptor), ("enemy_bomber", "enemy", en_bomber),
    ("asteroid_a", "asteroid", lambda m: rock(m, 11)), ("asteroid_b", "asteroid", lambda m: rock(m, 23)),
    ("asteroid_c", "asteroid", lambda m: rock(m, 37)), ("asteroid_ore", "asteroid", lambda m: rock(m, 51, True)),
    ("proj_bullet", "projectile", proj_bullet), ("proj_missile", "projectile", proj_missile), ("proj_bomb", "projectile", proj_bomb),
]
clear()
for name, kind, fn in BUILD:
    fn(M())
    export(name, kind)
with open(os.path.join(OUT, "manifest.json"), "w") as f:
    json.dump(MANIFEST, f, indent=1)
print("[MODEL] total tris=%d files=%d" % (sum(v["tris"] for v in MANIFEST.values()), len(MANIFEST)))
