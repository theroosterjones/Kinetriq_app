#include <metal_stdlib>
using namespace metal;

// MARK: - Full-screen camera quad

struct CameraVertex {
    float4 position [[position]];
    float2 texCoord;
};

// Two triangles covering clip space (-1…1)
constant float2 kPositions[6] = {
    {-1, -1}, { 1, -1}, {-1,  1},
    {-1,  1}, { 1, -1}, { 1,  1}
};
// Texture coords: (0,0) = top-left, (1,1) = bottom-right
constant float2 kTexCoords[6] = {
    {0, 1}, {1, 1}, {0, 0},
    {0, 0}, {1, 1}, {1, 0}
};

vertex CameraVertex cameraVertex(uint vid [[vertex_id]]) {
    CameraVertex out;
    out.position = float4(kPositions[vid], 0.0, 1.0);
    out.texCoord = kTexCoords[vid];
    return out;
}

// BGRA texture sampled as RGBA — Metal handles the channel swizzle for bgra8Unorm.
fragment float4 cameraFragment(CameraVertex        in  [[stage_in]],
                               texture2d<float>    tex [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return tex.sample(s, in.texCoord);
}
