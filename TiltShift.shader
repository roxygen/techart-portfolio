Shader "PostProcess/TiltShift"
{
    HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

        float _Offset;
        float _Area;
        float _Spread;
        float _Samples;
        float _Radius;
        
        float2 _PixelSize;
        
        float _CubicDistortion;
        float _DistortionScale;

        float4 _GoldenRatioAngle;

        float4 _BlitTexture_TexelSize;

        inline half gradient (half2 uv)
        {
            half2 h = uv.xy - half2(0.5, 0.5);
            half r2 = dot(h, h);

            uv = (1.0 + r2 * (_CubicDistortion * sqrt(r2))) * _DistortionScale * h + 0.5;
            
            half2 coord = uv * 2.0 - 1.0 + _Offset;
            return pow ( abs (coord.y * _Area), _Spread);

        }

        half4 Tilt(Varyings input) : SV_Target
        {
            half2x2 rot = half2x2(_GoldenRatioAngle);
            half4 accumulator = 0.0;
            half4 divisor = 0.0;

            half r = 1.0;
            half2 angle = half2(0.0, _Radius * saturate(gradient(input.texcoord)));

            for (int i = 0; i < _Samples; i++)
            {
                // float d = 6.28 * r / float(_Samples);
                r += 1.0 / r;// - d;
                angle = mul(rot, angle);
                half4 bokeh = SAMPLE_TEXTURE2D(
                    _BlitTexture,
                    sampler_LinearClamp,
                    input.texcoord + _PixelSize * (r - 1.0) * angle
                );

                accumulator += bokeh * bokeh;
                divisor += bokeh;
            }
            
            return accumulator/divisor;
        }
    ENDHLSL

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "UniversalPipeline"}
        // No culling or depth
        ZTest Always Cull Off ZWrite Off

        Pass
        {
            Name "TiltPass"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Tilt

            ENDHLSL
        }
    }
}
