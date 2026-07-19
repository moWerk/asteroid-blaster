#version 440

// Particle-burst explosion (Qt6 RHI dialect).
// Source for explosion.frag.qsb — recompile with:
// qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o explosion.frag.qsb explosion.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    vec3 baseColor;
} ubuf;

float noise(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
    vec2 uv = qt_TexCoord0 - vec2(0.5);
    float dist = length(uv);
    float fade = 1.0 - ubuf.time;
    vec3 color = vec3(0.0);
    float totalAlpha = 0.0;

    for (int i = 0; i < 12; i++) {
        float angle = float(i) * 0.3927 + noise(vec2(float(i), ubuf.time)) * 0.4;
        float speed = 0.8 + noise(vec2(float(i) + 1.0, ubuf.time)) * 0.4;
        float radius = speed * ubuf.time;
        vec2 particlePos = vec2(cos(angle), sin(angle)) * radius;
        float swirl = ubuf.time * 3.0 * (noise(vec2(float(i), 0.0)) - 0.5);
        particlePos += vec2(cos(swirl), sin(swirl)) * 0.1;
        float particleDist = length(uv - particlePos);
        float particleSize = 0.08 * (1.0 - ubuf.time * 0.3);
        if (particleDist < particleSize) {
            float intensity = 1.0 - (particleDist / particleSize);
            color += mix(vec3(1.0, 0.6, 0.2), ubuf.baseColor, ubuf.time) * intensity * intensity * fade;
            totalAlpha += intensity * fade;
        }
    }
    float coreDist = dist * (1.0 + ubuf.time);
    if (coreDist < 0.3) {
        float coreIntensity = 1.0 - (coreDist / 0.3);
        color += mix(vec3(1.0, 0.9, 0.6), ubuf.baseColor, ubuf.time) * coreIntensity * fade * 0.9;
        totalAlpha += coreIntensity * fade;
    }
    color = clamp(color * 2.0, vec3(0.0), vec3(1.0));
    fragColor = vec4(color, totalAlpha * ubuf.qt_Opacity);
}
