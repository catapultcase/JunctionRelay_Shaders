// StainedGlass — Cathedral leaded pane segmentation
// Voronoi cells as glass panes + lead lines + transmitted light colour + imperfections
//
// Bridge contract: t0=texture, s0=sampler, b0=TimeBuffer(float time, float3 pad)

Texture2D tex0 : register(t0);
SamplerState sampler0 : register(s0);
cbuffer TimeBuffer : register(b0) { float time; float3 _pad; };

float hash21(float2 p){float3 p3=frac(float3(p.xyx)*0.1031);p3+=dot(p3,p3.yzx+33.33);return frac((p3.x+p3.y)*p3.z);}
float noise2(float2 p){float2 i=floor(p),f=frac(p),u=f*f*(3.0-2.0*f);return lerp(lerp(hash21(i),hash21(i+float2(1,0)),u.x),lerp(hash21(i+float2(0,1)),hash21(i+float2(1,1)),u.x),u.y);}

float3 hsvToRgb(float3 hsv)
{
    float4 K = float4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    float3 p = abs(frac(hsv.xxx + K.xyz) * 6.0 - K.www);
    return hsv.z * lerp(K.xxx, saturate(p - K.xxx), hsv.y);
}

void voronoiCell(float2 p, out float edgeDist, out float2 cellId, out float2 cellCenter)
{
    float2 ip=floor(p), fp=frac(p);
    float minD1=8.0, minD2=8.0;
    cellId=float2(0,0); cellCenter=float2(0,0);
    for(int y=-2;y<=2;y++) for(int x=-2;x<=2;x++){
        float2 id=ip+float2(x,y);
        float2 r=float2(hash21(id), hash21(id+97.3));
        float2 diff=float2(x,y)+r-fp;
        float d=dot(diff,diff);
        if(d<minD1){minD2=minD1;minD1=d;cellId=id;cellCenter=float2(x,y)+r+fp;}
        else if(d<minD2){minD2=d;}
    }
    edgeDist=sqrt(minD2)-sqrt(minD1);
}

float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    // Two voronoi scales — large panes and smaller accent pieces
    float2 cellId1; float2 cellCenter1; float edge1;
    float2 cellId2; float2 cellCenter2; float edge2;
    voronoiCell(uv * float2(9.0, 7.0),  edge1, cellId1, cellCenter1);
    voronoiCell(uv * float2(18.0, 14.0), edge2, cellId2, cellCenter2);

    // Use smaller cells where large cell is near edge (lead tracery pattern)
    float useSmall = step(0.15, edge1);
    float edge     = lerp(edge2, edge1, useSmall);
    float2 cellId  = lerp(cellId2, cellId1, useSmall);

    // Each pane has a distinct hue based on cell ID
    float hue = hash21(cellId + 3.7);
    float sat = 0.7 + hash21(cellId + 1.1) * 0.3;
    float val = 0.6 + hash21(cellId + 5.3) * 0.3;
    float3 paneColor = hsvToRgb(float3(hue, sat, val));

    // Sample source content — light passing through tints the pane colour
    float4 raw  = tex0.Sample(sampler0, uv);
    float  luma = dot(raw.rgb, float3(0.299, 0.587, 0.114));

    // Transmitted light: pane colour modulated by scene brightness
    float3 transmitted = paneColor * (0.4 + luma * 0.8);

    // Glass thickness variation — bubbles and imperfections in hand-blown glass
    float thickness = noise2(uv * 12.0) * 0.3 + 0.7;
    transmitted    *= thickness;

    // Light scatter at pane edges — glass thickens near lead came
    float edgeLightup = smoothstep(0.05, 0.15, edge) * 0.3;
    transmitted       = lerp(transmitted * 1.4, transmitted, edgeLightup);

    // Lead came — thick dark lines between panes
    float leadWidth = 0.06;
    float lead      = step(edge, leadWidth);
    float3 leadColor = float3(0.08, 0.07, 0.06);   // dark oxidised lead

    // Lead highlight — slightly shiny along the centre
    float leadCenter = smoothstep(0.0, leadWidth * 0.3, edge);
    leadColor       += leadCenter * 0.12;

    float3 col = lerp(transmitted, leadColor, lead);

    // Overall warmth — sunlight coming through
    col *= float3(1.05, 1.0, 0.88);

    // Subtle vignette — stone window arch surrounds
    float2 vig = uv * (1.0 - uv);
    col *= lerp(0.4, 1.0, pow(vig.x * vig.y * 10.0, 0.3));

    return float4(saturate(col), 1.0);
}
