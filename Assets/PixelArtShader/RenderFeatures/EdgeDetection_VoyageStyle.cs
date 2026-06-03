using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class EdgeDetection_VoyageStyle : ScriptableRendererFeature
{
    private class EdgeDetectionPass : ScriptableRenderPass
    {
        private Material material;

        private static readonly int OutlineThicknessProperty = Shader.PropertyToID("_OutlineThickness");

        private static readonly int OuterDarkenProperty = Shader.PropertyToID("_OuterDarken");
        private static readonly int InnerBrightenProperty = Shader.PropertyToID("_InnerBrighten");

        private static readonly int OuterAlphaProperty = Shader.PropertyToID("_OuterAlpha");
        private static readonly int InnerAlphaProperty = Shader.PropertyToID("_InnerAlpha");

        private static readonly int DepthThresholdProperty = Shader.PropertyToID("_DepthThreshold");
        private static readonly int NormalThresholdProperty = Shader.PropertyToID("_NormalThreshold");

        private static readonly int DepthEdgeStrengthProperty = Shader.PropertyToID("_DepthEdgeStrength");
        private static readonly int NormalEdgeStrengthProperty = Shader.PropertyToID("_NormalEdgeStrength");

        private static readonly int NormalEdgeBiasProperty = Shader.PropertyToID("_NormalEdgeBias");
        private static readonly int DepthDirectionProperty = Shader.PropertyToID("_DepthDirection");

        public EdgeDetectionPass()
        {
            profilingSampler = new ProfilingSampler(nameof(EdgeDetectionPass));
        }

        public void Setup(ref EdgeDetectionSettings settings, ref Material edgeDetectionMaterial)
        {
            material = edgeDetectionMaterial;
            renderPassEvent = settings.renderPassEvent;

            material.SetFloat(OutlineThicknessProperty, settings.outlineThickness);

            material.SetFloat(OuterDarkenProperty, settings.outerDarken);
            material.SetFloat(InnerBrightenProperty, settings.innerBrighten);

            material.SetFloat(OuterAlphaProperty, settings.outerAlpha);
            material.SetFloat(InnerAlphaProperty, settings.innerAlpha);

            material.SetFloat(DepthThresholdProperty, settings.depthThreshold);
            material.SetFloat(NormalThresholdProperty, settings.normalThreshold);

            material.SetFloat(DepthEdgeStrengthProperty, settings.depthEdgeStrength);
            material.SetFloat(NormalEdgeStrengthProperty, settings.normalEdgeStrength);

            material.SetVector(NormalEdgeBiasProperty, settings.normalEdgeBias);
            material.SetFloat(DepthDirectionProperty, settings.depthDirection);
        }

        private class PassData { }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();

            if (!resourceData.activeColorTexture.IsValid())
                return;

            using var builder = renderGraph.AddRasterRenderPass<PassData>(
                "Voyage Style Edge Detection",
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
    public class EdgeDetectionSettings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;

        [Header("Pixel Perfect Edge Sampling")]
        [Range(1, 8)] public int outlineThickness = 1;

        [Header("Relative Edge Colour")]
        [Range(0, 1)] public float outerDarken = 0.35f;
        [Range(0, 2)] public float innerBrighten = 0.55f;

        [Header("Alpha")]
        [Range(0, 1)] public float outerAlpha = 1.0f;
        [Range(0, 1)] public float innerAlpha = 0.55f;

        [Header("Thresholds")]
        [Range(0.0001f, 0.05f)] public float depthThreshold = 0.003f;
        [Range(0.001f, 1f)] public float normalThreshold = 0.20f;

        [Header("Strength")]
        [Range(0, 2)] public float depthEdgeStrength = 1.0f;
        [Range(0, 2)] public float normalEdgeStrength = 1.0f;

        [Header("Direction / Bias")]
        [Tooltip("1 = outline around foreground objects. -1 = flip depth edge side.")]
        [Range(-1, 1)] public float depthDirection = 1.0f;

        public Vector3 normalEdgeBias = new Vector3(1, 1, 1);
    }

    [SerializeField] private EdgeDetectionSettings settings = new EdgeDetectionSettings();

    private Material edgeDetectionMaterial;
    private EdgeDetectionPass edgeDetectionPass;

    public override void Create()
    {
        edgeDetectionPass ??= new EdgeDetectionPass();
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (renderingData.cameraData.cameraType != CameraType.Game)
            return;

        if (edgeDetectionMaterial == null)
        {
            edgeDetectionMaterial = CoreUtils.CreateEngineMaterial(
                Shader.Find("Hidden/Edge Detection Voyage Style")
            );

            if (edgeDetectionMaterial == null)
            {
                Debug.LogWarning("EdgeDetection_VoyageStyle: shader could not be found.");
                return;
            }
        }

        edgeDetectionPass.ConfigureInput(
            ScriptableRenderPassInput.Depth |
            ScriptableRenderPassInput.Normal |
            ScriptableRenderPassInput.Color
        );

        edgeDetectionPass.requiresIntermediateTexture = true;
        edgeDetectionPass.Setup(ref settings, ref edgeDetectionMaterial);

        renderer.EnqueuePass(edgeDetectionPass);
    }

    protected override void Dispose(bool disposing)
    {
        edgeDetectionPass = null;
        CoreUtils.Destroy(edgeDetectionMaterial);
    }
}