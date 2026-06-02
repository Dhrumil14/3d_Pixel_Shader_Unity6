Shader "Custom/PixelArt/SharpPixelUpscale"
{
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }

        Cull Off
        ZWrite Off
        ZTest Always

        Pass
        {
            Name "Sharp Pixel Upscale"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            half4 Frag(Varyings input) : SV_Target
            {
                float2 uv = input.texcoord;

                // Size of one pixel in the low-resolution texture.
                float2 texelSize = _BlitTexture_TexelSize.xy;

                // Snap UVs to the centre of the nearest low-res texel.
                float2 snappedUV = (floor(uv / texelSize) + 0.5) * texelSize;

                half4 col = SAMPLE_TEXTURE2D_X_LOD(_BlitTexture, sampler_PointClamp, snappedUV, 0);

                return col;
            }
            ENDHLSL
        }
    }
}