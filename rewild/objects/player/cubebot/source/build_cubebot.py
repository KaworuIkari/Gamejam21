"""Procedurally builds the CubeBot character (mesh + rig + animations) and exports it to glTF.

Run headless from the repo root:
    /Applications/Blender.app/Contents/MacOS/Blender -b -P rewild/objects/player/cubebot/source/build_cubebot.py

Outputs (next to this folder):
    ../cubebot.glb          the asset Godot imports
    ./cubebot.blend         editable source (this folder has a .gdignore so Godot skips it)

Conventions: Blender Z-up, character faces -Y (becomes +Z in Godot). 1 unit = 1 m, ~1 m tall.
Every part is rigidly skinned to one bone, so the mesh never stretches.
Legs are animated with an IK rig, then baked to plain FK keys; the IK/pole helper bones are
not exported (export_def_bones), so Godot only sees the deform skeleton.
"""

import math
import os

import bmesh
import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
GLB_PATH = os.path.join(HERE, "..", "cubebot.glb")
BLEND_PATH = os.path.join(HERE, "cubebot.blend")
FPS = 30

# --- key dimensions -------------------------------------------------------------------------
BODY_W, BODY_D, BODY_H = 0.72, 0.68, 0.58
HIP_Z = 0.42
BODY_Z = HIP_Z + 0.02 + BODY_H / 2          # body cube center
FRONT_Y = -BODY_D / 2
LEG_X = 0.18
EYE_Z = BODY_Z - 0.02
EYE_R = 0.25                                # housing radius -- the big lens

# per-leg joint positions for the left leg (-X); right leg mirrors x
HIP = Vector((-LEG_X, 0.0, HIP_Z))
KNEE = Vector((-LEG_X, 0.08, 0.25))
ANKLE = Vector((-LEG_X, -0.01, 0.09))
TOE = Vector((-LEG_X, -0.14, 0.04))


def mirror(v, side):
    return Vector((v.x * (1 if side == "L" else -1), v.y, v.z))


# --- scene reset ----------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS


# --- materials ------------------------------------------------------------------------------
def make_mat(name, color, rough=0.5, metal=0.0, emit=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    return m


MATS = [
    make_mat("Shell", (0.74, 0.75, 0.78), rough=0.42),
    make_mat("Trim", (0.32, 0.33, 0.37), rough=0.45, metal=0.2),
    make_mat("Dark", (0.07, 0.07, 0.085), rough=0.5, metal=0.1),
    make_mat("LensDark", (0.02, 0.02, 0.03), rough=0.12, metal=0.4),
    # Godot drives these two at runtime (blue <-> yellow). Keep the names stable.
    make_mat("EyeGlow", (0.25, 0.65, 1.0), rough=0.2, emit=(0.25, 0.65, 1.0), strength=4.0),
    make_mat("EyeCore", (0.8, 0.93, 1.0), rough=0.1, emit=(0.8, 0.93, 1.0), strength=8.0),
    make_mat("Accent", (0.9, 0.25, 0.72), rough=0.35, emit=(1.0, 0.3, 0.8), strength=0.35),
]
MAT_INDEX = {m.name: i for i, m in enumerate(MATS)}

BONES = ["root", "body", "eye", "ear_L", "ear_R",
         "thigh_L", "shin_L", "foot_L", "thigh_R", "shin_R", "foot_R"]


# --- mesh building --------------------------------------------------------------------------
main_bm = bmesh.new()
deform = main_bm.verts.layers.deform.verify()


def commit(part, matrix, mat, bone, smooth=True):
    """Copy a temp bmesh into the combined mesh, rigidly weighted to `bone`."""
    gi = BONES.index(bone)
    vmap = {}
    for v in part.verts:
        nv = main_bm.verts.new(matrix @ v.co)
        nv[deform][gi] = 1.0
        vmap[v] = nv
    for f in part.faces:
        nf = main_bm.faces.new([vmap[v] for v in f.verts])
        nf.material_index = MAT_INDEX[mat]
        nf.smooth = smooth
    part.free()


def bevel_all(bm, width, segs):
    if width > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=width, segments=segs,
                        profile=0.5, affect="EDGES", clamp_overlap=True)


def box(size, bevel=0.0, segs=3):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bevel_all(bm, bevel, segs)
    return bm


def cyl(radius, depth, bevel=0.0, segs=40, radius2=None):
    """Cylinder along +Z centered at origin."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs,
                          radius1=radius, radius2=radius if radius2 is None else radius2,
                          depth=depth)
    if bevel > 0:
        bm.normal_update()
        rim = [e for e in bm.edges
               if abs(abs(e.link_faces[0].normal.z) - abs(e.link_faces[1].normal.z)) > 0.5]
        bmesh.ops.bevel(bm, geom=rim, offset=bevel, segments=3, profile=0.5,
                        affect="EDGES", clamp_overlap=True)
    return bm


def sphere(radius, u=40, v=20):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=radius)
    return bm


def torus(major, minor, seg=48, ring=12):
    bm = bmesh.new()
    rows = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        row = []
        for j in range(ring):
            b = 2 * math.pi * j / ring
            r = major + minor * math.cos(b)
            row.append(bm.verts.new((r * math.cos(a), r * math.sin(a), minor * math.sin(b))))
        rows.append(row)
    for i in range(seg):
        for j in range(ring):
            bm.faces.new([rows[i][j], rows[(i + 1) % seg][j],
                          rows[(i + 1) % seg][(j + 1) % ring], rows[i][(j + 1) % ring]])
    return bm


def heart(size, depth):
    """Flat heart in XY, extruded along +Z."""
    bm = bmesh.new()
    pts = []
    for i in range(48):
        t = 2 * math.pi * i / 48
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append(bm.verts.new((x / 32 * size, (y + 2) / 32 * size, 0)))
    face = bm.faces.new(pts)
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    bmesh.ops.translate(bm, vec=(0, 0, depth),
                        verts=[e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


T = Matrix.Translation
RX = lambda a: Matrix.Rotation(a, 4, "X")
RY = lambda a: Matrix.Rotation(a, 4, "Y")
FACE_FRONT = RX(math.pi / 2)    # maps +Z (cylinder axis) to -Y (front)
FACE_SIDE = RY(math.pi / 2)     # maps +Z to +X


def segment(p0, p1, w, d, bevel):
    """Rounded box spanning p0->p1 (in the YZ plane), w along X."""
    v = p1 - p0
    rot = v.to_track_quat("Z", "X").to_matrix().to_4x4()
    return box((w, d, v.length), bevel), T((p0 + p1) / 2) @ rot


# body shell
commit(box((BODY_W, BODY_D, BODY_H), bevel=0.07, segs=4), T((0, 0, BODY_Z)), "Shell", "body")
# underside plate the legs plug into
commit(box((0.5, 0.36, 0.06), bevel=0.02), T((0, 0.0, HIP_Z + 0.02)), "Dark", "body")
# top vent + back panel
for i in range(3):
    commit(box((0.2, 0.025, 0.012), bevel=0.005), T((0, -0.16 + i * 0.05, BODY_Z + BODY_H / 2 + 0.003)), "Dark", "body")
commit(box((0.34, 0.02, 0.22), bevel=0.01), T((0, BODY_D / 2 + 0.002, BODY_Z)), "Trim", "body")

# --- the big eye ---
commit(cyl(EYE_R + 0.03, 0.05, bevel=0.012), T((0, FRONT_Y - 0.01, EYE_Z)) @ FACE_FRONT, "Trim", "body")
commit(cyl(EYE_R, 0.08, bevel=0.01), T((0, FRONT_Y - 0.04, EYE_Z)) @ FACE_FRONT, "LensDark", "body")
commit(torus(EYE_R - 0.005, 0.018), T((0, FRONT_Y - 0.085, EYE_Z)) @ FACE_FRONT, "Shell", "body")
# glowing lens: a flattened dome, plus a hot core that pokes out of it
lens = sphere(EYE_R - 0.04)
bmesh.ops.scale(lens, vec=(1, 1, 0.35), verts=lens.verts)
commit(lens, T((0, FRONT_Y - 0.08, EYE_Z)) @ FACE_FRONT, "EyeGlow", "eye")
core = sphere(0.085, 32, 16)
bmesh.ops.scale(core, vec=(1, 1, 0.5), verts=core.verts)
commit(core, T((0, FRONT_Y - 0.13, EYE_Z)) @ FACE_FRONT, "EyeCore", "eye")

# heart badge, upper-left as seen from the front
commit(heart(0.11, 0.012), T((-0.25, FRONT_Y + 0.004, BODY_Z + 0.2)) @ FACE_FRONT, "Accent", "body")

# --- left ear: round speaker disc with a pink ring ---
EAR_L = Vector((-BODY_W / 2, 0.0, BODY_Z + 0.08))
commit(cyl(0.12, 0.05, bevel=0.012), T(EAR_L + Vector((-0.02, 0, 0))) @ FACE_SIDE, "Trim", "ear_L")
commit(torus(0.09, 0.016), T(EAR_L + Vector((-0.05, 0, 0))) @ FACE_SIDE, "Accent", "ear_L")
commit(cyl(0.055, 0.04, bevel=0.01), T(EAR_L + Vector((-0.055, 0, 0))) @ FACE_SIDE, "Shell", "ear_L")

# --- right ear: boxy camera pod with pink vents ---
EAR_R = Vector((BODY_W / 2, 0.0, BODY_Z + 0.08))
commit(box((0.13, 0.17, 0.15), bevel=0.025), T(EAR_R + Vector((0.06, 0, 0))), "Shell", "ear_R")
for i in range(3):
    commit(box((0.018, 0.012, 0.1), bevel=0.004),
           T(EAR_R + Vector((0.03 + i * 0.03, -0.087, 0))), "Accent", "ear_R")
commit(cyl(0.06, 0.03, bevel=0.008), T(EAR_R + Vector((0.135, 0, 0))) @ FACE_SIDE, "Dark", "ear_R")
commit(cyl(0.04, 0.02, bevel=0.006), T(EAR_R + Vector((0.155, 0, 0))) @ FACE_SIDE, "Accent", "ear_R")

# --- legs ---
for side in ("L", "R"):
    hip, knee, ankle, toe = (mirror(p, side) for p in (HIP, KNEE, ANKLE, TOE))
    s = "_" + side
    # hip joint + thigh
    commit(cyl(0.065, 0.12, bevel=0.012), T(hip) @ FACE_SIDE, "Dark", "thigh" + s)
    bm, m = segment(hip, knee, 0.12, 0.13, 0.03)
    commit(bm, m, "Shell", "thigh" + s)
    # knee joint + shin
    commit(cyl(0.058, 0.13, bevel=0.012), T(knee) @ FACE_SIDE, "Dark", "shin" + s)
    bm, m = segment(knee, ankle, 0.1, 0.1, 0.025)
    commit(bm, m, "Trim", "shin" + s)
    bm, m = segment(knee.lerp(ankle, 0.15), knee.lerp(ankle, 0.75), 0.115, 0.06, 0.02)
    commit(bm, T(Vector((0, -0.03, 0))) @ m, "Shell", "shin" + s)   # front shin guard
    # ankle + foot
    commit(cyl(0.045, 0.11, bevel=0.01), T(ankle) @ FACE_SIDE, "Dark", "foot" + s)
    commit(box((0.16, 0.25, 0.07), bevel=0.025), T((hip.x, -0.045, 0.06)), "Shell", "foot" + s)
    commit(box((0.17, 0.27, 0.03), bevel=0.01), T((hip.x, -0.045, 0.015)), "Dark", "foot" + s)

mesh = bpy.data.meshes.new("CubeBot")
main_bm.to_mesh(mesh)
main_bm.free()
for m in MATS:
    mesh.materials.append(m)
mesh.set_sharp_from_angle(angle=math.radians(40))

body_obj = bpy.data.objects.new("CubeBot", mesh)
scene.collection.objects.link(body_obj)
for name in BONES:
    body_obj.vertex_groups.new(name=name)


# --- armature -------------------------------------------------------------------------------
arm_data = bpy.data.armatures.new("CubeBotRig")
arm = bpy.data.objects.new("CubeBotRig", arm_data)
scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
eb = arm_data.edit_bones


def bone(name, head, tail, parent=None, deform=True, roll=0.0):
    b = eb.new(name)
    b.head, b.tail, b.roll = Vector(head), Vector(tail), roll
    b.use_deform = deform
    if parent:
        b.parent = eb[parent]
    return b


bone("root", (0, 0, 0), (0, 0.25, 0))
bone("body", (0, 0, HIP_Z), (0, 0, BODY_Z + BODY_H / 2), "root")
bone("eye", (0, FRONT_Y - 0.08, EYE_Z), (0, FRONT_Y - 0.25, EYE_Z), "body")
bone("ear_L", EAR_L, EAR_L + Vector((-0.15, 0, 0)), "body")
bone("ear_R", EAR_R, EAR_R + Vector((0.15, 0, 0)), "body")
for side in ("L", "R"):
    hip, knee, ankle, toe = (mirror(p, side) for p in (HIP, KNEE, ANKLE, TOE))
    bone("thigh_" + side, hip, knee, "body")
    bone("shin_" + side, knee, ankle, "thigh_" + side).use_connect = True
    bone("foot_" + side, ankle, toe, "shin_" + side).use_connect = True
    # animation helpers (not exported)
    bone("ik_foot_" + side, ankle, toe, "root", deform=False)
    bone("pole_" + side, knee + Vector((0, 0.5, 0)), knee + Vector((0, 0.6, 0)), "body", deform=False)
bpy.ops.object.mode_set(mode="OBJECT")

body_obj.parent = arm
mod = body_obj.modifiers.new("Armature", "ARMATURE")
mod.object = arm

# IK constraints
for side in ("L", "R"):
    ik = arm.pose.bones["shin_" + side].constraints.new("IK")
    ik.target, ik.subtarget = arm, "ik_foot_" + side
    ik.pole_target, ik.pole_subtarget = arm, "pole_" + side
    ik.chain_count = 2
    cr = arm.pose.bones["foot_" + side].constraints.new("COPY_ROTATION")
    cr.target, cr.subtarget = arm, "ik_foot_" + side

pb = arm.pose.bones
REST = {b.name: b.matrix_local.copy() for b in arm_data.bones}
DEFORM = [n for n in BONES]


def update():
    bpy.context.view_layer.update()


def leg_error():
    err = 0.0
    for side in ("L", "R"):
        for n in ("thigh_", "shin_"):
            err += (pb[n + side].matrix.to_translation() - REST[n + side].to_translation()).length
            err += (pb[n + side].matrix.col[1].xyz - REST[n + side].col[1].xyz).length
    return err


# pick the pole angle that keeps the rest pose intact
best = None
for ang in (0, 90, -90, 180):
    for side in ("L", "R"):
        pb["shin_" + side].constraints["IK"].pole_angle = math.radians(ang)
    update()
    e = leg_error()
    if best is None or e < best[1]:
        best = (ang, e)
for side in ("L", "R"):
    pb["shin_" + side].constraints["IK"].pole_angle = math.radians(best[0])
update()
print(f"[cubebot] pole angle {best[0]} deg, rest error {best[1]:.5f}")


# --- pose helpers ---------------------------------------------------------------------------
PIVOT = Vector((0, 0, HIP_Z))


class Pose:
    def __init__(self):
        self.body_off = Vector((0, 0, 0))
        self.body_rot = Euler((0, 0, 0))   # x = lean forward (+), y = roll, z = yaw
        self.feet = {"L": (Vector((0, 0, 0)), 0.0), "R": (Vector((0, 0, 0)), 0.0)}  # offset, pitch (+ = toe down)
        self.ears = {"L": Euler((0, 0, 0)), "R": Euler((0, 0, 0))}
        self.eye = Vector((1, 1, 1))


def apply_pose(p):
    for b in pb:
        b.matrix_basis = Matrix.Identity(4)
    update()
    rot = p.body_rot.to_matrix().to_4x4()
    pb["body"].matrix = T(p.body_off) @ T(PIVOT) @ rot @ T(-PIVOT) @ REST["body"]
    for side in ("L", "R"):
        off, pitch = p.feet[side]
        a = mirror(ANKLE, side)
        pb["ik_foot_" + side].matrix = T(off) @ T(a) @ RX(-pitch) @ T(-a) @ REST["ik_foot_" + side]
    update()
    for side in ("L", "R"):
        pb["ear_" + side].rotation_quaternion = p.ears[side].to_quaternion()
    pb["eye"].scale = p.eye
    update()


def capture():
    """Visual (constraint-evaluated) local transforms of every deform bone."""
    out = {}
    for n in DEFORM:
        b = pb[n]
        out[n] = arm.convert_space(pose_bone=b, matrix=b.matrix, from_space="POSE", to_space="LOCAL")
    return out


ANIMS = {}   # name -> (frames, loop, fn(frame)->Pose)


def anim(name, frames, loop):
    def deco(fn):
        ANIMS[name] = (frames, loop, fn)
        return fn
    return deco


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def gait(phase, stride, duty, lift):
    """Foot offset/pitch for one leg; phase 0 = heel strike at the front."""
    phase %= 1.0
    if phase < duty:
        s = phase / duty
        return Vector((0, -stride / 2 + stride * s, 0)), 0.0
    s = (phase - duty) / (1 - duty)
    y = stride / 2 - stride * smooth(s)
    z = lift * math.sin(math.pi * s)
    pitch = 0.5 * math.sin(math.pi * s) * (1 - s) - 0.25 * math.sin(math.pi * s) * s
    return Vector((0, y, z)), pitch


def ear_wobble(t, amp):
    return ({"L": Euler((amp * math.sin(t), 0, 0)), "R": Euler((-amp * math.sin(t + 0.6), 0, 0))})


IDLE_Z = -0.01


@anim("Idle", 60, True)
def idle(f):
    t = 2 * math.pi * f / 60
    p = Pose()
    p.body_off.z = IDLE_Z - 0.012 * (1 - math.cos(t)) / 2
    p.body_rot = Euler((0.015 * math.sin(t), 0.02 * math.sin(t + 0.5), 0))
    p.ears = ear_wobble(t, 0.08)
    blink = max(0.0, 1 - abs(f - 40) / 3)          # quick blink around frame 40
    p.eye = Vector((1 + 0.03 * math.sin(2 * t), 1, 1 - 0.85 * blink))
    return p


def locomotion(f, n, stride, duty, lift, bob, base_z, lean, sway):
    ph = f / n
    t = 2 * math.pi * ph
    p = Pose()
    for side, off in (("L", 0.0), ("R", 0.5)):
        p.feet[side] = gait(ph + off, stride, duty, lift)
    mid_stance = duty / 2
    p.body_off.z = base_z - bob * math.cos(4 * math.pi * (ph - mid_stance))
    p.body_rot = Euler((lean + 0.03 * math.cos(4 * math.pi * ph), sway * math.sin(t), 0.6 * sway * math.sin(t)))
    p.ears = ear_wobble(2 * t, 0.15 + lean)
    return p


@anim("Walk", 18, True)
def walk(f):
    return locomotion(f, 18, stride=0.26, duty=0.6, lift=0.07, bob=0.012, base_z=-0.025, lean=0.06, sway=0.05)


@anim("Run", 14, True)
def run(f):
    return locomotion(f, 14, stride=0.36, duty=0.4, lift=0.12, bob=0.022, base_z=-0.06, lean=0.18, sway=0.04)


@anim("Jump_Start", 12, False)
def jump_start(f):
    p = Pose()
    if f <= 6:                                       # crouch
        k = smooth(f / 6)
        p.body_off.z = IDLE_Z + (-0.1 - IDLE_Z) * k
        p.body_rot.x = 0.12 * k
        p.ears = ear_wobble(0, 0)
        p.ears["L"].x = p.ears["R"].x = -0.2 * k
    else:                                            # explode upward
        k = smooth((f - 6) / 6)
        p.body_off.z = -0.1 + 0.115 * k
        p.body_rot.x = 0.12 * (1 - k)
        p.ears["L"].x = p.ears["R"].x = -0.2 + 0.5 * k
        for side in ("L", "R"):
            p.feet[side] = (Vector((0, 0.03 * k, 0.03 * k)), 0.35 * k)
    p.eye = Vector((1, 1, 1 - 0.3 * math.sin(math.pi * min(f, 6) / 6)))
    return p


@anim("Fall", 24, True)
def fall(f):
    t = 2 * math.pi * f / 24
    p = Pose()
    p.body_off.z = 0.0
    p.body_rot = Euler((-0.06 + 0.02 * math.sin(t), 0.03 * math.sin(t), 0))
    for side, ph in (("L", 0.0), ("R", 1.6)):
        p.feet[side] = (Vector((0, 0.02 * math.sin(t + ph), 0.06 + 0.015 * math.sin(t + ph))), 0.3 + 0.08 * math.sin(t + ph))
    p.ears = {"L": Euler((0.35 + 0.1 * math.sin(2 * t), 0, 0)), "R": Euler((0.35 + 0.1 * math.sin(2 * t + 1), 0, 0))}
    p.eye = Vector((1.05, 1, 1.05))
    return p


@anim("Land", 14, False)
def land(f):
    p = Pose()
    k = f / 14
    impact = math.exp(-5 * k) * math.cos(2.2 * math.pi * k)       # damped squash
    p.body_off.z = IDLE_Z - 0.11 * impact * (1 - smooth(k))
    p.body_rot.x = 0.1 * impact * (1 - smooth(k))
    if f == 0:
        for side in ("L", "R"):
            p.feet[side] = (Vector((0, 0, 0)), 0.0)
    p.ears = {"L": Euler((-0.4 * impact, 0, 0)), "R": Euler((-0.4 * impact, 0, 0))}
    p.eye = Vector((1, 1, 1 - 0.5 * max(0.0, impact)))
    return p


# --- bake every animation to FK keys --------------------------------------------------------
baked = {}
max_ik_err = 0.0
for name, (frames, loop, fn) in ANIMS.items():
    keys = []
    for f in range(frames + 1):
        p = fn(f % frames if loop else min(f, frames))
        apply_pose(p)
        for side in ("L", "R"):
            tgt = pb["ik_foot_" + side].head
            max_ik_err = max(max_ik_err, (pb["shin_" + side].tail - tgt).length)
        keys.append(capture())
    if not loop:
        keys = keys[:frames + 1]
    baked[name] = keys
print(f"[cubebot] max IK reach error {max_ik_err * 100:.2f} cm")

# drop the helper rig: constraints off, helper bones deleted
for b in pb:
    for c in list(b.constraints):
        b.constraints.remove(c)
bpy.ops.object.mode_set(mode="EDIT")
for side in ("L", "R"):
    eb.remove(eb["ik_foot_" + side])
    eb.remove(eb["pole_" + side])
bpy.ops.object.mode_set(mode="OBJECT")
pb = arm.pose.bones

arm.animation_data_create()
for name, keys in baked.items():
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    prev = {}
    for f, frame in enumerate(keys):
        for n, m in frame.items():
            loc, rot, sca = m.decompose()
            if n in prev and prev[n].dot(rot) < 0:
                rot = -rot
            prev[n] = rot
            b = pb[n]
            b.location, b.rotation_quaternion, b.scale = loc, rot, sca
            b.keyframe_insert("location", frame=f, group=n)
            b.keyframe_insert("rotation_quaternion", frame=f, group=n)
            b.keyframe_insert("scale", frame=f, group=n)
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 0, act)
    arm.animation_data.action = None

for b in pb:
    b.matrix_basis = Matrix.Identity(4)
scene.frame_set(0)

bpy.ops.export_scene.gltf(
    filepath=os.path.abspath(GLB_PATH),
    export_format="GLB",
    export_animations=True,
    export_animation_mode="NLA_TRACKS",
    export_def_bones=True,
    export_force_sampling=True,
    export_frame_range=False,
    export_anim_single_armature=True,
    export_yup=True,
    export_apply=False,
)
# mute the tracks in the saved .blend so it opens in rest pose (unmute one / solo it to preview)
for track in arm.animation_data.nla_tracks:
    track.mute = True
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
print("[cubebot] exported", os.path.abspath(GLB_PATH), "animations:", list(baked))
