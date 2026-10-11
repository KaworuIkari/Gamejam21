# 玻璃主题与共享资源

项目全局主题为 `ui/theme/glass/glass_theme.tres`，供未显式指定主题的控件继承。其默认字体为 Sarasa UI Regular，按钮和部分标题等使用 SemiBold，详见 `ui/fonts/README_字体.md`。

当前主菜单、设置、存档及确认弹窗主要使用独立的 `ui/theme/light/light_theme.tres`。自定义对话图层也使用明亮主题，但仍直接引用本目录中的继续箭头、名牌和 `glass_panel_material.tres` 等素材。`GlassFx` 对相关玻璃纹理控件补充背景效果。

本目录的模糊着色器和材质与明亮主题的 `light_backdrop.gdshader` 分别维护。修改玻璃效果应检查材质的实际挂载节点，不要假定它负责所有菜单；修改菜单整体外观应优先检查明亮主题。

旧主题路径为 `ui/theme/greybox/greybox_theme.tres`。切换项目全局主题不会自动替换各场景显式指定的明亮主题。照片、头像、圆角纹理等过滤方式按节点和素材需求调整，不统一要求所有 UI 使用最近邻或 Linear。

保留本目录被引用的资源；新增外观优先复用明确的主题职责，避免把全部页面再次绑定到同一个材质。
