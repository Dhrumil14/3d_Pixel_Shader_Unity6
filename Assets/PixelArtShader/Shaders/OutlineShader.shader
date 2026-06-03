Shader "Hidden/OutlineShader"
{
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag
         
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"

            // Uniform Parameters
            float _LineDarken;
            float _CreaseBrighten;
            
            float _DepthDiffLow;
            float _DepthDiffHigh;
            float _NormalSmoothLow;
            float _NormalSmoothHigh;

            float3 _LineTint;        
            float3 _CreaseTint;      
            float _FlipPalettes;     
            float _LineOverlay;      
            float _LineAlpha;        
            float _CreaseOverlay;      
            float _CreaseAlpha;
            float _KernelRadius;     
            float _ZDeltaCutoff;     
            float _AngleZCutoff;     
            float _AngleZScale;      

            // Legacy values preserved for properties structure
            float _ConvexCutoff;
            float _CreaseFeather;
            float _ConcaveCutoff;
            float _ConcaveZCutoff;

            // Reconstruct position in view-space.
            float3 ReconstructViewPos(float2 uv, float rawDepth)
            {
                float4 clipPos = float4(uv * 2.0 - 1.0, rawDepth, 1.0);
                #if UNITY_UV_STARTS_AT_TOP
                    clipPos.y = -clipPos.y;
                #endif
                
                float4 viewPos = mul(UNITY_MATRIX_I_P, clipPos);
                return viewPos.xyz / viewPos.w;
            }

            half4 frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;
                float2 step_uv = _BlitTexture_TexelSize.xy * _KernelRadius;

                float3 vp[9];
                float3 vn[9];
                float2 sampleUVs[9];

                // Extract 3x3 grid.
                [unroll]
                for (int k = 0; k < 9; k++)
                {
                    float2 off = float2(k % 3 - 1, k / 3 - 1);
                    sampleUVs[k] = uv + off * step_uv;
                    
                    float rawDepth = SampleSceneDepth(sampleUVs[k]);
                    vp[k] = ReconstructViewPos(sampleUVs[k], rawDepth);
                    
                    float3 normalWS = SampleSceneNormals(sampleUVs[k]);
                    vn[k] = mul((float3x3)UNITY_MATRIX_V, normalWS); 
                }

                // Angular adaptation threshold for silhouette.
                float facing = 1.0 - vn[4].z;
                float t01 = saturate((facing - _AngleZCutoff) / (1.0 - _AngleZCutoff));
                float z_thresh = _ZDeltaCutoff * (t01 * _AngleZScale + 1.0);

                // Crease detection.
                int cardinals[4] = {1, 3, 5, 7};
                float depthDifference = 0.0;
                float invDepthDifference = 0.0;
                [unroll]
                for (int i = 0; i < 4; i++) {
                    int idx = cardinals[i];
                    depthDifference += clamp(vp[idx].z - vp[4].z, 0.0, 1.0);
                    invDepthDifference += clamp(vp[4].z - vp[idx].z, 0.0, 1.0);
                }
                
                invDepthDifference = clamp(invDepthDifference, 0.0, 1.0);
                invDepthDifference = clamp(smoothstep(0.9, 0.9, invDepthDifference) * 10.0, 0.0, 1.0);
                depthDifference = smoothstep(_DepthDiffLow, _DepthDiffHigh, depthDifference);

                // Directional contrast between cardinal opposites.
                float d0 = 1.0 - dot(vn[4], vn[cardinals[0]]);
                float d1 = 1.0 - dot(vn[4], vn[cardinals[1]]);
                float d2 = 1.0 - dot(vn[4], vn[cardinals[2]]);
                float d3 = 1.0 - dot(vn[4], vn[cardinals[3]]);
                
                float contrast0 = abs(d0 - d3);
                float contrast1 = abs(d1 - d2);
                
                float normalDifference = max(contrast0, contrast1);
                
                normalDifference = smoothstep(_NormalSmoothLow, _NormalSmoothHigh, normalDifference);
                float crease_weight = saturate(normalDifference - invDepthDifference);

                // Silhouette detection.
                bool has_line = false;
                int closest_idx = 4;
                float max_z = vp[4].z; 
                int neighbors[8] = {0, 1, 2, 3, 5, 6, 7, 8}; 
                [unroll]
                for (int s = 0; s < 8; s++) 
                {
                    int idx = neighbors[s];
                    if ((vp[idx].z - vp[4].z) > z_thresh)
                    {
                        has_line = true;
                    }
                    
                    if (vp[idx].z > max_z)
                    {
                        max_z = vp[idx].z;
                        closest_idx = idx;
                    }
                }

                // FIX: Grab the underlying scene color to preserve the background
                float3 center_color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, uv).rgb;
                float3 result = center_color;

                if (has_line)
                {
                    // Darken the color of the closest pixel for the silhouette.
                    float3 closest_color = SAMPLE_TEXTURE2D(_BlitTexture, sampler_LinearClamp, sampleUVs[closest_idx]).rgb;
                    
                    // Fallback to 0.4 default if C# didn't set _LineDarken
                    float darken_factor = (_LineDarken > 0.0) ? _LineDarken : 0.4;
                    result = closest_color * darken_factor;
                }
                else if (crease_weight > 0.0)
                {
                    // Brighten the center color for the crease.
                    // Fallback to 0.3 default if C# didn't set _CreaseBrighten
                    float brighten_factor = (_CreaseBrighten > 0.0) ? _CreaseBrighten : 0.3;
                    result = center_color * (1.0 + brighten_factor);
                }

                // Return full scene data with 1.0 alpha to avoid losing background data
                return half4(result, 1.0);
            }
            ENDHLSL
        }
    }
}