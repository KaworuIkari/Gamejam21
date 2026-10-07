shader_type canvas_item;
// （已停用）旧的“面板内置模糊”着色器：保留文件只为让场景里原有的 material 引用不报错，渲染效果等同没有材质。
// 现在面板和按钮的模糊统一由 glass_fx.gd 在背后加“模糊底”实现（见 glass_backdrop.gdshader）。
void fragment() {
}
