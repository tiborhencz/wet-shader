#ifndef UNITY_STANDARD_SHADOW_INCLUDED
#define UNITY_STANDARD_SHADOW_INCLUDED

// NOTE: had to split shadow functions into separate file,
// otherwise compiler gives trouble with LIGHTING_COORDS macro (in UnityStandardCore.cginc)


#include "UnityCG.cginc"
#include "UnityShaderVariables.cginc"
#include "UnityInstancing.cginc"
#include "UnityStandardConfig.cginc"
#include "UnityStandardUtils.cginc"

// Do dithering for alpha blended shadows on SM3+/desktop;
// on lesser systems do simple alpha-tested shadows
#if defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON)
	#if !((SHADER_TARGET < 30) || defined (SHADER_API_MOBILE) || defined(SHADER_API_GLES) || defined(SHADER_API_D3D11_9X) || defined (SHADER_API_PSP2))
	#define UNITY_STANDARD_USE_DITHER_MASK 1
	#endif
#endif

// Need to output UVs in shadow caster, since we need to sample texture and do clip/dithering based on it
#if defined(_ALPHATEST_ON) || defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON)
#define UNITY_STANDARD_USE_SHADOW_UVS 1
#endif

// Has a non-empty shadow caster output struct (it's an error to have empty structs on some platforms...)
#if !defined(V2F_SHADOW_CASTER_NOPOS_IS_EMPTY) || defined(UNITY_STANDARD_USE_SHADOW_UVS)
#define UNITY_STANDARD_USE_SHADOW_OUTPUT_STRUCT 1
#endif


half4		_Color;
half		_Cutoff;
sampler2D	_MainTex;
float4		_MainTex_ST;
#ifdef UNITY_STANDARD_USE_DITHER_MASK
sampler3D	_DitherMaskLOD;
#endif

// Handle PremultipliedAlpha from Fade or Transparent shading mode
half4		_SpecColor;
half		_Metallic;
#ifdef _SPECGLOSSMAP
sampler2D	_SpecGlossMap;
#endif
#ifdef _METALLICGLOSSMAP
sampler2D	_MetallicGlossMap;
#endif

half MetallicSetup_ShadowGetOneMinusReflectivity(half2 uv)
{
	half metallicity = _Metallic;
	#ifdef _METALLICGLOSSMAP
		metallicity = tex2D(_MetallicGlossMap, uv).r;
	#endif
	return OneMinusReflectivityFromMetallic(metallicity);
}

half SpecularSetup_ShadowGetOneMinusReflectivity(half2 uv)
{
	half3 specColor = _SpecColor.rgb;
	#ifdef _SPECGLOSSMAP
		specColor = tex2D(_SpecGlossMap, uv).rgb;
	#endif
	return (1 - SpecularStrength(specColor));
}

// SHADOW_ONEMINUSREFLECTIVITY(): workaround to get one minus reflectivity based on UNITY_SETUP_BRDF_INPUT
#define SHADOW_JOIN2(a, b) a##b
#define SHADOW_JOIN(a, b) SHADOW_JOIN2(a,b)
#define SHADOW_ONEMINUSREFLECTIVITY SHADOW_JOIN(UNITY_SETUP_BRDF_INPUT, _ShadowGetOneMinusReflectivity)

struct VertexInput
{
	float4 vertex	: POSITION;
	float3 normal	: NORMAL;
	float2 uv0		: TEXCOORD0;
	UNITY_INSTANCE_ID
};

#ifdef UNITY_STANDARD_USE_SHADOW_OUTPUT_STRUCT
struct VertexOutputShadowCaster
{
	V2F_SHADOW_CASTER_NOPOS
	#if defined(UNITY_STANDARD_USE_SHADOW_UVS)
		float2 tex : TEXCOORD1;
	#endif
};
#endif


// We have to do these dances of outputting SV_POSITION separately from the vertex shader,
// and inputting VPOS in the pixel shader, since they both map to "POSITION" semantic on
// some platforms, and then things don't go well.


void vertShadowCaster (VertexInput v,
	#ifdef UNITY_STANDARD_USE_SHADOW_OUTPUT_STRUCT
	out VertexOutputShadowCaster o,
	#endif
	out float4 opos : SV_POSITION)
{
	UNITY_SETUP_INSTANCE_ID(v);
	TRANSFER_SHADOW_CASTER_NOPOS(o,opos)
	#if defined(UNITY_STANDARD_USE_SHADOW_UVS)
		o.tex = TRANSFORM_TEX(v.uv0, _MainTex);
	#endif
}

half4 fragShadowCaster (
	#ifdef UNITY_STANDARD_USE_SHADOW_OUTPUT_STRUCT
	VertexOutputShadowCaster i
	#endif
	#ifdef UNITY_STANDARD_USE_DITHER_MASK
	, UNITY_VPOS_TYPE vpos : VPOS
	#endif
	) : SV_Target
{
	#if defined(UNITY_STANDARD_USE_SHADOW_UVS)
		half alpha = tex2D(_MainTex, i.tex).a * _Color.a;
		#if defined(_ALPHATEST_ON)
			clip (alpha - _Cutoff);
		#endif
		#if defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON)
			#if defined(_ALPHAPREMULTIPLY_ON)
				half outModifiedAlpha;
				PreMultiplyAlpha(half3(0, 0, 0), alpha, SHADOW_ONEMINUSREFLECTIVITY(i.tex), outModifiedAlpha);
				alpha = outModifiedAlpha;
			#endif
			#if defined(UNITY_STANDARD_USE_DITHER_MASK)
				// Use dither mask for alpha blended shadows, based on pixel position xy
				// and alpha level. Our dither texture is 4x4x16.
				half alphaRef = tex3D(_DitherMaskLOD, float3(vpos.xy*0.25,alpha*0.9375)).a;
				clip (alphaRef - 0.01);
			#else
				clip (alpha - _Cutoff);
			#endif
		#endif
	#endif // #if defined(UNITY_STANDARD_USE_SHADOW_UVS)

	SHADOW_CASTER_FRAGMENT(i)
}			

#endif // UNITY_STANDARD_SHADOW_INCLUDED
