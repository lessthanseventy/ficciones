#version 320 es
// CRT, full: scanlines, barrel distortion, phosphor bloom, vignette, chromatic fringing.
// Applies to the whole composited output (design §6). Fullscreen apps escape it via
// direct scanout, which is the point.
precision highp float;
in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;

vec2 barrel(vec2 uv) {
    vec2 c = uv * 2.0 - 1.0;
    float r2 = dot(c, c);
    c *= 1.0 + 0.045 * r2;
    return c * 0.5 + 0.5;
}

void main() {
    vec2 uv = barrel(v_texcoord);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) { fragColor = vec4(0.0, 0.0, 0.0, 1.0); return; }

    // chromatic fringing: pull red and blue apart by a hair, more toward the edges
    vec2 d = (uv - 0.5) * 0.0025;
    float r = texture(tex, uv + d).r;
    float g = texture(tex, uv).g;
    float b = texture(tex, uv - d).b;
    vec3 col = vec3(r, g, b);

    // phosphor bloom: a soft halo from the neighbours
    vec3 halo = texture(tex, uv + vec2(0.0015, 0.0)).rgb + texture(tex, uv - vec2(0.0015, 0.0)).rgb
              + texture(tex, uv + vec2(0.0, 0.0015)).rgb + texture(tex, uv - vec2(0.0, 0.0015)).rgb;
    col += halo * 0.06;

    // scanlines on the physical line grid
    float line = sin(uv.y * 1200.0 * 3.14159) * 0.5 + 0.5;
    col *= 0.82 + 0.18 * line;

    // vignette
    vec2 v = uv * (1.0 - uv.yx);
    col *= pow(v.x * v.y * 18.0, 0.22);

    fragColor = vec4(col, 1.0);
}
