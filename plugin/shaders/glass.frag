#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 surfaceSize;
    float cardWidth;
    float cardHeight;
    float split;
    float corner;
};
float box(vec2 p, vec2 b, float r) {
    vec2 q = abs(p)-b+r;
    return min(max(q.x,q.y),0.0)+length(max(q,0.0))-r;
}
float unite(float a, float b, float k) {
    float h=clamp(0.5+0.5*(b-a)/k,0.0,1.0);
    return mix(b,a,h)-k*h*(1.0-h);
}
void main() {
    vec2 p=qt_TexCoord0*surfaceSize-vec2(24.0);
    float w=mix(cardWidth,cardWidth-256.0,split);
    float d=box(p-vec2(w,cardHeight)*0.5,vec2(w,cardHeight)*0.5,corner);
    float k=0.1+20.0*sin(split*3.14159265);
    for(int i=0;i<4;i++) {
        float cx=mix(cardWidth-28.0,cardWidth-220.0+float(i)*64.0,split);
        float disc=length(p-vec2(cx,28.0))-27.5;
        d=unite(d,disc,k);
    }
    float aa=max(fwidth(d),0.65);
    float inside=1.0-smoothstep(-aa*0.5,aa*0.5,d);
    float edge=(1.0-smoothstep(0.45,1.25,-d))*inside;
    float shadow=exp(-max(d,0.0)/7.0)*0.12*(1.0-inside);
    vec3 base=vec3(0.085,0.085,0.094);
    // One continuous translucent material across joined circles and capsule.
    float a=mix(0.86,0.91,edge)*inside+shadow;
    vec3 line=mix(vec3(0.24),vec3(0.38),clamp(1.0-p.y/180.0,0.0,1.0));
    vec3 rgb=mix(base,line,edge*0.75);
    fragColor=vec4(rgb*a,a)*qt_Opacity;
}
