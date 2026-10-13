# CubeBot

Cube-headed robot with one big glowing eye, made entirely by `source/build_cubebot.py`.

- `cubebot.tscn`: drop-in character visual (script `cubebot.gd`, class `CubeBot`)
- `cubebot_preview.tscn`: test bench. 1-6 play animations, Space jumps, C toggles the eye colour, arrow keys orbit.
- `cubebot.glb`: generated asset. Loop modes are set in `cubebot.glb.import`.
- `source/`: build script and editable `.blend` (Godot ignores this folder)

## Animations (30 fps, in place, no root motion)

| name | length | loop | notes |
|---|---|---|---|
| Idle | 2.0 s | yes | breathing, ear wobble, blinks at 1.33 s |
| Walk | 0.6 s | yes | feet stay planted at about 0.72 m/s |
| Run | 0.47 s | yes | about 2.2 m/s, has a flight phase |
| Jump_Start | 0.4 s | no | crouch, then push off |
| Fall | 0.8 s | yes | legs dangle, ears up |
| Land | 0.47 s | no | squash, settles into Idle's first frame |

If the move speed differs, scale playback: `bot.play(&"Walk", 0.15, speed / 0.72)`.

## Eye

```gdscript
bot.eye_mix = 0.0      # blue
bot.glow_to(1.0, 0.5)  # tween to yellow over 0.5 s
bot.eye_emission = 4.0 # brightness of the lens
bot.eye_light_energy = 1.0 # OmniLight + forward SpotLight beam (cast_beam toggles the beam)
```

The lights hang off a `BoneAttachment3D` on the `eye` bone, which the script creates at runtime.

## Skeleton

`root` › `body` › `eye`, `ear_L`, `ear_R`, `thigh_L/R` › `shin_L/R` › `foot_L/R`. Every part is rigidly bound to one bone.
The legs were authored with IK and baked to FK, so add a `SkeletonIK3D`/`TwoBoneIK3D` on thigh→shin if you want terrain foot placement.

## Rebuilding

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b -P rewild/objects/player/cubebot/source/build_cubebot.py
```

Dimensions, colours and the animation curves are plain Python functions at the top and bottom of the script.
The material names `EyeGlow` / `EyeCore` must stay the same, because `cubebot.gd` finds them by name.
