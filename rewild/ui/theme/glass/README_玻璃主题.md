# 玻璃风 UI 主题（验证版）

- 项目主题已指向 `res://ui/theme/glass/glass_theme.tres`（project.godot 的 GUI → Theme → Custom）。
  想回到像素版：把它改回 `res://ui/theme/greybox_theme.tres` 即可，像素素材原样保留在 `ui/theme/pixel/`。
- 默认纹理过滤需为 Linear（Project Settings → Rendering → Textures → Canvas Textures），否则圆角会有锯齿。
- 字体：正文思源黑体（裁剪版），标题 / 主菜单 / 对话与历史正文用霞鹜文楷；来源与许可见 `ui/fonts/README_字体.md`。
  字号仍经过 `UIType.snap()`（12 的整数倍），对矢量字体无害，只是档位偏粗；以后要细调再把 `UIType.GRID_PX` 改小。
- 对话框的名牌与继续箭头已换成玻璃素材（`CustomUi/layers/dialogue_box_layer.tscn`）。
- 磨砂效果：`glass_blur.gdshader` + `glass_panel_material.tres`，已挂在设置页、暂停菜单、存档页、主菜单存档页和对话框的大面板上（节点的 Material）。**尚未在引擎里实测**；
  只能挂在 PanelContainer / Panel 上，不要挂在 Button / Label 上（文字会被一起处理坏）。
  可调参数在 `glass_panel_material.tres`：`blur_px` 模糊程度、`dim` 压暗背后画面、`saturation` 偏灰程度。
  不想要模糊：删掉对应节点的 Material 即可，贴图本身仍是半透明灰玻璃。
- 暂无图标；亮背景下暗色玻璃偏灰，后续做亮色变体。
