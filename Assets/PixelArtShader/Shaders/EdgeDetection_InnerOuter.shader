Shader "Hidden/Edge Detection InnerOuter"
{
    Properties
    {
        _OutlineThickness ("Outline Thickness", Float) = 1

        [Header(Relative Edge Colours)]
        _OuterDarken ("Outer Edge Darken", Range(0, 1)) = 0.35
        _InnerBrighten ("Inner Edge Brighten", Range(0, 2)) = 0.55

        [Header(Edge Strength)]
        _OuterAlpha ("Outer Edge Alpha", Range(0, 1)) = 1
        _InnerAlpha ("Inner Edge Alpha", Range(0, 1)) = 0.65

        [Header(Thresholds)]
        _DepthThreshold ("Depth Threshold", Range(0.0001, 0.05)) = 0.005
        _NormalThreshold ("Normal Threshold", Range(0.001, 1)) = 0.25
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

        // We output only the edge colour, then alpha-blend it over the camera colour.
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

            float RobertsCross(float samples[4])
            {
                float difference_1 = samples[1] - samples[2];
                float difference_2 = samples[0] - samples[3];
                return sqrt(difference_1 * difference_1 + difference_2 * difference_2);
            }

            float RobertsCross(float3 samples[4])
            {
                float3 difference_1 = samples[1] - samples[2];
                float3 difference_2 = samples[0] - samples[3];
                return sqrt(dot(difference_1, difference_1) + dot(difference_2, difference_2));
            }

            float3 SampleSceneNormalsRemapped(float2 uv)
            {
                return SampleSceneNormals(uv) * 0.5 + 0.5;
            }

            half4 frag(Varyings IN) : SV_TARGET
            {
                float2 uv = IN.texcoord;

                float2 texel_size = float2(1.0 / _ScreenParams.x, 1.0 / _ScreenParams.y);

                float half_width_f = floor(_OutlineThickness * 0.5);
                float half_width_c = ceil(_OutlineThickness * 0.5);

                float2 uvs[4];

                // Roberts Cross diagonal samples.
                uvs[0] = uv + texel_size * float2(half_width_f, half_width_c) * float2(-1,  1); // top left
                uvs[1] = uv + texel_size * float2(half_width_c, half_width_c) * float2( 1,  1); // top right
                uvs[2] = uv + texel_size * float2(half_width_f, half_width_f) * float2(-1, -1); // bottom left
                uvs[3] = uv + texel_size * float2(half_width_c, half_width_f) * float2( 1, -1); // bottom right

                float depth_samples[4];
                float linear_depth_samples[4];
                float3 normal_samples[4];
                float3 colour_samples[4];

                for (int i = 0; i < 4; i++)
                {
                    depth_samples[i] = SampleSceneDepth(uvs[i]);
                    linear_depth_samples[i] = Linear01Depth(depth_samples[i], _ZBufferParams);

                    normal_samples[i] = SampleSceneNormalsRemapped(uvs[i]);
                    colour_samples[i] = SampleSceneColor(uvs[i]);
                }

                float3 centre_colour = SampleSceneColor(uv);

                // ----------------------------
                // 1. OUTER EDGE: depth based
                // ----------------------------

                float edge_depth = RobertsCross(linear_depth_samples);
                edge_depth = edge_depth > _DepthThreshold ? 1.0 : 0.0;

                // Choose the nearest sampled colour so the outer edge inherits object colour,
                // not sky/plane colour.
                int nearest_index = 0;
                float nearest_depth = linear_depth_samples[0];

                for (int j = 1; j < 4; j++)
                {
                    if (linear_depth_samples[j] < nearest_depth)
                    {
                        nearest_depth = linear_depth_samples[j];
                        nearest_index = j;
                    }
                }

                float3 nearest_colour = colour_samples[nearest_index];

                // Object-relative dark outer edge.
                float3 outer_colour = nearest_colour * _OuterDarken;

                // ----------------------------
                // 2. INNER EDGE: normal based
                // ----------------------------

                float edge_normal = RobertsCross(normal_samples);
                edge_normal = edge_normal > _NormalThreshold ? 1.0 : 0.0;

                // Avoid normal highlights fighting with silhouette depth outlines.
                // Depth owns external edges. Normals should mostly handle inner creases.
                edge_normal *= (1.0 - edge_depth);

                // Object-relative bright inner edge.
                float3 inner_colour = saturate(centre_colour * (1.0 + _InnerBrighten));

                // ----------------------------
                // 3. Output priority
                // ----------------------------

                float3 final_edge_colour = 0;
                float final_alpha = 0;

                if (edge_depth > 0.5)
                {
                    final_edge_colour = outer_colour;
                    final_alpha = _OuterAlpha;
                }
                else if (edge_normal > 0.5)
                {
                    final_edge_colour = inner_colour;
                    final_alpha = _InnerAlpha;
                }

                return half4(final_edge_colour, final_alpha);
            }

            ENDHLSL
        }
    }
}