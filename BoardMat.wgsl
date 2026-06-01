#include FRAME_UNIFORMS
#include DRAW_UNIFORMS
#include STANDARD_VERTEX_INPUT
#include STANDARD_VERTEX_OUTPUT
#include STANDARD_VERTEX_SHADER

// https://www.shadertoy.com/view/Xt3cDn
fn xxhash(p : vec2u) -> u32 {
    let p2 = 2246822519u; let p3 = 3266489917u;
    let p4 = 668265263u;  let p5 = 374761393u;
    var h32 = p.y + p5 + p.x * p3;
    h32 = p4 * ((h32 << 17) | (h32 >> (32 - 17)));
    h32 = p2 * (h32^(h32 >> 15));
    h32 = p3 * (h32^(h32 >> 13));
    return h32^(h32 >> 16);
}

// Generates a random float from 0 to 1 given an input 2d vector
fn rand(p : vec2f) -> f32 
{
    return f32(xxhash(bitcast<vec2u>(p))) / f32(0xffffffff);
}

// 2D value noise
fn noise(p : vec2f) -> f32
{
    let i = floor(p);
    let f = fract(p);

    // Quintic interpolation
    let u = f*f*f*(f*(f*6.0-15.0)+10.0);

    let a = rand(i+vec2f(0, 0));
    let b = rand(i+vec2f(1, 0));
    let c = rand(i+vec2f(0, 1));
    let d = rand(i+vec2f(1, 1));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p : vec2f, freq : f32, amp: f32, lac : f32, gain : f32) -> f32
{
    // Make values mutable
    var f = freq;
    var a = amp;

    var val = 0.0;
    for (var i = 0; i < 8; i++)
    {
        let n = noise(p*f);
        val += a*n;
        f *= lac;
        a *= gain;
    }
    return val;
}

//-------------------------------------------------

// SHADER UNIFORMS
@group(1) @binding(0) var<uniform> freq : f32;
@group(1) @binding(1) var<uniform> amp  : f32;
@group(1) @binding(2) var<uniform> lac  : f32;
@group(1) @binding(3) var<uniform> gain : f32;

@fragment 
fn fs_main(in : VertexOutput) -> @location(0) vec4f
{   
    // Adjust amp so value is capped at 1.0
    let invMaxVal = clamp(1.0-gain, 0.125, 1.0);
    let ampN = amp * invMaxVal;

    let pos = in.v_uv + vec2f(23.0);
    let val = fbm(pos, freq, ampN, lac, gain);
    return vec4f(vec3f(1.0-val), 1.0);
}