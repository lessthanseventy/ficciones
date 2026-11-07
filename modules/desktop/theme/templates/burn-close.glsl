#version 320 es
// @duration 1.15
// Hyprfuego's burn-on-close (github.com/brontosaurusrex/hyprfuego, shaders/burn-close.glsl at
// 3a114aa), recoloured amber into violet by render.nix (burnCloseGlsl).
// Copyright (c) 2026 Hyprfuego contributors. MIT License: permission is hereby granted, free of
// charge, to any person obtaining a copy of this software, to deal in the Software without
// restriction, provided this notice is included in all copies or substantial portions.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
precision highp float;
in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;
uniform float progress;
uniform float seed;
uniform vec2 surface_size;
uniform vec4 window_rect;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x),
               mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1)), f.x), f.y);
}
float fbm(vec2 p) {
    // Favor broad flow over fine grain, using the same three noise samples.
    return 0.68 * noise(p) + 0.24 * noise(p * 2.03 + 17.1)
         + 0.08 * noise(p * 4.11 - 9.7);
}
vec4 over(vec4 foreground, vec4 background) {
    return foreground + background * (1.0 - foreground.a);
}
// The original bottom-up profile, with a fresh curve for each close.
highp uint profileHash(highp uint value) {
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    return value ^ (value >> 16u);
}
float profileControl(highp uint key, highp uint channel) {
    return float(profileHash(key ^ (channel * 0x9e3779b9u)) >> 8u) / 16777216.0;
}
float burnClock(float p) { return clamp(p, 0.0, 1.0); }
int controlPointCount(highp uint key) {
    float choice = profileControl(key, 20u);
    return choice < 0.20 ? 4 : (choice < 0.80 ? 5 : 6);
}
vec2 burnSchedule(float x, highp uint key) {
    // Keep the same smooth joins and height limits, with 4/5/6 control points.
    int count = controlPointCount(key);
    float a = profileControl(key, 10u), b = profileControl(key, 11u);
    float c = profileControl(key, 12u), d = profileControl(key, 13u);
    float e = profileControl(key, 14u), f = profileControl(key, 15u);
    float low = min(min(a, b), min(c, d));
    float high = max(max(a, b), max(c, d));
    if (count >= 5) { low = min(low, e); high = max(high, e); }
    if (count == 6) { low = min(low, f); high = max(high, f); }
    // Independent, bounded jitter keeps knots ordered without narrow spikes.
    vec4 knots = (vec4(1, 2, 3, 4) + 0.8 * (vec4(profileControl(key, 30u),
        profileControl(key, 31u), profileControl(key, 32u), profileControl(key, 33u)) - 0.5)) / float(count - 1);
    float timing;
    if (x < knots.x) timing = mix(a, b, smoothstep(0.0, knots.x, x));
    else if (x < knots.y) timing = mix(b, c, smoothstep(knots.x, knots.y, x));
    else if (count == 4) timing = mix(c, d, smoothstep(knots.y, 1.0, x));
    else if (x < knots.z) timing = mix(c, d, smoothstep(knots.y, knots.z, x));
    else if (count == 5) timing = mix(d, e, smoothstep(knots.z, 1.0, x));
    else if (x < knots.w) timing = mix(d, e, smoothstep(knots.z, knots.w, x));
    else timing = mix(e, f, smoothstep(knots.w, 1.0, x));
    timing = clamp((timing - low) / max(high - low, 0.0001), 0.0, 1.0);
    return vec2(mix(0.005, 0.14, timing), mix(0.61, 0.98, timing));
}
float advanceFront(vec2 schedule, float p) {
    float local = clamp((burnClock(p) - schedule.x) / (schedule.y - schedule.x), 0.0, 1.0);
    // Keep the randomized outline, with half its original vertical variation.
    float baseline = clamp((burnClock(p) - 0.0725) / 0.7225, 0.0, 1.0);
    return mix(-0.18, 1.18, mix(baseline, local, 0.5));
}
float burnFront(float x, float p, highp uint key) {
    return advanceFront(burnSchedule(x, key), p);
}
void main() {
    vec4 src = texture(tex, v_texcoord);
    float p = clamp(progress, 0.0, 1.0);
    if (p <= 0.0) { fragColor = src; return; }
    if (p >= 1.0 || src.a <= 0.0) { fragColor = vec4(0); return; }

    vec2 uv = (v_texcoord - window_rect.xy) / max(window_rect.zw, vec2(0.00001));
    vec2 pixels = max(surface_size * window_rect.zw, vec2(1));
    // Use window-height units so flames and sparks keep their proportions.
    vec2 pos = vec2(uv.x * pixels.x / pixels.y, 1.0 - uv.y);
    float variant = seed * 23.71;
    highp uint profileKey = uint(seed * 16777216.0);
    float t = p * 3.8;
    // Reuse this column's existing schedule: shorter burn time means taller fire.
    vec2 localSchedule = burnSchedule(uv.x, profileKey);
    float front = advanceFront(localSchedule, p);
    float fastBurn = clamp((0.84 - (localSchedule.y - localSchedule.x)) / 0.235, 0.0, 1.0);
    float flameScale = mix(0.65, 2.15, fastBurn * fastBurn);
    // A stationary irregular contour burns monotonically; the gas moves freely.
    float edge = pos.y - front;
    // Contour displacement is at most 0.0275 height units. Below -0.68,
    // paper, fire and smoke are all zero even with that displacement.
    // Sparks still run below; only invisible contour noise is skipped.
    if (edge > -0.68) {
        float contour = fbm(vec2(pos.x * 14.0 + variant, pos.y * 9.0));
        edge += (contour - 0.5) * 0.055;
    }
    float remain = smoothstep(-0.004, 0.007, edge);
    float alive = smoothstep(0.0, 0.065, p) * (1.0 - smoothstep(0.84, 1.0, p));

    // Dark brown/black char, without the continuous yellow outline.
    float charred = exp(-max(edge, 0.0) * 65.0) * alive;
    vec4 paper = src * remain;
    paper.rgb = mix(paper.rgb, vec3(0.018, 0.009, 0.004) * paper.a, charred * 0.94);

    // Broad, coherent tongues rise quickly; thin tips fade into the air.
    float flameAlpha = 0.0;
    vec3 fireColor = vec3(0);
    // Outside the visible envelope only a tiny core tail remains: below
    // 2e-7 at -0.12 height units, and below 1e-14 at +0.25. Skip
    // two turbulence fields there; reuse the remaining fade for heat colour.
    if (edge > -0.12) {
        // Height needs four noise samples; burned pixels need none.
        float plume = pow(noise(vec2(uv.x * 4.0, variant + 41.5)), 3.0);
        float height = 0.045 + 0.09 * fbm(vec2(pos.x * 9.0 + variant, -t * 1.4))
                     + 0.30 * plume;
        // Quiet patches stay low; fast patches produce taller, localized tongues.
        height *= flameScale;
        float h = max(edge, 0.0) / height;
        if (h < 1.45 || edge < 0.25) {
            float warp = fbm(vec2(pos.x * 6.5 + variant, pos.y * 3.5 - t * 2.0));
            vec2 gas = vec2(pos.x * 20.0 + variant + (warp - 0.5) * 1.3,
                            pos.y * 5.5 - t * 4.2);
            float detail = fbm(gas);
            float body = smoothstep(0.20 + h * 0.48, 0.65 + h * 0.32, detail);
            float falloff = exp(-h * 1.9);
            flameAlpha = body * falloff
                * smoothstep(-0.025, 0.012, edge) * (1.0 - smoothstep(0.45, 1.45, h)) * alive;
            float core = exp(-abs(edge) * 130.0) * smoothstep(0.28, 0.72, detail) * alive;
            flameAlpha = clamp(flameAlpha * 0.80 + core * 0.70, 0.0, 0.92) * src.a;
            float heat = clamp(body * 0.45 + falloff * falloff * 0.55, 0.0, 1.0);
            // violet tips, amber where it burns, a pale amber core
            fireColor = mix(@assistant@, @body@, smoothstep(0.35, 0.85, heat));
            float hot = heat * heat;
            fireColor = mix(fireColor, mix(vec3(1.0), @body@, 0.35), hot * hot * hot * 0.85);
        }
    }

    // Smoke originates below its current position and drifts upward. A soft
    // emission envelope and broken density avoid a gray strip glued to the edge.
    float smokeAlpha = 0.0;
    vec3 smokeColor = vec3(0.40, 0.38, 0.35);
    if (edge > -0.65 && edge < 0.65) {
        float curl = noise(vec2(pos.x * 5.0 + variant, pos.y * 3.0 - t * 0.8));
        vec2 emissionUV = uv + vec2((curl - 0.5) * 0.065 / (pixels.x / pixels.y), 0.13);
        float smokeEdge = 1.0 - emissionUV.y - burnFront(emissionUV.x, max(p - 0.12, 0.0), profileKey);
        float density = fbm(vec2(pos.x * 16.0 + (curl - 0.5) * 1.8 + variant,
                                   pos.y * 5.8 - t * 1.7));
        float envelope = exp(-abs(smokeEdge) * 8.0);
        float trail = smoothstep(-0.65, -0.30, edge)
                    * (1.0 - smoothstep(0.35, 0.65, edge));
        smokeAlpha = smoothstep(0.27, 0.73, density) * trail * envelope * alive * 0.30 * src.a;
        smokeColor = mix(vec3(0.32, 0.30, 0.28), vec3(0.58, 0.57, 0.54), curl);
    }

    // Sparse sparks are born on the current burn front. Check lifetime
    // before evaluating their front/trajectory; inactive sparks cost no geometry.
    vec4 sparks = vec4(0);
    float aspect = pixels.x / pixels.y;
    for (int i = 0; i < 48; ++i) {
        float id = float(i);
        float a = hash21(vec2(id + variant, 4.13));
        float birth = 0.06 + a * 0.74;
        float age = p - birth;
        if (age <= 0.0 || age >= 0.34) continue;
        float b = hash21(vec2(id + variant, 8.91));
        float c = hash21(vec2(id + variant, 15.77));
        float life = 0.11 + c * 0.23;
        if (age >= life) continue;
        float age01 = age / life;
        float drift = (c - 0.5) * 0.4;
        float x = b * aspect + (age * drift + sin(age * 12.0 + a * 17.0) * age * 0.08);
        float rise = 0.85 + a * 1.25;
        // Reject horizontally before evaluating the expensive burn profile.
        // The shear can shift x by at most ten vertical radii times its slope.
        vec2 r = max(vec2(1.0, 1.8) / pixels.y,
                     vec2(0.0018 + c * 0.003, 0.003 + a * 0.007));
        float shear = drift / rise;
        if (abs(pos.x - x) > 10.0 * (r.x + r.y * abs(shear))) continue;
        float originY = burnFront(b, birth, profileKey);
        float y = originY + (age * rise - age * age * 0.7);
        vec2 d = pos - vec2(x, y);
        d.x -= d.y * shear;
        // The halo beyond ten radii is below 1e-10 alpha. Most pixels miss a
        // tiny ember entirely; reject them before divides, exponentials/color.
        if (any(greaterThan(abs(d), r * 10.0))) continue;
        float distance2 = dot(d / r, d / r);
        float hotCore = exp(-distance2 * 1.9);
        float brightness = ((0.55 + c * 1.25) * hotCore + 0.10 * exp(-distance2 * 0.35))
            * smoothstep(0.0, 0.025, age) * (1.0 - smoothstep(0.35, 1.0, age01)) * alive;
        float alpha = clamp(brightness, 0.0, 0.96) * src.a;
        // embers leave amber and cool to violet
        vec3 color = mix(@body@, @assistant@, smoothstep(0.1, 0.6, age01));
        color = mix(color, mix(vec3(1.0), @body@, 0.35), hotCore * (1.0 - age01) * 0.55);
        sparks = over(vec4(color * alpha, alpha), sparks);
    }
    vec4 smoke = vec4(smokeColor * smokeAlpha, smokeAlpha);
    vec4 fire = vec4(fireColor * flameAlpha, flameAlpha);
    fragColor = over(sparks, over(fire, over(smoke, paper)));
}
