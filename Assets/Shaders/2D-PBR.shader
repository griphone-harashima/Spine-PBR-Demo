Shader "Sprite/2D-PBR"
{
    Properties
    {
        [PerRendererData] _MainTex ("Texture", 2D) = "white" {}
        [PerRendererData] _NormalMap ("Normal Map", 2D) = "bump" {}
        _Color ("Color", COLOR) = (1, 1, 1, 1)
        _Metallic("Metallic", Range(0.0, 1.0)) = 0.0
        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5
        _AmbientColor ("Ambient Color", Color) = (0.5,0.5,0.5,1)
    }
    
    HLSLINCLUDE
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
    // #include "Custom.cginc"

    struct Attributes
    {
        float4 positionOS       : POSITION;
        float2 uv               : TEXCOORD0;
        float4 color            : COLOR;
        half3 normal : NORMAL;
        float4 tangent : TANGENT;
    };

    struct Varyings
    {
        float2 uv        : TEXCOORD0;
        float4 color   : COLOR;
        float4 vertex : SV_POSITION;
        half3 normalWS : TEXCOORD1;
        half3 toEye : TEXCOORD2;
        float4 tangent  : TANGENT;
        float3 binormal : TEXCOORD3;
    };

    half4 _Color;
    float _Metallic;
    float _Smoothness;
    float3 _AmbientColor;

    TEXTURE2D(_MainTex);
    SAMPLER(sampler_MainTex);
    TEXTURE2D(_NormalMap);
    SAMPLER(sampler_NormalMap);

    // 誘電体の反射率（F0）は4%とする
    #define _DielectricF0 0.04

    inline half Fd_Burley(half ndotv, half ndotl, half ldoth, half roughness)
    {
        half fd90 = 0.5 + 2 * ldoth * ldoth * roughness;
        half lightScatter = (1 + (fd90 - 1) * pow(1 - ndotl, 5));
        half viewScatter = (1 + (fd90 - 1) * pow(1 - ndotv, 5));

        half diffuse = lightScatter * viewScatter;
        // 本来はこのDiffuseをπで割るべきだけどUnityではレガシーなライティングとの互換性を保つため割らない
        //diffuse /= PI;
        return diffuse;
    }

    half3 CalcDisneyDiffuse(half metallic, half roughness, float3 normal, float3 viewDir, float3 lightDir, float3 lightColor)
    {
        float3 halfDir = normalize(lightDir + viewDir);
        half ndotv = abs(dot(normal, viewDir));
        float ndotl = max(0, dot(normal, lightDir));
        half ldoth = max(0, dot(lightDir, halfDir));
        half reflectivity = lerp(_DielectricF0, 1, metallic);

        half diffuseTerm = Fd_Burley(ndotv, ndotl, ldoth, roughness) * ndotl;
        half3 diffuse = (1 - reflectivity) * lightColor * diffuseTerm;

        return diffuse;
    }

    inline float V_SmithGGXCorrelated(float ndotl, float ndotv, float alpha)
    {
        float lambdaV = ndotl * (ndotv * (1 - alpha) + alpha);
        float lambdaL = ndotv * (ndotl * (1 - alpha) + alpha);

        return 0.5f / (lambdaV + lambdaL + 0.0001);
    }

    inline half D_GGX(half roughness, half ndoth, half3 normal, half3 halfDir) {
        half3 ncrossh = cross(normal, halfDir);
        half a = ndoth * roughness;
        half k = roughness / (dot(ncrossh, ncrossh) + a * a);
        half d = k * k * (1 / PI);
        return min(d, 65504.0h);
    }

    inline half3 F_Schlick(half3 f0, half cos)
    {
        return f0 + (1 - f0) * pow(1 - cos, 5);
    }

    float3 CakcCookTorranceSpecular(half3 albedo, half metallic, half roughness, float3 normal, float3 viewDir, float3 lightDir, float3 lightColor)
    {
        float3 halfDir = normalize(lightDir + viewDir);
        half ndotv = abs(dot(normal, viewDir));
        float ndotl = max(0, dot(normal, lightDir));
        half ldoth = max(0, dot(lightDir, halfDir));
        half3 f0 = lerp(_DielectricF0, albedo, metallic);

        float alpha = roughness * roughness;
        float V = V_SmithGGXCorrelated(ndotl, ndotv, alpha);
        float D = D_GGX(roughness, ndotv, normal, halfDir);
        float3 F = F_Schlick(f0, ldoth); // マイクロファセットベースのスペキュラBRDFではcosはldothが使われる
        float3 specular = V * D * F * ndotl * lightColor;
        // 本来はSpecularにπを掛けるべきではないが、Unityではレガシーなライティングとの互換性を保つため、Diffuseを割らずにSpecularにPIを掛ける
        specular *= PI;
        specular = max(0, specular);

        return specular;
    }

    Varyings vert(Attributes input)
    {
        Varyings output = (Varyings)0;

        VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
        output.vertex = vertexInput.positionCS;
        output.color = input.color * _Color;
        output.uv = input.uv;

        output.normalWS = normalize(TransformObjectToWorldNormal(input.normal));
        float3 positionWS = TransformObjectToWorld(input.positionOS);
        output.toEye = normalize(GetWorldSpaceViewDir(positionWS));

        output.tangent = input.tangent;
        output.tangent.xyz = normalize(TransformObjectToWorldDir(input.tangent.xyz));
        // binormalはtangentのwとunity_WorldTransformParams.wを掛ける（Unityの決まり）
        output.binormal = normalize(cross(input.normal, input.tangent.xyz) * input.tangent.w * unity_WorldTransformParams.w);

        return output;
    }

    half4 frag(Varyings input) : SV_Target
    {
        float4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv);
        color *= input.color;
        color.rgb *= color.a;

        // ノーマルマップから法線情報を取得する
        float3 localNormal = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, input.uv));
        input.normalWS = input.tangent * localNormal.x + input.binormal * localNormal.y + input.normalWS * localNormal.z;

        Light light = GetMainLight();
        half roughness = 1 - _Smoothness;

        uint pixelLightCount = GetAdditionalLightsCount();
        half3 totalDiffPoint;
        float3 totalSpecPoint;
        for(uint lightindex = 0u; lightindex < pixelLightCount; ++lightindex)
        {
            Light light = GetAdditionalLight(lightindex, input.normalWS);
            half3 diffPoint = CalcDisneyDiffuse(_Metallic, roughness, input.normalWS, input.toEye, light.direction, light.color);
            float3 specPoint = CakcCookTorranceSpecular(color.rgb, _Metallic, roughness, input.normalWS, input.toEye, light.direction, light.color);
            totalDiffPoint += diffPoint;
            totalSpecPoint += specPoint;
        }

        // PBR拡散反射光
        half3 diffuse = CalcDisneyDiffuse(_Metallic, roughness, input.normalWS, input.toEye, light.direction, light.color);
        color.rgb *= diffuse + totalDiffPoint + _AmbientColor;

        // PBR鏡面反射光
        float3 specular = CakcCookTorranceSpecular(color.rgb, _Metallic, roughness, input.normalWS, input.toEye, light.direction, light.color);
        color.rgb += specular + totalSpecPoint;

        return color;
    }
    ENDHLSL
    
    SubShader
    {
        Tags
        { 
			"Queue"="Transparent" 
			"IgnoreProjector"="True" 
			"RenderType"="Transparent" 
			"PreviewType"="Plane"
			"CanUseSpriteAtlas"="True"
		}
        LOD 100
        
        ZWrite Off
        //ZTest Always
        Cull Off//Back
        Lighting Off

        Pass
        {
            Tags { "LightMode" = "SRPDefaultUnlit" "RenderPipeline" = "UniversalPipeline" }
            
            Blend One OneMinusSrcAlpha
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            ENDHLSL
        }
        Pass
        {
            Name "ShadowCaster"
            Tags {"LightMode" = "ShadowCaster"}
            ZWrite On
            ZTest LEqual
            Cull off
            
            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }
    }
}
