// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

// Fra https://docs.unity3d.com/Manual/SL-VertexFragmentShaderExamples.html
//https://msdn.microsoft.com/en-us/library/windows/desktop/bb509640(v=vs.85).aspx
//https://msdn.microsoft.com/en-us/library/windows/desktop/ff471421(v=vs.85).aspx
// rand num generator http://gamedev.stackexchange.com/questions/32681/random-number-hlsl
// http://www.reedbeta.com/blog/2013/01/12/quick-and-easy-gpu-random-numbers-in-d3d11/
// https://docs.unity3d.com/Manual/RenderDocIntegration.html
// https://docs.unity3d.com/Manual/SL-ShaderPrograms.html


Shader "Unlit/RaytracerFinal"
{
	Properties
	{
		_rays_per_pixel("Rays per Pixel", Range(0, 50)) = 20
		_max_bounce("Max bounces", Range(0, 50)) = 20
		_camera_position("Camera position", Vector) = (1, 1, 1)
		_camera_look_at("Camera look at", Vector) = (0, 0, 0)
		_sphere_position_x("Sphere position, x axis", Range(-10, 10)) = 0
		[Toggle] _sphere_material("Toggle diffuse or glass", Range(0, 1)) = 0
		_sphere_refraction_index("Refraction index", Range(0, 10)) = 1
		_sphere_color("Color", Color) = (150, 150, 150) 
	}
	SubShader{ Pass	{
	CGPROGRAM
	#pragma vertex vert
	#pragma fragment frag

	typedef vector <float, 3> vec3;  // to get more similar code to book
	typedef vector <fixed, 3> col3;

	uint _rays_per_pixel;
	uint _max_bounce;

	vec3 _camera_position;
	vec3 _camera_look_at;

	float _sphere_position_x;
	bool _sphere_material;
	float _sphere_refraction_index;
	vec3 _sphere_color;

	static const float M_PI = 3.14159265f;

	static const uint MAXIMUM_DEPTH = 20;
	static const uint NUMBER_OF_SAMPLES = 25;

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
		uint index; //to keep track of which sphere we are on. Since we can use pointers like c++

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

	static float rand_seed = 12.0;

	float random_number(in float2 uv)
	{
		float2 noise = (frac(sin(dot(uv, float2(12.9898, 78.233)*2.0)) * 43758.5453));
		rand_seed += 0.21342;
		return abs(noise.x + noise.y) * 0.5;
	};

	vec3 random_in_unit_sphere() {
		vec3 p;
		do {
			p = 2.0 * vec3(random_number(uv.x + rand_seed * uv.y + rand_seed), random_number(uv.x + rand_seed * 2 * uv.y + rand_seed * 2), random_number(pow(uv.x, 2) + rand_seed * pow(uv.y, 2) + rand_seed)) - vec3(1.0, 1.0, 1.0);
		} while (dot(p, p) >= 1.0);
		return p;
	}

	float schlick(float cosine, float ref_idx)
	{
		float r0 = (1.0 - ref_idx) / (1.0 + ref_idx);
		r0 = r0 * r0;
		return r0 + (1.0 - r0) * pow(1.0 - cosine, 5.0);
	}

	bool refract(vec3 v, vec3 n, float ni_over_nt, out vec3 refracted)
	{
		vec3 uv = normalize(v);
		float dt = dot(uv, n);
		float discriminant = 1.0 - ni_over_nt * ni_over_nt * (1 - dt * dt);
		if(discriminant > 0)
		{
			refracted = ni_over_nt * (uv - n * dt) - n * sqrt(discriminant);
			return true;
		}
		else
			return false;
	}

	struct sphere
	{
		vec3 center;
		float radius;
		bool metal;
		bool dielectric;
		vec3 albedo;
		float fuzz;
		float ref_idx;

		bool hit(ray r, float tmin, float tmax, out hit_record rec) {
			rec.index = 0;
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

		bool scatter(ray r_in, hit_record rec, out vec3 attenuation, out ray scattered)
		{
			if (metal)
			{
				vec3 reflected = reflect(normalize(r_in.direction), rec.normal);
				scattered = ray::from(rec.p, reflected + fuzz * random_in_unit_sphere());
				attenuation = albedo;
				return (dot(scattered.direction, rec.normal) > 0);
			}
			if(dielectric)
			{
				vec3 outward_normal;
				vec3 reflected = reflect(r_in.direction, rec.normal);
				float ni_over_nt;
				attenuation = vec3(1.0, 1.0, 1.0);
				vec3 refracted;
				float reflect_prob;
				float cosine;
				
				if(dot(r_in.direction, rec.normal) > 0)
				{
					outward_normal = -rec.normal;
					ni_over_nt = ref_idx;
					cosine = ref_idx * dot(r_in.direction, rec.normal) / length(r_in.direction);
				}
				else
				{
					outward_normal = rec.normal;
					ni_over_nt = 1.0 / ref_idx;
					cosine = -dot(r_in.direction, rec.normal) / length(r_in.direction);
				}
				if(refract(r_in.direction, outward_normal, ni_over_nt, refracted))
				{
					reflect_prob = schlick(cosine, ref_idx);
				}
				else 
				{
					scattered = ray::from(rec.p, reflected);
					reflect_prob = 1.0;
				}
				if(random_number(ref_idx) < reflect_prob)
				{
					scattered = ray::from(rec.p, reflected);
				}
				else
				{
					scattered = ray::from(rec.p, refracted);
				}
				return true;
			}
			else //diffuse
			{
				vec3 target = rec.p + rec.normal + random_in_unit_sphere();
				scattered = ray::from(rec.p, target - rec.p);
				attenuation = albedo;
				return true;
			}
		}
	};

	static const uint NUMBER_OF_SPHERES = 5;
	static const sphere WORLD[NUMBER_OF_SPHERES] = {
		{ vec3(_sphere_position_x, 0.0, -1.0), 0.5, false, _sphere_material, _sphere_color, 1.0, _sphere_refraction_index},
		{ vec3(0.0, -100.5, -1.0), 100.0, false, false, vec3(0.6, 0.8, 0.2), 1.0, 0.0},
		{ vec3(1.0, 0.0, -1.0), 0.5, true, false, vec3(0.9, 0.6, 1.0), 0.3, 0.0},
		{ vec3(-1.0, 0.0, -1.0), 0.5, false, true, vec3(0.0, 0.0, 0.0), 1.0, 1.5},
		{ vec3(-1.0, 0.0, -1.0), -0.45, false, true, vec3(0.0, 0.0, 0.0), 1.0, 1.5}
		// Sphere format: { vec3 center, float radius, bool metal, bool dielectric, vec3 albedo, float fuzz, float ref_idx }
	};

	struct camera
	{
		vec3 origin;
		vec3 lower_left_corner;
		vec3 horizontal;
		vec3 vertical;

		static camera from(vec3 look_from, vec3 look_at, vec3 vup, float vfov, float aspect)
		{
			camera cam;

			float theta = vfov * M_PI/180;
			float half_height = tan(theta/2);
			float half_width = aspect * half_height;

			vec3 w = normalize(look_from - look_at);
			vec3 u = normalize(cross(vup, w));
			vec3 v = cross(w, u);

			cam.origin = look_from;
			cam.lower_left_corner = vec3(-half_width, -half_height, -1.0);
			cam.lower_left_corner = cam.origin - half_width * u - half_height * v - w;
			cam.horizontal = 2 * half_width * u;
			cam.vertical = 2 * half_height * v;
			return cam;
		}
		ray getRay(float u, float v)
		{
			return ray::from(origin, lower_left_corner + u * horizontal + v * vertical - origin);
		}
	};

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
				rec.index = i;
			}
		}
		return hit_anything;
	}

	vec3 color(ray r)
	{
		hit_record rec;
		vec3 accumColor = vec3(1.0, 1.0, 1.0);
		uint i = 0;
		while ((hit_world(r, 0.001, 100000.0, rec)) && i <= _max_bounce)
		{
			ray scattered;
			vec3 attenuation;
			WORLD[rec.index].scatter(r, rec, attenuation, scattered);
			r = scattered;
			accumColor *= attenuation;
			i += 1;
		}

		if (i == _max_bounce)
		{
			return vec3(0.0, 0.0, 0.0);
		}
		else 
		{
			vec3 unit_direction = normalize(r.direction);
			float t = 0.5 * (unit_direction.y + 1.0);
			return accumColor * (lerp(vec3(1.0, 1.0, 1.0), vec3(0.5, 0.7, 1.0), t));
		}
	};

	/////////////////////////////////////////////////////////////////////////////////////
	fixed4 frag(v2f i) : SV_Target
	{
		float u = i.uv.x;
		float v = i.uv.y;
		uv = float2(u, v);

		col3 col = col3(0.0, 0.0, 0.0);
		camera cam = camera::from(_camera_position, _camera_look_at, vec3(0,1,0), 45, 4.0 / 2.0);

		for (uint i = 0; i < _rays_per_pixel; i++) {
			ray r = cam.getRay(u, v);
			col += col3(color(r));
		}
		col /= _rays_per_pixel;
		col = sqrt(col); // gamma correction
		return fixed4(col,1);
	}
	////////////////////////////////////////////////////////////////////////////////////
	ENDCG
}}}


