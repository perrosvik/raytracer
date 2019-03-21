// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

// Fra https://docs.unity3d.com/Manual/SL-VertexFragmentShaderExamples.html
//https://msdn.microsoft.com/en-us/library/windows/desktop/bb509640(v=vs.85).aspx
//https://msdn.microsoft.com/en-us/library/windows/desktop/ff471421(v=vs.85).aspx
// rand num generator http://gamedev.stackexchange.com/questions/32681/random-number-hlsl
// http://www.reedbeta.com/blog/2013/01/12/quick-and-easy-gpu-random-numbers-in-d3d11/
// https://docs.unity3d.com/Manual/RenderDocIntegration.html
// https://docs.unity3d.com/Manual/SL-ShaderPrograms.html


Shader "Unlit/Raytracer7"
{
	SubShader{ Pass	{
	CGPROGRAM
	#pragma vertex vert
	#pragma fragment frag

	typedef vector <float, 3> vec3;  // to get more similar code to book
	typedef vector <fixed, 3> col3;

	static const uint MAXIMUM_DEPTH = 25;
	static const uint NUMBER_OF_SAMPLES = 20;

	static float2 uv;

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

	struct hit_record {
		float t;
		vec3 p;
		vec3 normal;
	};

	struct ray
	{
		vec3 origin;
		vec3 direction;
		static ray from(vec3 orig, vec3 dir)
		{
			ray r;
			r.origin = orig;
			r.direction = dir;
			return r;
		}
		vec3 point_at_parameter(float t)
		{
			return origin + t * direction;
		}
	};

	struct sphere
	{
		vec3 center;
		float radius;

		static sphere from(vec3 co, float rad)
		{
			sphere s;
			s.center = co,
			s.radius = rad;
			return s;
		}

		bool hit(ray r, float tmin, float tmax, out hit_record rec) {
			vec3 oc = r.origin - center;
			float a = dot(r.direction, r.direction);
			float b = dot(oc, r.direction);
			float c = dot(oc, oc) - radius * radius;
			float discriminant = b * b - a * c;
			if (discriminant > 0) {
				float temp = (-b - sqrt(b*b - a * c)) / a;
				if (temp < tmax && temp > tmin) {
					rec.t = temp;
					rec.p = r.point_at_parameter(rec.t);
					rec.normal = (rec.p - center) / radius;
					return true;
				}
				temp = (-b + sqrt(b * b - a * c)) / a;
				if (temp < tmax  && temp > tmin) {
					rec.t = temp;
					rec.p = r.point_at_parameter(rec.t);
					rec.normal = (rec.p - center) / radius;
					return true;
				}
			}
			return false;
		}
	};

	static const uint NUMBER_OF_SPHERES = 2;
	static const sphere WORLD[NUMBER_OF_SPHERES] = {
		{ vec3(0.0, 0.0, -1.0), 0.5 },
		{ vec3(0.0, -100.5, -1.0), 100.0 }
	};

	struct camera
	{
		vec3 origin;
		vec3 lower_left_corner;
		vec3 horizontal;
		vec3 vertical;

		static camera from()
		{
			camera cam;
			cam.origin = vec3(0.0, 0.0, 0.0);
			cam.lower_left_corner = vec3(-2.0, -1.0, -1.0);
			cam.horizontal = vec3(4.0, 0.0, 0.0);
			cam.vertical = vec3(0.0, 2.0, 0.0);
			return cam;
		}

		ray getRay(float u, float v)
		{
			return ray::from(origin, lower_left_corner + u * horizontal + v * vertical - origin);
		}
	};

	static float rand_seed = 12.0;

	float random_number(in float2 uv)
	{
		float2 noise = (frac(sin(dot(uv,float2(12.9898, 78.233)*2.0)) * 43758.5453));	
		rand_seed += 0.21342;
		return abs(noise.x + noise.y) * 0.5;
	};

	vec3 random_in_unit_sphere() {
		vec3 p;
		do {
			p = 2.0 * vec3(random_number(uv.x+rand_seed * uv.y+rand_seed), random_number(uv.x+rand_seed * 2 * uv.y+rand_seed * 2), random_number(pow(uv.x,2) + rand_seed * pow(uv.y,2)+rand_seed)) - vec3(1.0, 1.0, 1.0);
		} while (dot(p, p) >= 1.0);
		return p;
	}



	bool hit_world(ray r, float tmin, float tmax, out hit_record rec) {
		hit_record temp_rec;
		bool hit_anything = false;
		float closest = tmax;

		for (uint i = 0; i < NUMBER_OF_SPHERES; i++) {
			sphere s = WORLD[i];
			if (s.hit(r, tmin, closest, temp_rec)) {
				hit_anything = true;
				closest = temp_rec.t;
				rec = temp_rec;
			}
		}

		return hit_anything;
	}

	vec3 color(ray r)
	{
		hit_record rec;
		vec3 accumColor = vec3(1.0, 1.0, 1.0);
		uint i = 0;
		while((hit_world(r, 0.001, 100000.0, rec)) && i <= MAXIMUM_DEPTH)
		{
			vec3 target = rec.p + rec.normal + random_in_unit_sphere();
			r = ray::from(rec.p, target - rec.p);
			accumColor *= 0.5;
			i += 1;
		}
		
		if (i == MAXIMUM_DEPTH)
		{
			return vec3(0.0, 0.0, 0.0);
		}
		else {
			vec3 unit_direction = normalize(r.direction);
			float t = 0.5 * (unit_direction.y + 1.0);
			return accumColor * (lerp(vec3(1.0, 1.0, 1.0), vec3(0.5, 0.7, 1.0), t));
		}
	};

	/////////////////////////////////////////////////////////////////////////////////////
	fixed4 frag(v2f i) : SV_Target
	{
		vec3 lower_left_corner = {-2, -1, -1};
		vec3 horizontal = {4, 0, 0};
		vec3 vertical = {0, 2, 0};
		vec3 origin = {0, 0, 0};

		float u = i.uv.x;
		float v = i.uv.y;
		uv = float2(u, v);

		col3 col = col3(0.0,0.0,0.0);
		camera cam = camera::from();

		for (uint i = 0; i < NUMBER_OF_SAMPLES; i++) {
			ray r = cam.getRay(u, v);
			col += col3(color(r));
		}
		col /= NUMBER_OF_SAMPLES;
		col = sqrt(col); // gamma correction
		return fixed4(col,1);
	}
	////////////////////////////////////////////////////////////////////////////////////
	ENDCG
} }}


