#version 300 es
precision mediump float;
// StainedGlass — Cathedral leaded pane segmentation
// Voronoi cells as glass panes + lead lines + transmitted light colour + imperfections
//
// GLSL ES 300 fragment shader. Uniforms: iChannel0, iTime



uniform sampler2D iChannel0;
uniform float iTime;

out vec4 fragColor;

float hash21(vec2 p){vec3 p3=fract(vec3(p.xyx)*0.1031);p3+=dot(p3,p3.yzx+33.33);return fract((p3.x+p3.y)*p3.z);}
float noise2(vec2 p){vec2 i=floor(p),f=fract(p),u=f*f*(3.0-2.0*f);return mix(mix(hash21(i),hash21(i+vec2(1,0)),u.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),u.x),u.y);}

vec3 hsvToRgb(vec3 hsv)
{
    vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    vec3 p = abs(fract(hsv.xxx + K.xyz) * 6.0 - K.www);
    return hsv.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), hsv.y);
}

void voronoiCell(vec2 p, out float edgeDist, out vec2 cellId, out vec2 cellCenter)
{
    vec2 ip=floor(p), fp=fract(p);
    float minD1=8.0, minD2=8.0;
    cellId=vec2(0,0); cellCenter=vec2(0,0);
    for(int y=-2;y<=2;y++) for(int x=-2;x<=2;x++){
        vec2 id=ip+vec2(x,y);
        vec2 r=vec2(hash21(id), hash21(id+97.3));
        vec2 diff=vec2(x,y)+r-fp;
        float d=dot(diff,diff);
        if(d<minD1){minD2=minD1;minD1=d;cellId=id;cellCenter=vec2(x,y)+r+fp;}
        else if(d<minD2){minD2=d;}
    }
    edgeDist=sqrt(minD2)-sqrt(minD1);
}

void main()
{
    vec2 uv = gl_FragCoord.xy / vec2(1920.0, 1080.0);
    // Two voronoi scales — large panes and smaller accent pieces
    vec2 cellId1; vec2 cellCenter1; float edge1;
    vec2 cellId2; vec2 cellCenter2; float edge2;
    voronoiCell(uv * vec2(9.0, 7.0),  edge1, cellId1, cellCenter1);
    voronoiCell(uv * vec2(18.0, 14.0), edge2, cellId2, cellCenter2);

    // Use smaller cells where large cell is near edge (lead tracery pattern)
    float useSmall = step(0.15, edge1);
    float edge     = mix(edge2, edge1, useSmall);
    vec2 cellId  = mix(cellId2, cellId1, useSmall);

    // Each pane has a distinct hue based on cell ID
    float hue = hash21(cellId + 3.7);
    float sat = 0.7 + hash21(cellId + 1.1) * 0.3;
    float val = 0.6 + hash21(cellId + 5.3) * 0.3;
    vec3 paneColor = hsvToRgb(vec3(hue, sat, val));

    // Sample source content — light passing through tints the pane colour
    vec4 raw  = texture(iChannel0, uv);
    float  luma = dot(raw.rgb, vec3(0.299, 0.587, 0.114));

    // Transmitted light: pane colour modulated by scene brightness
    vec3 transmitted = paneColor * (0.4 + luma * 0.8);

    // Glass thickness variation — bubbles and imperfections in hand-blown glass
    float thickness = noise2(uv * 12.0) * 0.3 + 0.7;
    transmitted    *= thickness;

    // Light scatter at pane edges — glass thickens near lead came
    float edgeLightup = smoothstep(0.05, 0.15, edge) * 0.3;
    transmitted       = mix(transmitted * 1.4, transmitted, edgeLightup);

    // Lead came — thick dark lines between panes
    float leadWidth = 0.06;
    float lead      = step(edge, leadWidth);
    vec3 leadColor = vec3(0.08, 0.07, 0.06);   // dark oxidised lead

    // Lead highlight — slightly shiny along the centre
    float leadCenter = smoothstep(0.0, leadWidth * 0.3, edge);
    leadColor       += leadCenter * 0.12;

    vec3 col = mix(transmitted, leadColor, lead);

    // Overall warmth — sunlight coming through
    col *= vec3(1.05, 1.0, 0.88);

    // Subtle vignette — stone window arch surrounds
    vec2 vig = uv * (1.0 - uv);
    col *= mix(0.4, 1.0, pow(vig.x * vig.y * 10.0, 0.3));

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
