using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;

public class PixelOnlyRendererFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class PixelSettings
    {
        [Header("Internal Pixel Resolution")]
        public int width = 640;
        public int height = 360;

        [Header("Upscale Material")]
        public Material upscaleMaterial;
    }

    public PixelSettings settings = new PixelSettings();

    private PixelOnlyPass pixelPass;

    public override void Create()
    {
        pixelPass = new PixelOnlyPass(settings)
        {
            renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing
        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (renderingData.cameraData.cameraType == CameraType.Game)
        {
            renderer.EnqueuePass(pixelPass);
        }
    }

    private class PixelOnlyPass : ScriptableRenderPass
    {
        private PixelSettings settings;

        public PixelOnlyPass(PixelSettings settings)
        {
            this.settings = settings;

            requiresIntermediateTexture = true;

            // For now we only need the camera colour.
            ConfigureInput(ScriptableRenderPassInput.Color);
        }

        private class PassData
        {
            public TextureHandle source;
            public TextureHandle destination;
            public Material material;
        }

        public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
        {
            UniversalResourceData resourceData = frameData.Get<UniversalResourceData>();
            UniversalCameraData cameraData = frameData.Get<UniversalCameraData>();

            TextureHandle cameraColor = resourceData.activeColorTexture;

            if (!cameraColor.IsValid())
                return;

            // ------------------------------------------------------------
            // 1. Copy full-resolution camera colour.
            // ------------------------------------------------------------

            TextureDesc colorCopyDesc = renderGraph.GetTextureDesc(cameraColor);
            colorCopyDesc.name = "_PixelArt_ColorCopy";
            colorCopyDesc.msaaSamples = MSAASamples.None;
            colorCopyDesc.clearBuffer = false;

            TextureHandle colorCopy = renderGraph.CreateTexture(colorCopyDesc);

            using (var builder = renderGraph.AddRasterRenderPass<PassData>("PixelArt_CopyColor", out var passData))
            {
                passData.source = cameraColor;
                passData.destination = colorCopy;

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

            // ------------------------------------------------------------
            // 2. Downsample to low resolution.
            // ------------------------------------------------------------

            TextureDesc lowResDesc = new TextureDesc(settings.width, settings.height)
            {
                name = "_PixelArt_LowResColor",
                colorFormat = cameraData.cameraTargetDescriptor.graphicsFormat,
                depthBufferBits = DepthBits.None,
                msaaSamples = MSAASamples.None,
                clearBuffer = false,
                useMipMap = false,
                filterMode = FilterMode.Point
            };

            TextureHandle lowResColor = renderGraph.CreateTexture(lowResDesc);

            using (var builder = renderGraph.AddRasterRenderPass<PassData>("PixelArt_Downsample", out var passData))
            {
                passData.source = colorCopy;
                passData.destination = lowResColor;

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

            // ------------------------------------------------------------
            // 3. Upscale low-res image back to camera target.
            // ------------------------------------------------------------

            using (var builder = renderGraph.AddRasterRenderPass<PassData>("PixelArt_Upscale", out var passData))
            {
                passData.source = lowResColor;
                passData.destination = cameraColor;
                passData.material = settings.upscaleMaterial;

                builder.UseTexture(passData.source, AccessFlags.Read);
                builder.SetRenderAttachment(passData.destination, 0, AccessFlags.Write);

                builder.SetRenderFunc((PassData data, RasterGraphContext context) =>
                {
                    if (data.material != null)
                    {
                        Blitter.BlitTexture(
                            context.cmd,
                            data.source,
                            new Vector4(1, 1, 0, 0),
                            data.material,
                            0
                        );
                    }
                    else
                    {
                        Blitter.BlitTexture(
                            context.cmd,
                            data.source,
                            new Vector4(1, 1, 0, 0),
                            0,
                            false
                        );
                    }
                });
            }
        }
    }
}