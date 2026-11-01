#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Ray-marched liquid sphere with soft iridescent shading.

namespace orbfx {

float hash3(float3 p) {
    p = fract(p * 0.3183099 + float3(0.1, 0.2, 0.3));
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(float3 x) {
    float3 i = floor(x);
    float3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float a = mix(hash3(i + float3(0.0, 0.0, 0.0)), hash3(i + float3(1.0, 0.0, 0.0)), f.x);
    float b = mix(hash3(i + float3(0.0, 1.0, 0.0)), hash3(i + float3(1.0, 1.0, 0.0)), f.x);
    float c = mix(hash3(i + float3(0.0, 0.0, 1.0)), hash3(i + float3(1.0, 0.0, 1.0)), f.x);
    float d = mix(hash3(i + float3(0.0, 1.0, 1.0)), hash3(i + float3(1.0, 1.0, 1.0)), f.x);
    return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

float3 rotY(float3 p, float a) {
    float c = cos(a);
    float s = sin(a);
    return float3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

float field(float3 p, float t, float amp) {
    float3 q = rotY(p, t * 0.25);
    float n = noise3(q * 1.7 + float3(0.0, t * 0.35, 0.0)) * 2.0 - 1.0;
    float n2 = noise3(q * 3.4 - float3(t * 0.22)) * 2.0 - 1.0;
    return length(p) - (1.0 + (n + 0.45 * n2) * amp);
}

} // namespace orbfx

[[ stitchable ]] half4 orb(float2 position, half4 color, float2 size, float time, float energy,
                           float3 tint, float tintAmt, float2 tilt, float dark) {
    float side = min(size.x, size.y);
    float2 uv = (position - size * 0.5) / (side * 0.5);
    uv.y = -uv.y;

    float3 ro = float3(0.0, 0.0, 3.2);
    float3 rd = normalize(float3(uv * 0.5, -1.0));
    float amp = 0.07 + energy * 0.16;

    float3 c1 = float3(1.0, 0.76, 0.66);
    float3 c2 = float3(0.72, 0.68, 1.0);
    float3 c3 = float3(0.56, 0.90, 0.85);

    // soft halo around the sphere
    float r = length(uv);
    float glowA = exp(-pow(max(r - 0.6, 0.0) * 3.2, 2.0)) * (0.22 + energy * 0.35) * (dark > 0.5 ? 1.4 : 1.0);
    glowA = clamp(glowA, 0.0, 1.0);
    float3 glowC = mix(c1, c2, 0.5 + 0.5 * uv.y);
    glowC = mix(glowC, tint, tintAmt * 0.6);
    half4 glow = half4(half3(glowC * glowA), half(glowA));

    // bounding sphere test
    float bound = 1.0 + amp * 1.5 + 0.02;
    float b = dot(ro, rd);
    float c = dot(ro, ro) - bound * bound;
    float h = b * b - c;
    if (h < 0.0) { return glow; }

    float t = max(-b - sqrt(h), 0.0);
    bool hit = false;
    float3 p = ro;
    for (int i = 0; i < 40; i++) {
        p = ro + rd * t;
        float d = orbfx::field(p, time, amp);
        if (d < 0.0015) { hit = true; break; }
        t += d * 0.75;
        if (t > 6.0) { break; }
    }
    if (!hit) { return glow; }

    const float e = 0.0025;
    float3 k1 = float3(1.0, -1.0, -1.0);
    float3 k2 = float3(-1.0, -1.0, 1.0);
    float3 k3 = float3(-1.0, 1.0, -1.0);
    float3 k4 = float3(1.0, 1.0, 1.0);
    float3 n = normalize(k1 * orbfx::field(p + k1 * e, time, amp) +
                         k2 * orbfx::field(p + k2 * e, time, amp) +
                         k3 * orbfx::field(p + k3 * e, time, amp) +
                         k4 * orbfx::field(p + k4 * e, time, amp));

    float3 v = -rd;
    float3 L = normalize(float3(-0.45 + tilt.x * 0.8, 0.8 + tilt.y * 0.8, 0.65));
    float fres = pow(1.0 - max(dot(n, v), 0.0), 2.3);

    float3 q = orbfx::rotY(p, time * 0.25);
    float nn = orbfx::noise3(q * 1.7 + float3(0.0, time * 0.35, 0.0));
    float3 base = mix(c1, c2, smoothstep(-0.7, 0.8, n.y + (nn - 0.5) * 0.9));
    float sw = 0.5 + 0.5 * sin(nn * 5.0 + time * 0.55 + n.y * 2.2 + n.x * 1.4);
    base = mix(base, c3, sw * 0.5);
    base = mix(base, tint, tintAmt * 0.65);

    float dif = max(dot(n, L), 0.0) * 0.32 + 0.72;
    float spec = pow(max(dot(reflect(-L, n), v), 0.0), 28.0) * 0.6;
    float3 col = base * dif + spec + fres * mix(float3(1.0), c3, 0.35) * 0.5;
    col = clamp(col, 0.0, 1.0);
    return half4(half3(col), 1.0h);
}
