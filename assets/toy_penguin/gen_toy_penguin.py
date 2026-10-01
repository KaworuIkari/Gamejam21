"""Generate the wind-up toy penguin model (toy_penguin.glb) with Blender.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender -b --python gen_toy_penguin.py
    ... --python gen_toy_penguin.py -- --preview <dir>   # also render preview PNGs

Every part is defined as a signed distance field and meshed by casting rays
from a point inside it, which gives clean quad grids and smooth blends.
Blender axes: Z up, the penguin faces -Y (+Z after glTF export), its left is +X.
The model is 1 unit tall with the origin under the feet.
"""

import math
import os
import sys
import tempfile

import bpy
import numpy as np

OUT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_GLB = os.path.join(OUT_DIR, "toy_penguin.glb")

# sRGB 0-255 colours
BLUE = (30, 64, 168)
WHITE = (242, 240, 235)
ORANGE = (246, 138, 28)
BLACK = (8, 8, 10)
STEEL = (200, 202, 208)

TEX_W, TEX_H = 2048, 1024

BODY_C = np.array([0.0, 0.0, 0.40])
HEAD_C = np.array([0.0, 0.0, 0.835])
HEAD_R = np.array([0.165, 0.16, 0.16])
BODY_PIVOT = np.array([0.0, 0.0, 0.12])


# --------------------------------------------------------------------------
# SDF helpers
# --------------------------------------------------------------------------

def norm(v):
    return np.linalg.norm(v, axis=-1)


def normalize(v):
    v = np.asarray(v, dtype=float)
    return v / np.maximum(norm(v)[..., None], 1e-12)


def sd_ellipsoid(p, c, r):
    r = np.asarray(r, dtype=float)
    q = p - np.asarray(c, dtype=float)
    k0 = norm(q / r)
    k1 = norm(q / (r * r))
    return np.where(k1 < 1e-9, -r.min(), k0 * (k0 - 1.0) / np.maximum(k1, 1e-9))


def sd_capsule(p, a, b, radius):
    a = np.asarray(a, dtype=float)
    b = np.asarray(b, dtype=float)
    pa = p - a
    ba = b - a
    h = np.clip((pa @ ba) / (ba @ ba), 0.0, 1.0)
    return norm(pa - ba * h[..., None]) - radius


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def cast(sdf, origin, dirs, tmax, iters=36):
    """Surface point along each ray; the origin must be inside the shape."""
    lo = np.zeros(dirs.shape[:-1])
    hi = np.full(dirs.shape[:-1], float(tmax))
    for _ in range(iters):
        mid = 0.5 * (lo + hi)
        inside = sdf(origin + dirs * mid[..., None]) < 0.0
        lo = np.where(inside, mid, lo)
        hi = np.where(inside, hi, mid)
    return origin + dirs * (0.5 * (lo + hi))[..., None]


def frame_from_z(z_axis, hint):
    """Right-handed frame (columns x, y, z) whose y leans towards hint."""
    z = normalize(z_axis)
    x = normalize(np.cross(hint, z))
    y = np.cross(z, x)
    return np.stack([x, y, z], axis=1)


def sphere_param(sdf, center, radii, tmax):
    """Position function sampling a shape like a sphere scaled by radii."""
    center = np.asarray(center, dtype=float)
    radii = np.asarray(radii, dtype=float)

    def pos(u, v):
        th = 2.0 * math.pi * np.asarray(u, dtype=float)
        phi = (np.asarray(v, dtype=float) - 0.5) * math.pi
        d = np.stack([np.cos(phi) * np.cos(th), np.cos(phi) * np.sin(th), np.sin(phi)], -1)
        return cast(sdf, center, normalize(d * radii), tmax)

    return pos


def grid_mesh(pos, nu, nv):
    """Closed quad grid with a pole at each end: (verts, faces, per-face uvs)."""
    uu, vv = np.meshgrid(np.arange(nu) / nu, np.arange(1, nv) / nv)
    rings = pos(uu, vv).reshape(-1, 3)
    bottom = pos(np.array([0.0]), np.array([0.0]))
    top = pos(np.array([0.0]), np.array([1.0]))
    verts = np.concatenate([bottom, rings, top])
    top_i = len(verts) - 1

    def idx(i, j):
        return 1 + (j - 1) * nu + (i % nu)

    faces, uvs = [], []
    for i in range(nu):
        u0, u1, um = i / nu, (i + 1) / nu, (i + 0.5) / nu
        faces.append((0, idx(i + 1, 1), idx(i, 1)))
        uvs.append(((um, 0.0), (u1, 1 / nv), (u0, 1 / nv)))
        for j in range(1, nv - 1):
            v0, v1 = j / nv, (j + 1) / nv
            faces.append((idx(i, j), idx(i + 1, j), idx(i + 1, j + 1), idx(i, j + 1)))
            uvs.append(((u0, v0), (u1, v0), (u1, v1), (u0, v1)))
        faces.append((idx(i, nv - 1), idx(i + 1, nv - 1), top_i))
        uvs.append(((u0, 1 - 1 / nv), (u1, 1 - 1 / nv), (um, 1.0)))
    return verts, faces, uvs


def merge(parts):
    verts, faces, uvs, offset = [], [], [], 0
    for v, f, uv in parts:
        verts.append(v)
        faces += [tuple(i + offset for i in face) for face in f]
        uvs += uv
        offset += len(v)
    return np.concatenate(verts), faces, uvs


# --------------------------------------------------------------------------
# Body (egg torso blended into a round head)
# --------------------------------------------------------------------------

def sdf_body(p):
    q = p - BODY_C
    rz = np.where(q[..., 2] > 0.0, 0.34, 0.29)
    r = np.stack([np.full_like(rz, 0.255), np.full_like(rz, 0.245), rz], -1)
    k0 = norm(q / r)
    k1 = norm(q / (r * r))
    torso = np.where(k1 < 1e-9, -0.245, k0 * (k0 - 1.0) / np.maximum(k1, 1e-9))
    return smin(torso, sd_ellipsoid(p, HEAD_C, HEAD_R), 0.09)


def body_pos(u, v, iters=36):
    """The ray origin slides up the spine so both poles are sampled evenly."""
    u = np.asarray(u, dtype=float)
    v = np.asarray(v, dtype=float)
    th = 2.0 * math.pi * u  # u = 0 is the back, 0.5 the front
    phi = (v - 0.5) * math.pi
    s = v * v * (3.0 - 2.0 * v)
    origin = np.stack([np.zeros_like(s), np.zeros_like(s),
                       BODY_C[2] + (HEAD_C[2] - BODY_C[2]) * s], -1)
    d = np.stack([-np.sin(th) * np.cos(phi), np.cos(th) * np.cos(phi), np.sin(phi)], -1)
    return cast(sdf_body, origin, d, 0.6, iters)


def head_dir(az_deg, el_deg):
    az, el = math.radians(az_deg), math.radians(el_deg)
    return np.array([math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)])


def head_point(az_deg, el_deg):
    return cast(sdf_body, HEAD_C, head_dir(az_deg, el_deg)[None, :], 0.5)[0]


EYE_AZ, EYE_EL, EYE_R = 42.0, 24.0, 0.024


def white_paint(p):
    """Signed distance-like field, negative where the body is painted white."""
    x, y, z = p[..., 0], p[..., 1], p[..., 2]
    alpha = np.arctan2(np.abs(x), -y)
    rho = np.hypot(x, y)
    half_width = np.radians(np.clip(72.0 - 14.0 * ((z - 0.40) / 0.30) ** 2, 40.0, 72.0))
    d = smax((alpha - half_width) * rho, z - 0.80, 0.03)
    for side in (-1.0, 1.0):
        lobe = head_point(side * 35.0, 29.0)
        d = smin(d, norm(p - lobe) - 0.098, 0.02)
    chin = head_point(0.0, -25.0)
    return smin(d, norm(p - chin) - 0.11, 0.02)


def make_body_texture(path):
    u = (np.arange(TEX_W) + 0.5) / TEX_W
    v = (np.arange(TEX_H) + 0.5) / TEX_H
    uu, vv = np.meshgrid(u, v)
    d = white_paint(body_pos(uu, vv, iters=26))
    gy, gx = np.gradient(d)
    mask = np.clip(0.5 - d / (1.5 * np.hypot(gx, gy) + 1e-9), 0.0, 1.0)[..., None]
    rgb = (np.array(BLUE) * (1.0 - mask) + np.array(WHITE) * mask) / 255.0
    rgba = np.concatenate([rgb, np.ones((TEX_H, TEX_W, 1))], -1).astype(np.float32)
    img = bpy.data.images.new("toy_penguin_body", TEX_W, TEX_H, alpha=False)
    img.pixels.foreach_set(rgba.ravel())
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    return img


# --------------------------------------------------------------------------
# Feet: one moulded base with three webbed toes per side
# --------------------------------------------------------------------------

FEET_C = np.array([0.0, -0.03, 0.035])


def sdf_feet(p):
    d = sd_ellipsoid(p, (0.0, 0.02, 0.03), (0.19, 0.12, 0.05))
    for side in (-1.0, 1.0):
        for ang, length in ((13.0, 0.17), (40.0, 0.185), (67.0, 0.17)):
            a = math.radians(ang)
            along = np.array([side * math.sin(a), -math.cos(a), 0.0])
            across = np.array([math.cos(a), side * math.sin(a), 0.0])
            q = p - (np.array([0.0, -0.03, 0.03]) + along * 0.12)
            local = np.stack([q @ along, q @ across, q[..., 2]], -1)
            d = smin(d, sd_ellipsoid(local, (0, 0, 0), (length, 0.07, 0.05)), 0.05)
    d = smin(d, sd_ellipsoid(p, (0.0, 0.0, 0.09), (0.085, 0.085, 0.10)), 0.03)
    return smax(d, -p[..., 2], 0.012)


# --------------------------------------------------------------------------
# Beak (open), local frame: x right, y up, z forward
# --------------------------------------------------------------------------

def sdf_beak(q):
    hinge = 0.045

    def tilted(angle_deg):
        a = math.radians(angle_deg)
        z0 = q[..., 2] - hinge
        y = q[..., 1] * math.cos(a) - z0 * math.sin(a)
        z = z0 * math.cos(a) + q[..., 1] * math.sin(a)
        return np.stack([q[..., 0], y, z], -1)

    up = tilted(18.0)
    upper = smax(sd_ellipsoid(up, (0, 0, 0.0), (0.07, 0.05, 0.125)), -up[..., 1], 0.01)
    lo = tilted(-24.0)
    lower = smax(sd_ellipsoid(lo, (0, 0, -0.005), (0.057, 0.036, 0.095)), lo[..., 1], 0.008)
    core = norm(q - np.array([0.0, 0.0, 0.005])) - 0.045
    return smin(smin(upper, lower, 0.008), core, 0.012)


# --------------------------------------------------------------------------
# Flipper, local frame: x across, y thickness, z along (0 at the shoulder)
# --------------------------------------------------------------------------

FLIPPER_LEN, FLIPPER_W, FLIPPER_T = 0.44, 0.072, 0.018


def sdf_flipper(q):
    u = np.clip(q[..., 2] / FLIPPER_LEN, 1e-4, 1.0 - 1e-4)
    round_ends = 2.0 * np.sqrt(u * (1.0 - u))
    half_w = FLIPPER_W * round_ends * (1.25 - 0.5 * u)
    half_t = FLIPPER_T * round_ends ** 0.6
    f = (np.abs(q[..., 0]) / half_w) ** 2.5 + (np.abs(q[..., 1]) / half_t) ** 2.5 - 1.0
    outside = (q[..., 2] <= 0.0) | (q[..., 2] >= FLIPPER_LEN)
    return np.where(outside, 1.0, f)


def flipper_part(side):
    along = normalize(np.array([side * math.sin(math.radians(52.0)), 0.10,
                                -math.cos(math.radians(52.0))]))
    rot = frame_from_z(along, np.array([0.0, 1.0, 0.0]))
    shoulder = cast(sdf_body, np.array([0.0, 0.0, 0.66]), np.array([[side, 0.0, 0.0]]), 0.5)[0]
    pivot = shoulder - along * 0.05
    pos = sphere_param(sdf_flipper, (0, 0, FLIPPER_LEN * 0.45),
                       (FLIPPER_W, FLIPPER_T, FLIPPER_LEN * 0.5), 0.5)
    verts, faces, uvs = grid_mesh(pos, 40, 28)
    verts[:, 1] += 0.06 * FLIPPER_LEN * (verts[:, 2] / FLIPPER_LEN) ** 2  # tip curls back
    return pivot, (verts @ rot.T, faces, uvs)


# --------------------------------------------------------------------------
# Wind-up key on the penguin's right side
# --------------------------------------------------------------------------

def key_parts():
    anchor = cast(sdf_body, np.array([0.0, 0.0, 0.30]), np.array([[-1.0, 0.0, 0.0]]), 0.5)[0]
    rot = frame_from_z(np.array([-1.0, 0.0, 0.0]), np.array([0.0, 0.0, 1.0]))
    shaft_sdf = lambda q: sd_capsule(q, (0, 0, -0.02), (0, 0, 0.065), 0.011)
    shaft = grid_mesh(sphere_param(shaft_sdf, (0, 0, 0.02), (0.011, 0.011, 0.045), 0.2), 16, 12)
    shaft = (shaft[0] @ rot.T, shaft[1], shaft[2])

    def handle_sdf(q):
        d = sd_ellipsoid(q, (0, 0, 0.026), (0.032, 0.0075, 0.032))
        return smin(d, sd_ellipsoid(q, (0, 0, -0.026), (0.032, 0.0075, 0.032)), 0.006)

    handle = grid_mesh(sphere_param(handle_sdf, (0, 0, 0), (0.032, 0.0075, 0.058), 0.2), 28, 24)
    handle = (handle[0] + np.array([-0.09, 0.0, 0.0]), handle[1], handle[2])
    return anchor, merge([shaft, handle])


# --------------------------------------------------------------------------
# Blender scene
# --------------------------------------------------------------------------

def srgb_to_linear(rgb255):
    c = np.array(rgb255) / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return (*lin, 1.0)


def make_material(name, rgb255, roughness, metallic=0.0, image=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = srgb_to_linear(rgb255)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    if image is not None:
        tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image = image
        mat.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    return mat


ORIGINS = {}


def make_object(name, part, material, origin, parent=None):
    """part holds world-aligned vertices relative to origin (a world position)."""
    verts, faces, uvs = part
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts.tolist(), [], faces)
    layer = mesh.uv_layers.new(name="UVMap")
    layer.data.foreach_set("uv", [c for face in uvs for uv in face for c in uv])
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
    mesh.materials.append(material)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    ORIGINS[name] = np.asarray(origin, dtype=float)
    if parent is not None:
        obj.parent = parent
        obj.location = ORIGINS[name] - ORIGINS[parent.name]
    else:
        obj.location = ORIGINS[name]
    return obj


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tex_path = os.path.join(tempfile.mkdtemp(), "toy_penguin_body.png")
    mat_body = make_material("PenguinBody", WHITE, 0.28, image=make_body_texture(tex_path))
    mat_blue = make_material("PenguinBlue", BLUE, 0.28)
    mat_orange = make_material("PenguinOrange", ORANGE, 0.25)
    mat_eye = make_material("PenguinEye", BLACK, 0.08)
    mat_metal = make_material("PenguinMetal", STEEL, 0.3, metallic=1.0)

    verts, faces, uvs = grid_mesh(body_pos, 96, 72)
    body = make_object("Body", (verts - BODY_PIVOT, faces, uvs), mat_body, BODY_PIVOT)

    beak_origin = head_point(0.0, 8.0) + np.array([0.0, 0.05, 0.0])
    beak_rot = frame_from_z(np.array([0.0, -1.0, 0.0]), np.array([0.0, 0.0, 1.0]))
    verts, faces, uvs = grid_mesh(sphere_param(sdf_beak, (0, 0, 0), (0.07, 0.07, 0.13), 0.3), 56, 40)
    make_object("Beak", (verts @ beak_rot.T, faces, uvs), mat_orange, beak_origin, body)

    eye_sdf = lambda q: norm(q) - EYE_R
    for name, side in (("EyeR", -1.0), ("EyeL", 1.0)):
        center = head_point(side * EYE_AZ, EYE_EL) - head_dir(side * EYE_AZ, EYE_EL) * EYE_R * 0.3
        part = grid_mesh(sphere_param(eye_sdf, (0, 0, 0), (1, 1, 1), 0.1), 20, 12)
        make_object(name, part, mat_eye, center, body)

    for name, side in (("FlipperR", -1.0), ("FlipperL", 1.0)):
        pivot, part = flipper_part(side)
        make_object(name, part, mat_blue, pivot, body)

    anchor, part = key_parts()
    make_object("WindupKey", part, mat_metal, anchor, body)

    feet = grid_mesh(sphere_param(sdf_feet, FEET_C, (0.3, 0.3, 0.06), 0.6), 96, 40)
    make_object("Feet", feet, mat_orange, (0.0, 0.0, 0.0))

    tris = sum(len(p.vertices) - 2 for o in bpy.data.objects for p in o.data.polygons)
    print(f"toy_penguin: {len(bpy.data.objects)} objects, {tris} triangles")


def export():
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format='GLB', export_yup=True,
                              export_animations=False, export_cameras=False, export_lights=False)
    print(f"toy_penguin: wrote {OUT_GLB} ({os.path.getsize(OUT_GLB) / 1024:.0f} KiB)")


def render_previews(out_dir):
    from mathutils import Vector
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = scene.render.resolution_y = 720
    scene.view_settings.view_transform = 'Standard'

    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.78, 0.82, 1.0)
    scene.world = world

    bpy.ops.mesh.primitive_plane_add(size=20.0)
    bpy.context.object.data.materials.append(make_material("Ground", (120, 122, 125), 0.5))
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.0
    sun.data.angle = math.radians(15.0)
    sun.rotation_euler = (math.radians(50.0), 0.0, math.radians(-35.0))
    scene.collection.objects.link(sun)

    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    cam.data.lens = 70.0
    scene.collection.objects.link(cam)
    scene.camera = cam
    target = Vector((0.0, 0.0, 0.5))
    for name, az, el in (("photo", -20.0, 14.0), ("front", 0.0, 5.0), ("side", 90.0, 5.0),
                         ("back", 160.0, 20.0), ("top", 25.0, 55.0)):
        a, e = math.radians(az), math.radians(el)
        offset = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
        cam.location = target + offset * 3.4
        cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.filepath = os.path.join(out_dir, f"preview_{name}.png")
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build()
    export()
    if "--preview" in args:
        render_previews(args[args.index("--preview") + 1])
