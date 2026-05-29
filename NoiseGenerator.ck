// Math utils
fun float fract(float n) { return n - Math.floor(n); }
fun float hash(float n) { return fract(Math.sin(n+123.543) * 43758.5453123); }

// Vector math utils
fun vec2 vecFloor(vec2 n) { return @(Math.floor(n.x), Math.floor(n.y)); }
fun vec2 vecFract(vec2 n) { return @(fract(n.x), fract(n.y)); }
fun float vecHash(vec2 n) { retun hash(n.x + n.y*31); }

/* Alternate vec2 hashing if the 2D -> 1D doesn't work
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
} */

// 2D value noise with derivatives
// Returns @(noise value, x-derivative, y-derivative)
fun vec3 noise(vec2 p) {
    vecFloor(p) => vec2 i;
    vecFract(p) => vec2 f;

    // quintic interpolation
    f*f*f*(f*(f*6.0-@(15.0, 15.0))+@(10.0, 10.0)) => vec2 u;
    30.0*f*f*(f*(f-@(1.0, 1.0))+@(2.0,2.0)) => vec2 du;
    
    vecHash(i+@(0, 0)) => float a;
    vecHash(i+@(1, 0)) => float b;
    vecHash(i+@(0, 1)) => float c;
    vecHash(i+@(1, 1)) => float d;

    a => float k0;
    b - a => float k1;
    c - a => float k2;
    a - b - c + d => float k3;

    k0 + k1*u.x + k2*u.y + k3*u.x*u.y => float val;
    du * @(k1 + k3*u.y, k2 + k3*u.x) => vec2 d;

    return @(val, d.x, d.y);
}

// Fractal brownian motion adapted from Inigo Quilez
fun vec3 fbm(vec2 x) {
    8 => int nFreqs;

    // Params (currently hardcoded)
    1.0 => float freq;
    1.0 => float amp;
    2.0 => float lac;
    0.5 => float gain; 
    
    0.0 => float val;
    @(0.0, 0.0) => vec2 d;

    for (0 => int i; i < nFreqs; i++) {
        vec3 n = noise(x*freq);

        amp*n.x +=> val;
        amp*freq*@(n.y, n.z) +=> d;

        lac *=> freq;
        gain *=> amp;
    }
    return @(val, d.x, d.y);
}
