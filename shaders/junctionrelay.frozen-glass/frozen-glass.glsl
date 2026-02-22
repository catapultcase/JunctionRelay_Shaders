// FrozenGlass — Ice crystal refraction with frost dendrite growth patterns
// Voronoi ice structure + fractal frost edges + frozen colour grade + condensation
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime

float hash21(vec2 p) { vec3 p3=fract(vec3(p.xyx)*0.1031); p3+=dot(p3,p3.yzx+33.33); return fract((p3.x+p3.y)*p3.z); }
float noise2(vec2 p) {
    vec2 i=floor(p),f=fract(p),u=f*f*(3.0-2.0*f);
    return mix(mix(hash21(i),hash21(i+vec2(1,0)),u.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),u.x),u.y);
}
float fbm(vec2 p) {
    float v=0.0,a=0.5;
    mat2 r=mat2(0.8,-0.6,0.6,0.8);
    for(int i=0;i<5;i++){v+=a*noise2(p);p=r * p*2.2;a*=0.5;}
    return v;
}

// Voronoi returning edge distance (for ice crystal boundaries)
float voronoiEdge(vec2 p)
{
    vec2 ip=floor(p), fp=fract(p);
    float minD1=8.0, minD2=8.0;
    for(int y=-2;y<=2;y++) for(int x=-2;x<=2;x++) {
        vec2 id=ip+vec2(x,y);
        vec2 r=vec2(hash21(id),hash21(id+97.3));
        vec2 diff=vec2(x,y)+r-fp;
        float d=dot(diff,diff);
        if(d<minD1){minD2=minD1;minD1=d;}
        else if(d<minD2){minD2=d;}
    }
    return sqrt(minD2)-sqrt(minD1);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord.xy / iResolution.xy;
    // Ice crystal voronoi structure — refraction through crystal facets
    vec2 iceUV  = uv * vec2(8.0, 6.0);
    float  edge   = voronoiEdge(iceUV);
    float  crystal = smoothstep(0.0, 0.15, edge);   // 1=inside crystal, 0=at boundary

    // Each crystal facet refracts slightly differently
    vec2 facetNormal;
    facetNormal.x = fbm(iceUV + vec2(3.1, 1.7)) - 0.5;
    facetNormal.y = fbm(iceUV + vec2(1.7, 4.3)) - 0.5;
    float  iceThickness = fbm(uv * 4.0) * 0.5 + 0.5;
    vec2 refractUV = clamp(uv + facetNormal * iceThickness * 0.025 * crystal, 0.0, 1.0);

    vec4 col = texture(iChannel0, refractUV);

    // Frost dendrites — fractal branching patterns grown from edges
    float frost = fbm(uv * 12.0);
    frost      += fbm(uv * 24.0 + vec2(1.3, 2.7)) * 0.5;
    frost      /= 1.5;
    // Frost is stronger at screen edges (cold radiates inward from window frame)
    vec2 fromEdge = min(uv, 1.0 - uv);
    float edgeFrost = 1.0 - smoothstep(0.0, 0.35, min(fromEdge.x, fromEdge.y));
    frost *= edgeFrost;
    float frostMask = smoothstep(0.45, 0.65, frost);

    // Ice crystal boundary lines — visible facet edges
    float crystalEdge = 1.0 - smoothstep(0.0, 0.04, edge);

    // Frozen colour grade — desaturate and push blue-white
    float luma = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    vec3 frozen = mix(col.rgb, vec3(luma, luma, luma), 0.6);
    frozen = mix(frozen, frozen * vec3(0.75, 0.88, 1.0), 0.5);

    col.rgb = frozen;

    // Overlay frost as white-blue opaque layer
    col.rgb = mix(col.rgb, vec3(0.85, 0.92, 1.0), frostMask * 0.85);

    // Crystal edge lines as bright white
    col.rgb = mix(col.rgb, vec3(0.9, 0.95, 1.0), crystalEdge * 0.5 * crystal);

    // Condensation droplets — tiny beads of water where frost has half-melted
    vec2 dropGrid = uv * vec2(60.0, 40.0);
    vec2 dc = floor(dropGrid);
    vec2 df = fract(dropGrid);
    vec2 dp = vec2(hash21(dc), hash21(dc+5.1));
    float  dd = length(df - dp);
    float  dropMask = step(dd, 0.18) * (1.0 - edgeFrost);
    col.rgb = mix(col.rgb, col.rgb * vec3(0.7,0.85,1.0) + 0.1, dropMask * 0.6);

    // Overall blue-cold tint
    col.rgb *= vec3(0.88, 0.93, 1.02);

    fragColor = clamp(col, 0.0, 1.0);
}
