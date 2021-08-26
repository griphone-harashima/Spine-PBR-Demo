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