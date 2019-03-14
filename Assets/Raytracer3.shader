// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

// Fra https://docs.unity3d.com/Manual/SL-VertexFragmentShaderExamples.html
//https://msdn.microsoft.com/en-us/library/windows/desktop/bb509640(v=vs.85).aspx
//https://msdn.microsoft.com/en-us/library/windows/desktop/ff471421(v=vs.85).aspx
// rand num generator http://gamedev.stackexchange.com/questions/32681/random-number-hlsl
// http://www.reedbeta.com/blog/2013/01/12/quick-and-easy-gpu-random-numbers-in-d3d11/
// https://docs.unity3d.com/Manual/RenderDocIntegration.html
// https://docs.unity3d.com/Manual/SL-ShaderPrograms.html


Shader "Unlit/Raytracer3BlueSky"
{
	SubShader{ Pass	{
	CGPROGRAM
	#pragma vertex vert
	#pragma fragment frag

	typedef vector <float, 3> vec3;  // to get more similar code to book
	typedef vector <fixed, 3> col3;

	class ray
	{
		void make(vec3 orig, vec3 dir) { origin = orig; direction = dir; } // constructors not supported in hlsl
		vec3 point_at_parameter(float t) { return origin + t * direction; }
		vec3 origin; // access directly instead of via function
		vec3 direction;
	};

	vec3 color(ray r)
	{
		vec3 unit_direction = r.direction;
		float t = 0.5 * (unit_direction.y + 1.0);
		return (1.0 - t) * vec3(1.0, 1.0, 1.0) + t * vec3(0.5, 0.7, 1.0);
	}

	struct appdata
	{
		float4 vertex : POSITION;
		float2 uv : TEXCOORD0;
	};

	struct v2f
	{
		float2 uv : TEXCOORD0;
		float4 vertex : SV_POSITION;
	};

	v2f vert(appdata v)
	{
		v2f o;
		o.vertex = UnityObjectToClipPos(v.vertex);
		o.uv = v.uv;
		return o;
	}

	/////////////////////////////////////////////////////////////////////////////////////
	fixed4 frag(v2f i) : SV_Target
	{
		vec3 lower_left_corner = {-2, -1, -1};
		vec3 horizontal = {4, 0, 0};
		vec3 vertical = {0, 2, 0};
		vec3 origin = {0, 0, 0};

		float u = i.uv.x;
		float v = i.uv.y;

		ray r;
		r.make(origin, lower_left_corner + u * horizontal + v * vertical);
		col3 col = color(r);
		return fixed4(col,1);
	}
	////////////////////////////////////////////////////////////////////////////////////

	ENDCG
}}}


