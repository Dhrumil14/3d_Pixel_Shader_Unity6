Shader "Hidden/Edge Detection Voyage Style"
{
    Properties
    {
        _OutlineThickness ("Outline Thickness", Float) = 1

        [Header(Relative Edge Colour)]
        _OuterDarken ("Outer Edge Darken", Range(0, 1)) = 0.35
        _InnerBrighten ("Inner Edge Brighten", Range(0, 2)) = 0.55

        [Header(Alpha)]
        _OuterAlpha ("Outer Alpha", Range(0, 1)) = 1
        _InnerAlpha ("Inner Alpha", Range(0, 1)) = 0.55

        [Header(Thresholds)]
        _DepthThreshold ("Depth Threshold", Range(0.0001, 0.05)) = 0.003
        _NormalThreshold ("Normal Threshold", Range(0.001, 1)) = 0.20

        [Header(Strength)]
        _DepthEdgeStrength ("Depth Edge Strength", Range(0, 2)) = 1
        _NormalEdgeStrength ("Normal Edge Strength", Range(0, 2)) = 1

        [Header(Direction And Bias)]
        _DepthDirection ("Depth Direction", Range(-1, 1)) = 1
        _NormalEdgeBias ("Normal Edge Bias", Vector) = (1, 1, 1, 0)
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
            Name "VOYAGE STYLE EDGE DETECTION"

            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            float _OutlineThickness;

            float _OuterDarken;
            float _InnerBrighten;

            float _OuterAlpha;
            float _InnerAlpha;

            float _DepthThreshold;
            float _NormalThreshold;

            float _DepthEdgeStrength;
            float _NormalEdgeStrength;

            float _DepthDirection;
            float3 _NormalEdgeBias;

            float GetDepth(float2 uv)
            {
                float rawDepth = SampleSceneDepth(uv);
                return Linear01Depth(rawDepth, _ZBufferParams);
            }

            float3 GetNormal(float2 uv)
            {
                return normalize(SampleSceneNormals(uv));
            }

            float3 GetSceneColour(float2 uv)
            {
                return SampleSceneColor(uv);
            }

            void VoyageOutline(
                float2 uv,
                out float depthOutline,
                out float normalOutline,
                out float3 nearestColour
            )
            {
                float2 texelSize = float2(1.0 / _ScreenParams.x, 1.0 / _ScreenParams.y);
                texelSize *= max(1.0, _OutlineThickness);

                float centreDepth = GetDepth(uv);
                float3 centreNormal = GetNormal(uv);
                float3 centreColour = GetSceneColour(uv);

                float2 uvs[4];

                // Pixel-perfect cardinal sampling:
                // up, down, right, left.
                uvs[0] = uv + float2(0.0, texelSize.y);
                uvs[1] = uv - float2(0.0, texelSize.y);
                uvs[2] = uv + float2(texelSize.x, 0.0);
                uvs[3] = uv - float2(texelSize.x, 0.0);

                float depths[4];
                float3 normals[4];

                float depthDifference = 0.0;

                nearestColour = centreColour;
                float nearestDepth = centreDepth;

                [unroll]
                for (int i = 0; i < 4; i++)
                {
                    depths[i] = GetDepth(uvs[i]);

                    // Directional depth edge.
                    //
                    // _DepthDirection = 1:
                    //   centreDepth - neighbourDepth
                    //   tends to mark the outside/background side near objects.
                    //
                    // _DepthDirection = -1:
                    //   neighbourDepth - centreDepth
                    //   flips the side.
                    depthDifference += (centreDepth - depths[i]) * _DepthDirection;

                    // Find closest visible neighbour so outer edge inherits object colour.
                    if (depths[i] < nearestDepth)
                    {
                        nearestDepth = depths[i];
                        nearestColour = GetSceneColour(uvs[i]);
                    }
                }

                float depthEdge = step(_DepthThreshold, depthDifference);

                float dotSum = 0.0;

                [unroll]
                for (int j = 0; j < 4; j++)
                {
                    normals[j] = GetNormal(uvs[j]);

                    float3 normalDiff = centreNormal - normals[j];

                    // Direction/bias filter.
                    // This prevents every normal change from becoming a line.
                    float normalBiasDiff = dot(normalDiff, _NormalEdgeBias);
                    float normalIndicator = smoothstep(-0.01, 0.01, normalBiasDiff);

                    dotSum += dot(normalDiff, normalDiff) * normalIndicator;
                }

                float normalIndicatorFinal = sqrt(dotSum);
                float normalEdge = step(_NormalThreshold, normalIndicatorFinal);

                // Depth wins.
                // Outer silhouettes should not also become bright normal highlights.
                normalEdge *= (1.0 - depthEdge);

                depthOutline = saturate(depthEdge * _DepthEdgeStrength);
                normalOutline = saturate(normalEdge * _NormalEdgeStrength);
            }

            half4 frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                float depthEdge;
                float normalEdge;
                float3 nearestColour;

                VoyageOutline(
                    uv,
                    depthEdge,
                    normalEdge,
                    nearestColour
                );

                float3 centreColour = GetSceneColour(uv);

                // Object-relative colours:
                // depth edge = darker nearby object colour
                // normal edge = brighter centre object colour
                float3 outerColour = nearestColour * _OuterDarken;
                float3 innerColour = saturate(centreColour * (1.0 + _InnerBrighten));

                if (depthEdge > 0.5)
                {
                    return half4(outerColour, _OuterAlpha);
                }

                if (normalEdge > 0.5)
                {
                    return half4(innerColour, _InnerAlpha);
                }

                return half4(0, 0, 0, 0);
            }

            ENDHLSL
        }
    }

    FallBack Off
}