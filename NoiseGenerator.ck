/* NoiseGenerator.ck
 * -----------------
 * Class to generate fractal noise from an input 2D coordinate.
 * Noise parameters are specified in the constructor.
 */

public class NoiseGen {
    1.0 => float freq;  // Lowest frequency of the noise
    1.0 => float amp;   // Amplitude of first frequency (final amp will be higher)
    2.0 => float lac;   // Scales the freqency each iteration
    0.5 => float gain;  // Scales the amplitude each iteration

    fun NoiseGen() {}
    fun NoiseGen(float f, float a, float l, float g) {
        f => freq;
        a => amp;
        l => lac;
        g => gain;
    }

    // Math utils
    fun float fract(float n) { return n - Math.floor(n); }
    fun float hash(float n) { return fract(Math.sin(n+123.543) * 43758.5453123); }

    // Vector math utils
    fun vec2 vecFloor(vec2 n) { return @(Math.floor(n.x), Math.floor(n.y)); }
    fun vec2 vecFract(vec2 n) { return @(fract(n.x), fract(n.y)); }
    fun float vecHash(vec2 n) { return hash(n.x + n.y*31); }
    fun vec2 mult(vec2 a, vec2 b) { return @(a.x * b.x, a.y * b.y); }

    /* Alternate vec2 hashing if the 2D -> 1D doesn't work
    float hash(vec2 p) {
        return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
    } */

    // 2D value noise with derivatives
    // Returns @(noise value, x-derivative, y-derivative)
    fun vec3 valueNoise(vec2 p) {
        vecFloor(p) => vec2 i;
        vecFract(p) => vec2 f;

        // quintic interpolation
        @(f.x*f.x*f.x*(f.x*(f.x*6.0-15.0)+10.0),
          f.y*f.y*f.y*(f.y*(f.y*6.0-15.0))+10.0) @=> vec2 u;

        @(30.0*f.x*f.x*(f.x*(f.x-1.0)+2.0),
          30.0*f.y*f.y*(f.y*(f.y-1.0)+2.0)) @=> vec2 du;
    
        vecHash(i+@(0, 0)) => float a;
        vecHash(i+@(1, 0)) => float b;
        vecHash(i+@(0, 1)) => float c;
        vecHash(i+@(1, 1)) => float d;

        a => float k0;
        b - a => float k1;
        c - a => float k2;
        a - b - c + d => float k3;

        k0 + k1*u.x + k2*u.y + k3*u.x*u.y => float val;
        mult(du, @(k1 + k3*u.y, k2 + k3*u.x)) => vec2 derivative;

        return @(val, derivative.x, derivative.y);
    }

    // Fractal brownian motion adapted from Inigo Quilez
    fun vec3 fbm(vec2 p, float freq, float amp, float lac, float gain) {
        8 => int nFreqs;

        0.0 => float val;
        @(0.0, 0.0) => vec2 d;

        for (0 => int i; i < nFreqs; i++) {
            valueNoise(p*freq) => vec3 n;

            amp*n.x +=> val;
            amp*freq*@(n.y, n.z) +=> d;

            lac *=> freq;
            gain *=> amp;
        }
        return @(val, d.x, d.y);
    }

    // No derivatives
    fun float noise(vec2 p) {
        fbm(p, freq, amp, lac, gain) @=> vec3 val;
        return val.x;
    }

    // Yes derivatives
    fun vec3 noiseD(vec2 p) { 
        return fbm(p, freq, amp, lac, gain); 
    }
}
