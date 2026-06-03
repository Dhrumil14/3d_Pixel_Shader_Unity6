using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class NewShader : ScriptableRendererFeature
{
    private class NewShaderPass : ScriptableRenderPass
    {
        private Material material;

        private static readonly int OutlineThicknessProperty = Shader.PropertyToID("_OutlineThickness");

        private static readonly int OuterDarkenProperty = Shader.PropertyToID("_OuterDarken");
        private static readonly int InnerBrightenProperty = Shader.PropertyToID("_InnerBrighten");

        private static readonly int OuterAlphaProperty = Shader.PropertyToID("_OuterAlpha");
        private static readonly int InnerAlphaProperty = Shader.PropertyToID("_InnerAlpha");

        private static readonly int DepthThresholdProperty = Shader.PropertyToID("_DepthThreshold");
        private static readonly int NormalThresholdProperty = Shader.PropertyToID("_NormalThreshold");

        private static readonly int DepthStrengthProperty = Shader.PropertyToID("_DepthStrength");
        private static readonly int NormalStrengthProperty = Shader.PropertyToID("_NormalStrength");

        private static readonly int DebugModeProperty = Shader.PropertyToID("_DebugMode");

        public NewShaderPass()
        {
            profilingSampler = new ProfilingSampler(nameof(NewShaderPass));
        }

        public void Setup(ref NewShaderSettings settings, ref Material newShaderMaterial)
        {
            material = newShaderMaterial;
            renderPassEvent = settings.renderPassEvent;

            material.SetFloat(OutlineThicknessProperty, settings.outlineThickness);

            material.SetFloat(OuterDarkenProperty, settings.outerDarken);
            material.SetFloat(InnerBrightenProperty, settings.innerBrighten);

            material.SetFloat(OuterAlphaProperty, settings.outerAlpha);
            material.SetFloat(InnerAlphaProperty, settings.innerAlpha);

            material.SetFloat(DepthThresholdProperty, settings.depthThreshold);
            material.SetFloat(NormalThresholdProperty, settings.normalThreshold);

            material.SetFloat(DepthStrengthProperty, settings.depthStrength);
            material.SetFloat(NormalStrengthProperty, settings.normalStrength);

            material.SetFloat(DebugModeProperty, settings.debugMode);
        }

        private class PassData { }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();

            if (!resourceData.activeColorTexture.IsValid())
                return;

            using var builder = renderGraph.AddRasterRenderPass<PassData>(
                "New Shader Scharr Outlines",
                out _
            );

            builder.SetRenderAttachment(resourceData.activeColorTexture, 0);
            builder.UseAllGlobalTextures(true);
            builder.AllowPassCulling(false);

            builder.SetRenderFunc((PassData _, RasterGraphContext context) =>
            {
                Blitter.BlitTexture(
                    context.cmd,
                    Vector2.one,
                    material,
                    0
                );
            });
        }
    }

    [Serializable]
    public class NewShaderSettings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;

        [Header("Debug")]
        [Tooltip("0 = Final, 1 = Depth Edge, 2 = Normal Edge, 3 = Combined Mask")]
        [Range(0, 3)] public int debugMode = 0;

        [Header("Pixel Size / Thickness")]
        [Range(1, 10)] public int outlineThickness = 2;

        [Header("Relative Edge Colour")]
        [Range(0, 1)] public float outerDarken = 0.35f;
        [Range(0, 2)] public float innerBrighten = 0.55f;

        [Header("Alpha")]
        [Range(0, 1)] public float outerAlpha = 1.0f;
        [Range(0, 1)] public float innerAlpha = 0.55f;

        [Header("Thresholds")]
        [Range(0.0001f, 0.2f)] public float depthThreshold = 0.02f;
        [Range(0.0001f, 5f)] public float normalThreshold = 1.5f;

        [Header("Strength")]
        [Range(0, 3)] public float depthStrength = 1.0f;
        [Range(0, 3)] public float normalStrength = 1.0f;
    }

    [SerializeField] private NewShaderSettings settings = new NewShaderSettings();

    private Material newShaderMaterial;
    private NewShaderPass newShaderPass;

    public override void Create()
    {
        newShaderPass ??= new NewShaderPass();
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        // Game View only.
        if (renderingData.cameraData.cameraType != CameraType.Game)
            return;

        if (newShaderMaterial == null)
        {
            newShaderMaterial = CoreUtils.CreateEngineMaterial(
                Shader.Find("Hidden/NewShader")
            );

            if (newShaderMaterial == null)
            {
                Debug.LogWarning("NewShader: shader could not be found.");
                return;
            }
        }

        newShaderPass.ConfigureInput(
            ScriptableRenderPassInput.Depth |
            ScriptableRenderPassInput.Normal |
            ScriptableRenderPassInput.Color
        );

        newShaderPass.requiresIntermediateTexture = true;
        newShaderPass.Setup(ref settings, ref newShaderMaterial);

        renderer.EnqueuePass(newShaderPass);
    }

    protected override void Dispose(bool disposing)
    {
        newShaderPass = null;
        CoreUtils.Destroy(newShaderMaterial);
    }
}