// FrozenGlass — Ice crystal refraction with frost dendrite growth patterns
// Voronoi ice structure + fractal frost edges + frozen colour grade + condensation
//
// Bridge contract: t0=texture, s0=sampler, b0=TimeBuffer(float time, float3 pad)

Texture2D tex0 : register(t0);
SamplerState sampler0 : register(s0);
cbuffer TimeBuffer : register(b0) { float time; float3 _pad; };

float hash21(float2 p) { float3 p3=frac(float3(p.xyx)*0.1031); p3+=dot(p3,p3.yzx+33.33); return frac((p3.x+p3.y)*p3.z); }
float noise2(float2 p) {
    float2 i=floor(p),f=frac(p),u=f*f*(3.0-2.0*f);
    return lerp(lerp(hash21(i),hash21(i+float2(1,0)),u.x),lerp(hash21(i+float2(0,1)),hash21(i+float2(1,1)),u.x),u.y);
}
float fbm(float2 p) {
    float v=0.0,a=0.5;
    float2x2 r=float2x2(0.8,-0.6,0.6,0.8);
    for(int i=0;i<5;i++){v+=a*noise2(p);p=mul(r,p)*2.2;a*=0.5;}
    return v;
}

// Voronoi returning edge distance (for ice crystal boundaries)
float voronoiEdge(float2 p)
{
    float2 ip=floor(p), fp=frac(p);
    float minD1=8.0, minD2=8.0;
    for(int y=-2;y<=2;y++) for(int x=-2;x<=2;x++) {
        float2 id=ip+float2(x,y);
        float2 r=float2(hash21(id),hash21(id+97.3));
        float2 diff=float2(x,y)+r-fp;
        float d=dot(diff,diff);
        if(d<minD1){minD2=minD1;minD1=d;}
        else if(d<minD2){minD2=d;}
    }
    return sqrt(minD2)-sqrt(minD1);
}

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // Ice crystal voronoi structure — refraction through crystal facets
    float2 iceUV  = uv * float2(8.0, 6.0);
    float  edge   = voronoiEdge(iceUV);
    float  crystal = smoothstep(0.0, 0.15, edge);   // 1=inside crystal, 0=at boundary

    // Each crystal facet refracts slightly differently
    float2 facetNormal;
    facetNormal.x = fbm(iceUV + float2(3.1, 1.7)) - 0.5;
    facetNormal.y = fbm(iceUV + float2(1.7, 4.3)) - 0.5;
    float  iceThickness = fbm(uv * 4.0) * 0.5 + 0.5;
    float2 refractUV = saturate(uv + facetNormal * iceThickness * 0.025 * crystal);

    float4 col = tex0.Sample(sampler0, refractUV);

    // Frost dendrites — fractal branching patterns grown from edges
    float frost = fbm(uv * 12.0);
    frost      += fbm(uv * 24.0 + float2(1.3, 2.7)) * 0.5;
    frost      /= 1.5;
    // Frost is stronger at screen edges (cold radiates inward from window frame)
    float2 fromEdge = min(uv, 1.0 - uv);
    float edgeFrost = 1.0 - smoothstep(0.0, 0.35, min(fromEdge.x, fromEdge.y));
    frost *= edgeFrost;
    float frostMask = smoothstep(0.45, 0.65, frost);

    // Ice crystal boundary lines — visible facet edges
    float crystalEdge = 1.0 - smoothstep(0.0, 0.04, edge);

    // Frozen colour grade — desaturate and push blue-white
    float luma = dot(col.rgb, float3(0.299, 0.587, 0.114));
    float3 frozen = lerp(col.rgb, float3(luma, luma, luma), 0.6);
    frozen = lerp(frozen, frozen * float3(0.75, 0.88, 1.0), 0.5);

    col.rgb = frozen;

    // Overlay frost as white-blue opaque layer
    col.rgb = lerp(col.rgb, float3(0.85, 0.92, 1.0), frostMask * 0.85);

    // Crystal edge lines as bright white
    col.rgb = lerp(col.rgb, float3(0.9, 0.95, 1.0), crystalEdge * 0.5 * crystal);

    // Condensation droplets — tiny beads of water where frost has half-melted
    float2 dropGrid = uv * float2(60.0, 40.0);
    float2 dc = floor(dropGrid);
    float2 df = frac(dropGrid);
    float2 dp = float2(hash21(dc), hash21(dc+5.1));
    float  dd = length(df - dp);
    float  dropMask = step(dd, 0.18) * (1.0 - edgeFrost);
    col.rgb = lerp(col.rgb, col.rgb * float3(0.7,0.85,1.0) + 0.1, dropMask * 0.6);

    // Overall blue-cold tint
    col.rgb *= float3(0.88, 0.93, 1.02);

    return saturate(col);
}
