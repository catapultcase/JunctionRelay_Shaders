// Passthrough pixel shader — identity transform.
// Samples the input texture and returns it unchanged.
// Use as a baseline or starting point for custom shader effects.

Texture2D inputTexture : register(t0);
SamplerState samplerState : register(s0);

struct PS_INPUT {
    float4 position : SV_POSITION;
    float2 texCoord : TEXCOORD0;
};

float4 main(PS_INPUT input) : SV_TARGET {
    return inputTexture.Sample(samplerState, input.texCoord);
}
