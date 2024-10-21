# My Portfolio

## Custom render feature with custom postprocessing volume

Adaptation of this [built-in](https://github.com/imclab/TiltShift/tree/master) shader for URP.

<iframe width="800" height="450" src="https://www.youtube.com/embed/dvxGyGokUt8" frameborder="0" allowfullscreen></iframe>

<details>
<summary>Shader code.</summary>

<pre> ```hlsl
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
                r += 1.0 / r;
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
        Cull Off ZWrite Off

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
```
</pre>
</details>


<details>
<summary>Custom volume code.</summary>

```cs
using System;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[Serializable, VolumeComponentMenuForRenderPipeline ("Postprocess/TiltShift", typeof(UniversalRenderPipeline))]
public class TiltShiftPostprocess : VolumeComponent, IPostProcessComponent
{
    public BoolParameter Active = new BoolParameter(true);

    public ClampedFloatParameter  Offset = new ClampedFloatParameter(0f, 0f, 1f);

    public ClampedFloatParameter Area = new ClampedFloatParameter(1f, 0f, 20f);

    public ClampedFloatParameter Spread = new ClampedFloatParameter(1f, 0f, 20f);

    public ClampedIntParameter Samples = new ClampedIntParameter(32, 4, 64);

    public ClampedFloatParameter Radius = new ClampedFloatParameter(2f, 0f, 2f);

    public ClampedFloatParameter CubicDistortion = new ClampedFloatParameter(5f, 0f, 20f);

    public ClampedFloatParameter DistortionScale = new ClampedFloatParameter(1f, 0f, 1f);

    public bool IsActive() => Active.value;

    public bool IsTileCompatible() => true;
}
```
</details>


<details>
  <summary>Render feature code.</summary>

```cs
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class TiltShiftRenderFeature : ScriptableRendererFeature
{
    private Material m_Material;
    class TiltShiftRenderPass : ScriptableRenderPass
    {
        private Material m_Material;
        // private static readonly int m_tiltId = Shader.PropertyToID("_TiltPass");

        private RTHandle m_Tilt;
        private RenderTextureDescriptor m_TiltTextureDescriptor;

        // Golden Ratio Angle
        private Vector4 m_GoldenRatioAngle = Vector4.zero;
        private const float m_GoldenRatio = 2.39996323f;

        public TiltShiftRenderPass(Material material)
        {
            m_Material = material;

            float goldenCos = Mathf.Cos(m_GoldenRatio);
            float goldenSin = Mathf.Sin(m_GoldenRatio);

            m_GoldenRatioAngle.Set(goldenCos, goldenSin, -goldenSin, goldenCos);

            m_TiltTextureDescriptor = new RenderTextureDescriptor(
                Screen.width, Screen.height,
                RenderTextureFormat.Default, 0);
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            m_TiltTextureDescriptor.width = cameraTextureDescriptor.width;
            m_TiltTextureDescriptor.height = cameraTextureDescriptor.height;

            RenderingUtils.ReAllocateIfNeeded(ref m_Tilt, m_TiltTextureDescriptor); // move to configure
        }

        // In URP 14 have blit problem, need to investigate
        // possible solution: https://discussions.unity.com/t/resolved-custom-render-pass-failing-urp-v14-0-6/911141/3
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer commandBuffer = CommandBufferPool.Get();
            
            VolumeStack volumeStack = VolumeManager.instance.stack;
            TiltShiftPostprocess tiltData = volumeStack.GetComponent<TiltShiftPostprocess>();

            RTHandle cameraTargetHandle = renderingData.cameraData.renderer.cameraColorTargetHandle;

            if (cameraTargetHandle == null)
                return;
            
            if (tiltData.IsActive())
            {
                UpdateTiltMaterial(tiltData);

                if(m_Material!=null)
                {
                    if(cameraTargetHandle == null) 
                    {
                        Debug.LogWarning("TiltTex is null");
                    }
                    if( cameraTargetHandle == null)
                    {
                        Debug.LogWarning("Camera is null");
                    }
                    Blit(commandBuffer, cameraTargetHandle, m_Tilt, m_Material, 0);
                    Blit(commandBuffer, m_Tilt, cameraTargetHandle, null, 1);
                }
            }

            context.ExecuteCommandBuffer(commandBuffer);
            CommandBufferPool.Release(commandBuffer);
        }

        private void UpdateTiltMaterial(TiltShiftPostprocess tiltData)
        {
            if (m_Material == null)
            {
                return;
            }

            // TODO move string to const or Shader Property ID
            m_Material.SetFloat("_Offset", tiltData.Offset.value);
            m_Material.SetFloat("_Area", tiltData.Area.value);
            m_Material.SetFloat("_Spread", tiltData.Spread.value);
            m_Material.SetInt("_Samples", tiltData.Samples.value);
            m_Material.SetFloat("_Radius", tiltData.Radius.value);
            m_Material.SetFloat("_CubicDistortion", tiltData.CubicDistortion.value);
            m_Material.SetFloat("_DistortionScale", tiltData.DistortionScale.value);


            // Setting up precalulated staff from here https://www.shadertoy.com/view/4d2Xzw
            // to not calculate at runtime
            m_Material.SetVector("_GoldenRatioAngle", m_GoldenRatioAngle);
        }

        public void Dispose()
        {
           // would material be deleted twice?
            // #if UNITY_EDITOR
            //     if (EditorApplication.isPlaying)
            //     {
            //         Destroy(m_Material);
            //     }
            //     else
            //     {
            //         DestroyImmediate(m_Material);
            //     }
            // #else
            //     Destroy(m_Material);
            // #endif
            
            if (m_Tilt!= null)
            {
                m_Tilt.Release();
            }
        }
    }

    TiltShiftRenderPass m_ScriptablePass;


    public override void Create()
    {
        if (m_Material == null || m_Material.shader == null)
        {
            if (m_Material!=null)
            {
                CoreUtils.Destroy(m_Material);
            }

            m_Material = CoreUtils.CreateEngineMaterial("PostProcess/TiltShift");
        }
        m_ScriptablePass = new TiltShiftRenderPass(m_Material);
        m_ScriptablePass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_ScriptablePass);
    }


    protected override void Dispose(bool disposing)
    {
        m_ScriptablePass.Dispose();
        #if UNITY_EDITOR
            if (EditorApplication.isPlaying)
            {
                Destroy(m_Material);
            }
            else
            {
                DestroyImmediate(m_Material);
            }
        #else
            Destroy(m_Material);
        #endif
        
    }
}
  ```
</details>



## Lowpoly

Mixamo integration test.

<iframe width="800" height="450" src="https://www.youtube.com/embed/rUhSBQ9xL9A" frameborder="0" allowfullscreen></iframe>

