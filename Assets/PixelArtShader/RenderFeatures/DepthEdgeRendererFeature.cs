using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class DepthEdgeRendererFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class EdgeSettings
    {
        public Material edgeMaterial;
    }

    public EdgeSettings settings = new EdgeSettings();

    private DepthEdgePass depthEdgePass;

    public override void Create()
    {
        depthEdgePass = new DepthEdgePass(settings)
        {
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing
        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (renderingData.cameraData.cameraType == CameraType.Game)
        {
            renderer.EnqueuePass(depthEdgePass);
        }
    }

    private class DepthEdgePass : ScriptableRenderPass
    {
        private EdgeSettings settings;

        public DepthEdgePass(EdgeSettings settings)
        {
            this.settings = settings;

            requiresIntermediateTexture = true;
            ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal); ;
        }

        private class PassData
        {
            public TextureHandle source;
            public TextureHandle destination;
            public Material material;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            if (settings.edgeMaterial == null)
                return;

            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
            TextureHandle cameraColor = resourceData.activeColorTexture;

            if (!cameraColor.IsValid())
                return;

            TextureDesc tempDesc = renderGraph.GetTextureDesc(cameraColor);
            tempDesc.name = "_PixelArt_DepthEdgeTemp";
            tempDesc.clearBuffer = false;

            TextureHandle tempTexture = renderGraph.CreateTexture(tempDesc);

            // Pass 1: apply depth edge material into temp texture
            using (var builder = renderGraph.AddRasterRenderPass<PassData>("PixelArt_DepthEdge", out var passData))
            {
                passData.source = cameraColor;
                passData.destination = tempTexture;
                passData.material = settings.edgeMaterial;

                builder.UseTexture(passData.source, AccessFlags.Read);
                builder.SetRenderAttachment(passData.destination, 0, AccessFlags.Write);

                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    Blitter.BlitTexture(
                        context.cmd,
                        data.source,
                        new Vector4(1, 1, 0, 0),
                        data.material,
                        0
                    );
                });
            }

            // Pass 2: copy temp texture back to camera color
            using (var builder = renderGraph.AddRasterRenderPass<PassData>("PixelArt_DepthEdge_CopyBack", out var passData))
            {
                passData.source = tempTexture;
                passData.destination = cameraColor;

                builder.UseTexture(passData.source, AccessFlags.Read);
                builder.SetRenderAttachment(passData.destination, 0, AccessFlags.Write);

                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    Blitter.BlitTexture(
                        context.cmd,
                        data.source,
                        new Vector4(1, 1, 0, 0),
                        0,
                        false
                    );
                });
            }
        }
    }
}