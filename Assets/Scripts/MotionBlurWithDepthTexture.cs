using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class MotionBlurWithDepthTexture : PostEffectsBase
{
    public Shader motionBlurShader;
    private Material motionBlurMaterial = null;
    public Material material
    {
        get
        {
            motionBlurMaterial = CheckShaderAndCreateMaterial(motionBlurShader, motionBlurMaterial);
            return motionBlurMaterial;
        }
    }
    [Range(0.0f, 1.0f)]
    public float blurSize = 0.5f;
    private Camera myCamera;
    public Camera camera
    {
        get 
        { 
            if(myCamera == null)
            {
                myCamera = GetComponent<Camera>();
            }
            return myCamera;
        }
    }
    private Matrix4x4 previousViewProjectionMatrix;
    private void OnEnable()
    {
        camera.depthTextureMode |= DepthTextureMode.Depth;
    }
    private void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if(material != null)
        {
            material.SetFloat("_BlurSize", blurSize);

            //向着色器传入上一帧的从世界空间变换到裁剪空间的矩阵
            material.SetMatrix("_PreviousViewProjectionMatrix", previousViewProjectionMatrix);
            //计算这一帧的从世界空间变换到裁剪空间的矩阵
            Matrix4x4 currentViewProjectionMatrix = camera.projectionMatrix * camera.worldToCameraMatrix;
            //取反得到逆矩阵，即这一帧从裁剪空间变换到世界空间的矩阵
            Matrix4x4 currentViewProjectionInverseMatrix = currentViewProjectionMatrix.inverse;
            //将变换后的逆矩阵作为矩阵参数传入着色器帮助后续计算
            //原因是我们需要计算出物体在这一帧所在的世界空间的位置，然后再通过上一帧的变换矩阵求得上一帧的裁剪空间位置进而进行齐次除法求得NDC和上一帧的屏幕坐标
            //然后把当前帧减去上一帧即可获得屏幕空间上物体的速度方向，进而可以对这个方向上进行邻像素采样达到模糊效果
            material.SetMatrix("_CurrentViewProjectionInverseMatrix", currentViewProjectionInverseMatrix);
            //将这一帧从世界空间变换到裁剪空间的矩阵传给上一帧这个变量(其实是因为下一帧的时候这一帧就是上一帧了)
            previousViewProjectionMatrix = currentViewProjectionMatrix;

            Graphics.Blit(source, destination,material);
        }
        else
        {
            Graphics.Blit(source, destination);
        }
    }
}
