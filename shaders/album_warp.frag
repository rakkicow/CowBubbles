#include <flutter/runtime_effect.glsl>

// ambient album artwork, one pass
// blur is pre-paid: the cover arrives as a tiny box-filtered copy

// uniform order = setFloat indices in music_background.dart
uniform sampler2D uTexture;
uniform vec2 uSize;        // canvas px
uniform float uTime;       // seconds
uniform float uTwist;      // centre twist, radians
uniform float uSaturation;
uniform float uScrim;      // fade toward the ground
uniform vec3 uGround;      // ground colour, 0..1
uniform vec2 uTexSize;     // cover copy, texels

out vec4 frag_color;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// smoothstepped bilinear; plain gives a diamond lattice
vec3 smoothTex(vec2 uv) {
    vec2 p = uv * uTexSize - 0.5;
    vec2 i = floor(p);
    vec2 f = p - i;
    f = f * f * (3.0 - 2.0 * f);
    vec2 inv = 1.0 / uTexSize;
    vec2 c = (i + 0.5) * inv;
    vec3 a = texture(uTexture, c).rgb;
    vec3 b = texture(uTexture, c + vec2(inv.x, 0.0)).rgb;
    vec3 d = texture(uTexture, c + vec2(0.0, inv.y)).rgb;
    vec3 e = texture(uTexture, c + inv).rgb;
    return mix(mix(a, b, f.x), mix(d, e, f.x), f.y);
}

// one cover copy; alpha is soft coverage
vec4 sprite(vec2 p, vec2 c, float s, float a) {
    vec2 d = p - c;
    float ca = cos(a), sa = sin(a);
    vec2 l = vec2(ca * d.x + sa * d.y, -sa * d.x + ca * d.y) / s;
    vec2 uv = l + 0.5;
    vec2 edge = smoothstep(0.0, 0.22, uv) * smoothstep(0.0, 0.22, 1.0 - uv);
    return vec4(smoothTex(clamp(uv, 0.0, 1.0)), edge.x * edge.y);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    // screen-height units, origin centre
    float aspect = uSize.x / uSize.y;
    vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);

    // twist, stronger toward the centre
    float radius = 0.95;
    float dist = length(p);
    if (dist < radius) {
        float ratio = (radius - dist) / radius;
        float ang = ratio * ratio * uTwist * (0.8 + 0.2 * sin(uTime * 0.09));
        float s = sin(ang), c = cos(ang);
        p = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
    }

    float t = uTime;
    // three copies; s0 always covers the screen
    vec4 s0 = sprite(p, vec2(0.10 * sin(t * 0.050), 0.08 * cos(t * 0.041)),
                     1.9, t * 0.070);
    vec4 s1 = sprite(p, vec2(-0.25 + 0.12 * cos(t * 0.037), 0.18 * sin(t * 0.045)),
                     1.5, -t * 0.095 + 2.1);
    vec4 s2 = sprite(p, vec2(0.28 + 0.10 * sin(t * 0.043), -0.15 + 0.10 * cos(t * 0.031)),
                     1.3, t * 0.120 + 4.0);

    // stack in order
    vec3 col = s0.rgb;
    col = mix(col, s1.rgb, s1.a * 0.85);
    col = mix(col, s2.rgb, s2.a * 0.75);

    // saturation; blurring averages toward grey
    float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(vec3(lum), col, uSaturation);

    // toward ground, for legibility
    col = mix(col, uGround, uScrim);

    // dither, 8-bit gradients band
    col += (hash(FlutterFragCoord().xy) - 0.5) * 0.008;

    frag_color = vec4(col, 1.0);
}
