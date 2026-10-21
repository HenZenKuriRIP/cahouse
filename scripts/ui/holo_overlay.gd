extends ColorRect
## Fullscreen subtle CRT/holo layer: 1-logical-pixel scanlines + gentle vignette; flicker disabled by REDUCE FLASH.
const SHADER := """
shader_type canvas_item;
uniform float strength = 0.06;
uniform float flicker = 0.0;
uniform float lines = 480.0;
uniform float time_s = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	float scan = step(0.5, fract(uv.y * lines));
	float vig = smoothstep(0.35, 0.95, length(uv - 0.5) * 1.25);
	float fl = flicker * (0.5 + 0.5 * sin(time_s * 50.0)) * 0.03;
	COLOR = vec4(0.031, 0.047, 0.094, clamp(scan * strength + vig * 0.35 + fl, 0.0, 0.6));
}
"""
var mat: ShaderMaterial
var _t := 0.0
var flicker_amount := 0.3

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	material = mat
	color = Color.WHITE

func _process(delta: float) -> void:
	_t += delta
	mat.set_shader_parameter("time_s", _t)
	mat.set_shader_parameter("flicker", 0.0 if bool(SaveManager.settings.get("reduce_flash", false)) else flicker_amount)
