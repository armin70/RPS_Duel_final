shader_type canvas_item;
render_mode unshaded;

uniform sampler2D color_video : filter_linear;
uniform sampler2D alpha_video : filter_linear;
uniform float alpha_gamma : hint_range(0.25, 4.0, 0.01) = 1.0;
uniform float alpha_multiplier : hint_range(0.0, 2.0, 0.01) = 1.0;

void fragment() {
    vec4 color_frame = texture(color_video, UV);
    float mask = texture(alpha_video, UV).r;
    mask = pow(clamp(mask, 0.0, 1.0), alpha_gamma);
    mask = clamp(mask * alpha_multiplier, 0.0, 1.0);

    COLOR = vec4(color_frame.rgb, mask);
}
