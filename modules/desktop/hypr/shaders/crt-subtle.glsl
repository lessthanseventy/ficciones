#version 320 es
// CRT, subtle: faint scanlines and vignette only — enough to read as a tube, not enough to
// fight text.
precision highp float;
in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;

void main() {
    vec2 uv = v_texcoord;
    vec3 col = texture(tex, uv).rgb;
    float line = sin(uv.y * 1200.0 * 3.14159) * 0.5 + 0.5;
    col *= 0.93 + 0.07 * line;
    vec2 v = uv * (1.0 - uv.yx);
    col *= pow(v.x * v.y * 18.0, 0.10);
    fragColor = vec4(col, 1.0);
}
