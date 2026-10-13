# Stylized Fox — Reference Revision

A lean, stylized orange-and-cream quadruped inspired by the supplied reference, with an editable Blender rig and an animated GLB.

## Files
- `fox.blend`: mesh, weighted skeleton, IK foot targets, six Actions, and a studio preview setup.
- `fox.glb`: game asset only, with embedded texture and sampled bone animation. Cameras, lights, and studio ground are excluded.
- `fox_atlas.png`: 1024 × 1024 palette texture. UV islands deliberately share color swatches; this is not a unique paintable UV unwrap.
- `fox_preview.png`: studio render.
- `previews/`: videos of each clip and a combined animated overview.
- `validation.json`, `export_check.json`, `pose_checks.json`: geometry, export, and animation checks.

## Asset specifications
1,052 triangles; 614 Blender vertices before export splitting; one material; 25 deform bones; 34 total rig bones. The atlas provides flat colors rather than painted fur. The torso, neck, skull, and muzzle form a continuous surface. Legs, ears, facial details, and tail use separate surface islands. Smooth normals soften the shading while preserving the low-poly silhouette.

The source uses meters, Z up, and -Y forward. The neutral pose is approximately 1.97 m tall including ears and 2.68 m long including tail and muzzle. Scale the entire character uniformly if your game needs a smaller fox. GLB converts to Y up and +Z forward.

## Animation clips
| Clip | Duration | Playback |
| --- | ---: | --- |
| Idle | 4 s | Loop |
| Walk | 1 s | Loop; in place |
| Play | 5 s | One shot; idle at both ends |
| Sleep | 6 s | Loop |
| LieDown | 2 s | Idle → Sleep |
| WakeUp | 2 s | Sleep → Idle |

Source animation is sampled at 24 fps; preview videos use 12 fps. Walk has a 0.27 m stance travel over 0.62 s. Move the character forward at roughly 0.435 m/s at normal playback speed to match stance-foot speed. Adjust movement and animation speed together. The play clip includes a small local hop and returns to its start position.

## Editing in Blender
Select Fox_Rig, enter Pose Mode, and use the Action Editor to select an animation. The named NLA tracks are stored muted to prevent the clips from blending together.

Move `IK.front.L`, `IK.front.R`, `IK.hind.L`, and `IK.hind.R` to position feet. Foot rotation follows the corresponding IK target. Rotate `tail.00` through `tail.03`, the ears, head, and jaw directly. Eye bones squash the eyes into closed slits for sleep. The `pole.*` helper bones are unconnected placeholders; IK currently uses the rest-pose bend direction.

GLB contains baked deform-bone motion, not Blender's editable IK constraints. Use the Blender source for animation edits. Export only Fox and Fox_Rig, with animations and constraint sampling enabled.

## Importing into a game
1. Import `fox.glb` using your engine's glTF 2.0 import support. Materials and the atlas are embedded.
2. Keep the supplied quadruped skeleton. If the importer asks for a humanoid or generic rig, choose generic.
3. Enable looping for Idle, Walk, and Sleep. Play the transitions and Play once.
4. Use Idle → LieDown → Sleep → WakeUp → Idle for sleeping. Blend locomotion clips over approximately 0.1–0.2 seconds as a starting point.
5. Use in-place movement for Walk and match the speed above. Add your game's collision shape and gameplay controller separately.
6. Check lighting, scale, ground contact, and animation blends in your chosen engine before shipping.

Export was re-imported into Blender to confirm the mesh, skin, material, embedded image, and six animation clips. All source frames were checked for ground penetration, and loop endpoints were compared. No target game engine was selected, so engine-specific integration and runtime performance have not been tested.
