Shader "Custom/PixelArt/DepthEdge"
{
    Properties
    {
        [Header(Debug)]
        _DebugMode ("Debug Mode 0 Final 1 Depth 2 Normal 3 DepthEdges 4 NormalEdges 5 Combined", Range(0, 5)) = 0

        [Header(Depth Edges)]
        _DepthEdgeColor ("Depth Edge Color", Color) = (0.08, 0.11, 0.18, 1)
        _DepthThreshold ("Depth Threshold", Range(0.0001, 0.05)) = 0.003
        _DepthSoftness ("Depth Softness", Range(0.0001, 0.02)) = 0.002

        [Header(Normal Edges)]
        _NormalEdgeColor ("Normal Edge Color", Color) = (1.0, 0.92, 0.65, 1)
        _NormalThreshold ("Normal Threshold", Range(0.001, 1)) = 0.25
        _NormalSoftness ("Normal Softness", Range(0.001, 1)) = 0.15

        [Header(Shared)]
        _Thickness ("Thickness", Range(1, 16)) = 4
        _DepthEdgeStrength ("Depth Edge Strength", Range(0, 1)) = 1
        _NormalEdgeStrength ("Normal Edge Strength", Range(0, 1)) = 0.8
        _DepthDebugPower ("Depth Debug Power", Range(0.1, 5)) = 1
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" }

        Cull Off
        ZWrite Off
        ZTest Always

        Pass
        {
            Name "Pixel Outline Debug"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _DebugMode;

            float4 _DepthEdgeColor;
            float _DepthThreshold;
            float _DepthSoftness;

            float4 _NormalEdgeColor;
            float _NormalThreshold;
            float _NormalSoftness;

            float _Thickness;
            float _DepthEdgeStrength;
            float _NormalEdgeStrength;
            float _DepthDebugPower;

            float SampleLinearDepth01(float2 uv)
            {
                float rawDepth = SampleSceneDepth(uv);
                return Linear01Depth(rawDepth, _ZBufferParams);
            }

            float DepthEdge(float2 uv, float2 texel)
{
    float dC = SampleLinearDepth01(uv);

    float dL = SampleLinearDepth01(uv + float2(-texel.x, 0));
    float dR = SampleLinearDepth01(uv + float2( texel.x, 0));
    float dU = SampleLinearDepth01(uv + float2(0,  texel.y));
    float dD = SampleLinearDepth01(uv + float2(0, -texel.y));

    // Only draw the edge on the nearer pixel side.
    // This is better than abs(), because abs() outlines both near and far surfaces.
    float diffL = dL - dC;
    float diffR = dR - dC;
    float diffU = dU - dC;
    float diffD = dD - dC;

    float maxDiff = max(max(diffL, diffR), max(diffU, diffD));

    return smoothstep(
        _DepthThreshold,
        _DepthThreshold + _DepthSoftness,
        maxDiff
    );
}

            float NormalEdge(float2 uv, float2 texel)
{
    float dC = SampleLinearDepth01(uv);

    float dL = SampleLinearDepth01(uv + float2(-texel.x, 0));
    float dR = SampleLinearDepth01(uv + float2( texel.x, 0));
    float dU = SampleLinearDepth01(uv + float2(0,  texel.y));
    float dD = SampleLinearDepth01(uv + float2(0, -texel.y));

    float3 nC = normalize(SampleSceneNormals(uv));

    float3 nL = normalize(SampleSceneNormals(uv + float2(-texel.x, 0)));
    float3 nR = normalize(SampleSceneNormals(uv + float2( texel.x, 0)));
    float3 nU = normalize(SampleSceneNormals(uv + float2(0,  texel.y)));
    float3 nD = normalize(SampleSceneNormals(uv + float2(0, -texel.y)));

    float diffL = 1.0 - saturate(dot(nC, nL));
    float diffR = 1.0 - saturate(dot(nC, nR));
    float diffU = 1.0 - saturate(dot(nC, nU));
    float diffD = 1.0 - saturate(dot(nC, nD));

    // Critical fix:
    // Normal edges should only happen when depth difference is small.
    // If depth difference is large, that is an external silhouette,
    // and should be handled by DepthEdge(), not NormalEdge().
    float depthDiffL = abs(dC - dL);
    float depthDiffR = abs(dC - dR);
    float depthDiffU = abs(dC - dU);
    float depthDiffD = abs(dC - dD);

    float sameSurfaceL = 1.0 - smoothstep(_DepthThreshold, _DepthThreshold + _DepthSoftness, depthDiffL);
    float sameSurfaceR = 1.0 - smoothstep(_DepthThreshold, _DepthThreshold + _DepthSoftness, depthDiffR);
    float sameSurfaceU = 1.0 - smoothstep(_DepthThreshold, _DepthThreshold + _DepthSoftness, depthDiffU);
    float sameSurfaceD = 1.0 - smoothstep(_DepthThreshold, _DepthThreshold + _DepthSoftness, depthDiffD);

    diffL *= sameSurfaceL;
    diffR *= sameSurfaceR;
    diffU *= sameSurfaceU;
    diffD *= sameSurfaceD;

    float maxDiff = max(max(diffL, diffR), max(diffU, diffD));

    return smoothstep(
        _NormalThreshold,
        _NormalThreshold + _NormalSoftness,
        maxDiff
    );
}

            half4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float2 texel = _BlitTexture_TexelSize.xy * _Thickness;

                half4 sceneColor = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);

                float depth01 = SampleLinearDepth01(uv);
                float3 normalWS = normalize(SampleSceneNormals(uv));

                float depthEdge = DepthEdge(uv, texel) * _DepthEdgeStrength;
                float normalEdge = NormalEdge(uv, texel) * _NormalEdgeStrength;

                // Debug Mode 1: show depth map.
                if (_DebugMode < 1.5 && _DebugMode > 0.5)
                {
                    float d = pow(saturate(depth01), _DepthDebugPower);
                    return half4(d, d, d, 1);
                }

                // Debug Mode 2: show normal map.
                if (_DebugMode < 2.5 && _DebugMode > 1.5)
                {
                    float3 normalColor = normalWS * 0.5 + 0.5;
                    return half4(normalColor, 1);
                }

                // Debug Mode 3: show depth edges only.
                if (_DebugMode < 3.5 && _DebugMode > 2.5)
                {
                    return half4(depthEdge.xxx, 1);
                }

                // Debug Mode 4: show normal edges only.
                if (_DebugMode < 4.5 && _DebugMode > 3.5)
                {
                    return half4(normalEdge.xxx, 1);
                }

                // Debug Mode 5: show combined mask.
                if (_DebugMode > 4.5)
                {
                    float combined = saturate(depthEdge + normalEdge);
                    return half4(combined.xxx, 1);
                }

                // Debug Mode 0: final composite.
                half3 finalColor = sceneColor.rgb;

                // Depth edges darken.
                finalColor = lerp(finalColor, _DepthEdgeColor.rgb, saturate(depthEdge));

                // Normal edges brighten.
                finalColor = lerp(finalColor, _NormalEdgeColor.rgb, saturate(normalEdge));

                return half4(finalColor, sceneColor.a);
            }

            ENDHLSL
        }
    }

    FallBack Off
}