Shader "Motion Blur With Depth Texture"
{
    Properties
    {
        _MainTex("Base (RGB)", 2D) = "white" {}
        //模糊系数
        _BlurSize("Blur Size", float) = 1.0
    }
    SubShader
    {
        CGINCLUDE
        #include "UnityCG.cginc"

        //主纹理
        sampler2D _MainTex;
        //主纹理的纹素大小
        half4 _MainTex_TexelSize;
        //深度纹理，由unity传递
        sampler2D _CameraDepthTexture;
        //从裁剪空间变换到世界空间的矩阵
        float4x4 _CurrentViewProjectionInverseMatrix;
        //世界空间变换到裁剪空间的矩阵
        float4x4 _PreviousViewProjectionMatrix;
        //模糊系数
        half _BlurSize;

        struct v2f
        {
            float4 pos : SV_POSITION;
            half2 uv : TEXCOORD0;
            half2 uv_depth : TEXCOORD1;
        };

        v2f vert(appdata_img v)
        {
            v2f o;
            o.pos = UnityObjectToClipPos(v.vertex);
            o.uv = v.texcoord;
            o.uv_depth = v.texcoord;
            //同时处理多张纹理，需要注意平台差异，若y方向纹素为负数，则说明图像翻转，需要手动调整
            #if UNITY_UV_STARTS_AT_TOP
                if(_MainTex_TexelSize.y < 0)
                {
                    o.uv_depth.y = 1 - o.uv_depth.y;
                }
            #endif
            return o;
        }
        fixed4 frag(v2f i) : SV_TARGET
        {
            float d = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture,i.uv_depth);
            //DirectX   [0,1]      x,y,d都在[0,1]，因此DirectX下不需要映射，因为NDC也是[0,1]
            float4 H = float4(i.uv.x, i.uv.y, d, 1);
            //OpenGL    [-1,1]     x,y,d都在[0,1]，而NDC为[-1,1]，因此需要映射
            //float4 H = float4(i.uv.x * 2 - 1, i.uv.y * 2 - 1, d * 2 - 1, 1);

            //第一版理解(思路没问题，但可以不这样)
            //其实这个地方H应该先乘以Wclip进行反向齐次除法的，但wclip在齐次除法后已经丢失(Wclip指裁剪空间下的W分量)
            //后续理论上要通过屏幕空间中两个坐标位置相减，但实际上因为没办法求得worldPos的真实值(丢失Wclip)
            //因此在后续利用这个worldPos反向计算上一帧的屏幕空间中的值的时候完全可以取巧，即都不跟Wclip挂钩
            //其可行性是因为就算我们不乘以Wclip，也可以把他当做Wclip从向量中提取出来了,下文要求的速度完全可以使用相对速度来完成模糊效果
            //                                               |x|
            // _CurrentViewProjectionInverseMatrix  ·   Wclip|y|   xyz为NDC中的坐标，w分量其实是因为齐次除法除以了Wclip变为了1，事实上我们这里设置也是它为1
            //                                               |z|
            //                                               |1|
            //理论上：float4 D = mul(_CurrentViewProjectionInverseMatrix, H * Wclip);
            //        float4 worldPos = D;
            //实际上：float4 D = mul(_CurrentViewProjectionInverseMatrix, H);
            //        float4 worldPos = D;        
            //第一版原因如上↑

            //第二版原因如下↓
            //勘误：我原本以为Wclip已经丢失没办法计算，没想到今天推导矩阵的时候发现Wclip可以逆向推导出来，这时候它与D的关系为：Wclip = 1 / D.w
            //其本质是因为视角空间，也就是观察空间下W分量为1，因此我们经过float4 D = mul(_CurrentViewProjectionInverseMatrix, H)计算出来的
            //D的值其实为1/Wclip,因此移项后我们就可以发现可以得出Wclip的值进行计算，即D/D.w,其实就等于D * Wclip， 

            float4 D = mul(_CurrentViewProjectionInverseMatrix, H);
            float4 worldPos = D / D.w;
            
            //这里的Pos是NDC空间中的，这里的W是原本保留的Wclip，除以W以后就无法保留了，这里因为上述原因，因此我们直接没有必要进行W齐次除法
            float4 currentPos = H;
            float4 previousPos = mul(_PreviousViewProjectionMatrix, worldPos);
            //previousPos /= previousPos.w;   第一版这里舍弃  
            //第二版这里修改原因如上
            previousPos /= previousPos.w;
            

            //通过这一帧减去上一帧的位置变化得到NDC中的速度，但这里NDC和屏幕空间其实已经是一次线性映射了，因此用NDC来计算相对速度也没什么问题
            float2 velocity = (currentPos.xy - previousPos.xy) / 2.0f;
            //速度大小会影响uv偏移量大小，模糊系数用来调整模糊程度，得到镜头移动快慢下不同的模糊混合效果
            float2 uv = i.uv;
            float4 color = tex2D(_MainTex,uv);
            uv += velocity * _BlurSize;
            //每移动一次就要将颜色叠加实现残影效果，每循环一次就要偏移uv获得上一帧的像素用来叠加
            for(int it = 1;it < 3;it++, uv += velocity * _BlurSize)
            {
                float4 currentColor = tex2D(_MainTex,uv);
                color += currentColor;
            }
            //均和叠加多个颜色渲染的效果，除以的值需要和总的uv偏移次数对齐，因为uv偏移次数就是叠加的次数，为了避免亮度过高需要均和
            color /= 3;
            return fixed4(color.rgb, 1.0);
        }
        ENDCG
        pass
        {
            ZTest Always
            Cull Off 
            ZWrite Off 
            CGPROGRAM 
            #pragma vertex vert 
            #pragma fragment frag
            ENDCG
        }
    }
}
