Shader "Hidden/NewShader"
{
    Properties
    {
        _DebugMode ("Debug Mode", Range(0, 3)) = 0

        _OutlineThickness ("Outline Thickness", Float) = 1

        _OuterDarken ("Outer Edge Darken", Range(0, 1)) = 0.35
        _InnerBrighten ("Inner Edge Brighten", Range(0, 2)) = 0.45

        _OuterAlpha ("Outer Alpha", Range(0, 1)) = 1
        _InnerAlpha ("Inner Alpha", Range(0, 1)) = 0.55

        _DepthThreshold ("Depth Threshold", Range(0.001, 1)) = 0.2
        _NormalThreshold ("Normal Threshold", Range(0.001, 1)) = 0.2

        _DepthStrength ("Depth Strength", Range(0, 3)) = 1
        _NormalStrength ("Normal Strength", Range(0, 3)) = 1
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
        }

        ZWrite Off
        Cull Off
        ZTest Always
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            Name "NEW SHADER GODOT STYLE EDGES"

            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            float _DebugMode;

            float _OutlineThickness;

            float _OuterDarken;
            float _InnerBrighten;

            float _OuterAlpha;
            float _InnerAlpha;

            float _DepthThreshold;
            float _NormalThreshold;

            float _DepthStrength;
            float _NormalStrength;

            float GetEyeDepth(float2 uv)
            {
                float rawDepth = SampleSceneDepth(uv);

                // Similar purpose to Godot's getDepth():
                // returns camera/view distance, not just raw depth buffer value.
                return LinearEyeDepth(rawDepth, _ZBufferParams);
            }

            float3 GetNormal(float2 uv)
            {
                return normalize(SampleSceneNormals(uv));
            }

            float3 GetSceneColor(float2 uv)
            {
                return SampleSceneColor(uv);
            }

            float NormalIndicator(
                float3 normalEdgeBias,
                float3 baseNormal,
                float3 newNormal,
                float depthDiff
            )
            {
                // Based on the Godot normalIndicator() idea.
                float normalDiff = dot(baseNormal - newNormal, normalEdgeBias);

                float normalIndicator = saturate(
                    smoothstep(-0.01, 0.01, normalDiff)
                );

                // Only allow normal highlights where the depth relation makes sense.
                float depthIndicator = saturate(
                    sign(depthDiff * 0.25 + 0.0025)
                );

                return (1.0 - saturate(dot(baseNormal, newNormal)))
                    * depthIndicator
                    * normalIndicator;
            }

            void ComputeEdges(
                float2 uv,
                float2 px,
                out float depthEdge,
                out float normalEdge,
                out float negativeDepthMask
            )
            {
                float depth = GetEyeDepth(uv);

                float depthU = GetEyeDepth(uv + float2(0.0, -1.0) * px);
                float depthR = GetEyeDepth(uv + float2(1.0,  0.0) * px);
                float depthD = GetEyeDepth(uv + float2(0.0,  1.0) * px);
                float depthL = GetEyeDepth(uv + float2(-1.0, 0.0) * px);

                // -------------------------------------------------------
                // 1. Depth edge / dark outer edge
                // -------------------------------------------------------
                // This follows the Godot shader idea:
                // neighbour - current = edge on foreground side.
                float depthDiff = 0.0;

                depthDiff += saturate(depthU - depth);
                depthDiff += saturate(depthD - depth);
                depthDiff += saturate(depthR - depth);
                depthDiff += saturate(depthL - depth);

                depthEdge = smoothstep(
                    _DepthThreshold,
                    _DepthThreshold + 0.1,
                    depthDiff
                );

                depthEdge *= _DepthStrength;

                // -------------------------------------------------------
                // 2. Negative depth difference
                // -------------------------------------------------------
                // Used to suppress highlights on the wrong side of depth breaks.
                float negDepthDiff = 0.0;

                negDepthDiff += saturate(depth - depthU);
                negDepthDiff += saturate(depth - depthD);
                negDepthDiff += saturate(depth - depthR);
                negDepthDiff += saturate(depth - depthL);

                negativeDepthMask = smoothstep(
                    _DepthThreshold,
                    _DepthThreshold + 0.1,
                    negDepthDiff
                );

                // -------------------------------------------------------
                // 3. Normal edge / light inner highlight
                // -------------------------------------------------------
                float3 normal = GetNormal(uv);

                float3 normalU = GetNormal(uv + float2(0.0, -1.0) * px);
                float3 normalR = GetNormal(uv + float2(1.0,  0.0) * px);
                float3 normalD = GetNormal(uv + float2(0.0,  1.0) * px);
                float3 normalL = GetNormal(uv + float2(-1.0, 0.0) * px);

                float3 normalEdgeBias = float3(1.0, 1.0, 1.0);

                float normalDiff = 0.0;

                normalDiff += NormalIndicator(normalEdgeBias, normal, normalU, depthDiff);
                normalDiff += NormalIndicator(normalEdgeBias, normal, normalR, depthDiff);
                normalDiff += NormalIndicator(normalEdgeBias, normal, normalD, depthDiff);
                normalDiff += NormalIndicator(normalEdgeBias, normal, normalL, depthDiff);

                normalEdge = smoothstep(
                    _NormalThreshold,
                    _NormalThreshold + 0.6,
                    normalDiff
                );

                // Key Godot-style suppression:
                // normal highlights should not appear on the wrong side of depth breaks.
                normalEdge = saturate(normalEdge - negativeDepthMask);

                // Depth owns strong silhouettes.
                normalEdge *= (1.0 - saturate(depthEdge));

                normalEdge *= _NormalStrength;
            }

            float3 PickForegroundColor(float2 uv, float2 px)
            {
                float centerDepth = GetEyeDepth(uv);
                float nearestDepth = centerDepth;
                float3 nearestColor = GetSceneColor(uv);

                float2 offsets[4];
                offsets[0] = float2(0.0, -1.0) * px;
                offsets[1] = float2(1.0,  0.0) * px;
                offsets[2] = float2(0.0,  1.0) * px;
                offsets[3] = float2(-1.0, 0.0) * px;

                [unroll]
                for (int i = 0; i < 4; i++)
                {
                    float2 sampleUV = uv + offsets[i];
                    float sampleDepth = GetEyeDepth(sampleUV);

                    if (sampleDepth < nearestDepth)
                    {
                        nearestDepth = sampleDepth;
                        nearestColor = GetSceneColor(sampleUV);
                    }
                }

                return nearestColor;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                // px = pixel size from the tutorial idea.
                float2 px = float2(
                    1.0 / _ScreenParams.x,
                    1.0 / _ScreenParams.y
                ) * max(1.0, _OutlineThickness);

                float depthEdge;
                float normalEdge;
                float negativeDepthMask;

                ComputeEdges(
                    uv,
                    px,
                    depthEdge,
                    normalEdge,
                    negativeDepthMask
                );

                depthEdge = saturate(depthEdge);
                normalEdge = saturate(normalEdge);

                // Debug 1: depth outer edge.
                if (_DebugMode > 0.5 && _DebugMode < 1.5)
                {
                    return half4(depthEdge.xxx, 1);
                }

                // Debug 2: normal inner highlight.
                if (_DebugMode > 1.5 && _DebugMode < 2.5)
                {
                    return half4(normalEdge.xxx, 1);
                }

                // Debug 3: negative depth suppression mask.
                if (_DebugMode > 2.5)
                {
                    return half4(negativeDepthMask.xxx, 1);
                }

                float3 originalColor = GetSceneColor(uv);

                // Relative edge colours.
                float3 foregroundColor = PickForegroundColor(uv, px);

                float3 shadowColor = foregroundColor * _OuterDarken;
                float3 highlightColor = saturate(originalColor * (1.0 + _InnerBrighten));

                // Output only the overlay contribution.
                // The RenderGraph pass blends it over the existing scene.
                if (depthEdge > 0.001)
                {
                    return half4(shadowColor, depthEdge * _OuterAlpha);
                }

                if (normalEdge > 0.001)
                {
                    return half4(highlightColor, normalEdge * _InnerAlpha);
                }

                return half4(0, 0, 0, 0);
            }

            ENDHLSL
        }
    }

    FallBack Off
}