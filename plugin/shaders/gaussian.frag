#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 direction;
    float sigma;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    float s=max(sigma,0.05);
    float stepSize=max(0.5,s/6.0);
    vec4 sum=vec4(0.0);
    float total=0.0;
    for(int i=-24;i<=24;i++) {
        float d=float(i)*stepSize;
        float weight=exp(-0.5*d*d/(s*s));
        sum+=texture(source,qt_TexCoord0+direction*d)*weight;
        total+=weight;
    }
    fragColor=sum/total*qt_Opacity;
}
