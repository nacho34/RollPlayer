/* Heightmap.wgsl
 * ----------------------------------------------------------------
 * Generates an artificial heightmap using value noise and computes
 * two levels of derivatives.
 * Results written into textures that can be read back to the CPU.
 */

// https://www.shadertoy.com/view/Xt3cDn
fn xxhash(p : u32) -> u32 {
    var h32 = p + 374761393u;
    h32 = 668265263u * ((h32 << 17) | (h32 >> (32 - 17)));
    h32 = 2246822519u * (h32 ^ (h32 >> 15));
    h32 = 3266489917u * (h32 ^ (h32 >> 13));
    return h32^(h32 >> 16);
}

fn rand(p : f32) -> f32 
{ 
    return f32(xxhash(bitcast<u32>(p))) / f32(0xffffffff); 
}

// 1D value noise with derivatives
// Returns (value, first derivative, second derivative)
fn noised(p : f32) -> vec3f
{
    let i = floor(p);
    let f = fract(p);

    // Quintic interpolation
    let u   = f*f*f*(f*(f*6.0-15.0)+10.0);
    let du  = 30.0*f*f*(f*(f-2.0)+1.0);
    let ddu = 60.0*f*(f*(f*2.0-3.0)+1.0);

    let a = rand(i);
    let b = rand(i+1.0);

    return vec3f(mix(a, b, u), (a - b) * du, (a - b) * ddu);
}

// Fractal brownian motion with derivatives
fn fbm(p : f32, nf : i32, freq : f32, amp: f32, lac : f32, gain : f32) -> vec3f
{
    var f = freq;
    var a = amp;

    var val = 0.0;
    var d   = 0.0;
    var dd  = 0.0;
    for (var i = 0; i < nf; i++)
    {
        let n = noised(p*f);
        val += a*n.x;
        d   += a*f*n.y;
        dd  += a*f*n.z;

        f *= lac;
        a *= gain;
    }
    return vec3f(val, d, dd);
}

//-----------------------------------------------------------------
// Noise uniforms
@group(0) @binding(0) var<uniform> freq : f32;
@group(0) @binding(1) var<uniform> amp  : f32;
@group(0) @binding(2) var<uniform> lac  : f32;
@group(0) @binding(3) var<uniform> gain : f32;

// Output texture and scale information
@group(0) @binding(4) var<uniform> sample_size : f32;
@group(0) @binding(5) var heightmap: texture_storage_2d<rgba32float, write>;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) GlobalInvocationID : vec3<u32>) {
    let idx = GlobalInvocationID.xy;
    let dims = textureDimensions(heightmap);
    let map_rows = dims.y / 3;
    if (idx.x >= dims.x || idx.y >= map_rows) {
        return;
    }

    let n_freqs = 8;

    // Normalize so the max noise value is equal to amp
    var inv_max_val = 1.0 / f32(n_freqs);
    if (gain < 1.0)
    {
        inv_max_val = (1.0 - gain) / (1.0 - pow(gain, f32(n_freqs)));
    }
    let amp_n = amp * inv_max_val;

    // Pack 4 samples into each texel
    var out   = vec4f(0.0);
    var outd  = vec4f(0.0);
    var outdd = vec4f(0.0);

    // Initial sample index
    let s0 = (idx.y * dims.x + idx.x) * 4;
    let offset = 23.0;

    let n0 = fbm(f32(s0)*sample_size+offset, n_freqs, freq, amp_n, lac, gain);
    out.x = n0.x; outd.x = n0.y; outdd.x = n0.z;
   
    let n1 = fbm(f32(s0+1)*sample_size+offset, n_freqs, freq, amp_n, lac, gain);
    out.y = n1.x; outd.y = n1.y; outdd.y = n1.z;

    let n2 = fbm(f32(s0+2)*sample_size+offset, n_freqs, freq, amp_n, lac, gain);
    out.z = n2.x; outd.z = n2.y; outdd.z = n2.z;
        
    let n3 = fbm(f32(s0+3)*sample_size+offset, n_freqs, freq, amp_n, lac, gain);
    out.w = n3.x; outd.w = n3.y; outdd.w = n3.z;

    textureStore(heightmap, vec2u(idx.x, idx.y), out);
    textureStore(heightmap, vec2u(idx.x, idx.y + map_rows), outd);
    textureStore(heightmap, vec2u(idx.x, idx.y + 2*map_rows), outdd);
}