Shader "Custom/PixelArt/ToonLit"
{
    Properties
    {
        _BaseMap ("Base Texture", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)

        _Steps ("Lighting Steps", Range(2, 8)) = 3
        _AmbientStrength ("Ambient Strength", Range(0, 1)) = 0.25
        _ShadowStrength ("Shadow Strength", Range(0, 1)) = 0.65

        _SpecularStrength ("Specular Strength", Range(0, 1)) = 0.15
        _SpecularSize ("Specular Size", Range(8, 128)) = 32
        _SpecularSteps ("Specular Steps", Range(1, 4)) = 2
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }

        Pass
        {
            Name "ToonLit"
            Tags { "LightMode" = "UniversalForward" }

            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM

            #pragma vertex Vert
            #pragma fragment Frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;

                half _Steps;
                half _AmbientStrength;
                half _ShadowStrength;

                half _SpecularStrength;
                half _SpecularSize;
                half _SpecularSteps;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float2 uv : TEXCOORD2;
                float4 shadowCoord : TEXCOORD3;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;

                VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS);

                output.positionCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;
                output.normalWS = normalize(normalInputs.normalWS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.shadowCoord = TransformWorldToShadowCoord(output.positionWS);

                return output;
            }

            half SteppedValue(half value, half steps)
            {
                steps = max(2.0h, steps);
                return floor(value * steps) / (steps - 1.0h);
            }

            half4 Frag(Varyings input) : SV_Target
            {
                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half3 baseColor = tex.rgb * _BaseColor.rgb;

                half3 normalWS = normalize(input.normalWS);

                Light mainLight = GetMainLight(input.shadowCoord);

                half3 lightDir = normalize(mainLight.direction);
                half3 viewDir = normalize(GetWorldSpaceViewDir(input.positionWS));

                // Basic diffuse lighting.
                half ndotl = saturate(dot(normalWS, lightDir));

                // Include shadow attenuation.
                half shadow = mainLight.shadowAttenuation;
                half shadowedLight = lerp(ndotl * _ShadowStrength, ndotl, shadow);

                // Stepped toon lighting.
                half steppedDiffuse = SteppedValue(shadowedLight, _Steps);

                // Keep some ambient brightness so shadows are not pure black.
                half finalLight = max(_AmbientStrength, steppedDiffuse);

                // Simple stepped specular highlight.
                half3 halfDir = normalize(lightDir + viewDir);
                half spec = pow(saturate(dot(normalWS, halfDir)), _SpecularSize);
                spec = SteppedValue(spec, _SpecularSteps) * _SpecularStrength;

                half3 finalColor = baseColor * finalLight * mainLight.color;
                finalColor += spec * mainLight.color;

                return half4(finalColor, tex.a * _BaseColor.a);
            }

            ENDHLSL
        }

                Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM

            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;

                half _Steps;
                half _AmbientStrength;
                half _ShadowStrength;

                half _SpecularStrength;
                half _SpecularSize;
                half _SpecularSteps;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            float3 _LightDirection;
            float3 _LightPosition;

            float4 GetShadowPositionHClip(Attributes input)
            {
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);

                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDirectionWS = _LightDirection;
                #endif

                float4 positionCS = TransformWorldToHClip(
                    ApplyShadowBias(positionWS, normalWS, lightDirectionWS)
                );

                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif

                return positionCS;
            }

            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output;
                output.positionCS = GetShadowPositionHClip(input);
                return output;
            }

            half4 ShadowPassFragment(Varyings input) : SV_TARGET
            {
                return 0;
            }

            ENDHLSL
        }
    }

    FallBack Off
}