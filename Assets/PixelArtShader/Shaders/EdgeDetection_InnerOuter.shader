Shader "Hidden/Edge Detection InnerOuter"
{
    Properties
    {
        _OutlineThickness ("Outline Thickness", Float) = 2

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

        [Header(Normal Bias)]
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
            Name "EDGE DETECTION INNER OUTER"

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

            void Outline_float(
                float2 uv,
                float depthThreshold,
                float normalsThreshold,
                float3 normalEdgeBias,
                float depthEdgeStrength,
                float normalEdgeStrength,
                out float depthOutline,
                out float normalOutline
            )
            {
                float2 texelSize = float2(1.0 / _ScreenParams.x, 1.0 / _ScreenParams.y);
                texelSize *= max(1.0, _OutlineThickness);

                float depth = GetDepth(uv);
                float3 normal = GetNormal(uv);

                float2 uvs[4];

                // Cardinal neighbours: up, down, right, left.
                uvs[0] = uv + float2(0.0, texelSize.y);
                uvs[1] = uv - float2(0.0, texelSize.y);
                uvs[2] = uv + float2(texelSize.x, 0.0);
                uvs[3] = uv - float2(texelSize.x, 0.0);

                // -----------------------------
                // Depth edge indicator
                // -----------------------------

                float depths[4];
                float depthDifference = 0.0;

                [unroll]
                for (int i = 0; i < 4; i++)
                {
                    depths[i] = GetDepth(uvs[i]);

                    // Directional depth comparison.
                    // With Linear01Depth, nearer = smaller, farther = larger.
                    // neighbour - centre catches current-pixel foreground silhouettes.
                    depthDifference += depths[i] - depth;
                }

                float depthEdge = step(depthThreshold, depthDifference);

                // -----------------------------
                // Normal edge indicator
                // -----------------------------

                float3 normals[4];
                float dotSum = 0.0;

                [unroll]
                for (int j = 0; j < 4; j++)
                {
                    normals[j] = GetNormal(uvs[j]);

                    float3 normalDiff = normal - normals[j];

                    // Bias decides which normal changes are accepted.
                    float normalBiasDiff = dot(normalDiff, normalEdgeBias);
                    float normalIndicator = smoothstep(-0.01, 0.01, normalBiasDiff);

                    dotSum += dot(normalDiff, normalDiff) * normalIndicator;
                }

                float indicator = sqrt(dotSum);
                float normalEdge = step(normalsThreshold, indicator);

                // If this is a strong depth silhouette, depth owns it.
                // Normals should mainly show inner creases.
                normalEdge *= (1.0 - depthEdge);

                depthOutline = depthEdge * depthEdgeStrength;
                normalOutline = normalEdge * normalEdgeStrength;
            }

            half4 frag(Varyings IN) : SV_TARGET
            {
                float2 uv = IN.texcoord;

                float depthEdge;
                float normalEdge;

                Outline_float(
                    uv,
                    _DepthThreshold,
                    _NormalThreshold,
                    _NormalEdgeBias,
                    _DepthEdgeStrength,
                    _NormalEdgeStrength,
                    depthEdge,
                    normalEdge
                );

                depthEdge = saturate(depthEdge);
                normalEdge = saturate(normalEdge);

                float3 centreColour = GetSceneColour(uv);

                // Look around for a nearby foreground/object colour.
                // This helps the dark outer line inherit the object colour,
                // instead of only using the exact current pixel.
                float2 texelSize = float2(1.0 / _ScreenParams.x, 1.0 / _ScreenParams.y);
                texelSize *= max(1.0, _OutlineThickness);

                float2 uvs[4];
                uvs[0] = uv + float2(0.0, texelSize.y);
                uvs[1] = uv - float2(0.0, texelSize.y);
                uvs[2] = uv + float2(texelSize.x, 0.0);
                uvs[3] = uv - float2(texelSize.x, 0.0);

                float centreDepth = GetDepth(uv);
                float nearestDepth = centreDepth;
                float3 nearestColour = centreColour;

                [unroll]
                for (int i = 0; i < 4; i++)
                {
                    float d = GetDepth(uvs[i]);

                    if (d < nearestDepth)
                    {
                        nearestDepth = d;
                        nearestColour = GetSceneColour(uvs[i]);
                    }
                }

                float3 outerColour = nearestColour * _OuterDarken;
                float3 innerColour = saturate(centreColour * (1.0 + _InnerBrighten));

                // Depth edges are dark outer lines.
                if (depthEdge > 0.5)
                {
                    return half4(outerColour, _OuterAlpha);
                }

                // Normal edges are light inner highlights.
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