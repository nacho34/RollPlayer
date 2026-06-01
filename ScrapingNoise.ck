// @import "NoiseGenerator.ck"  // Replaced by compute shader

1.0/60.0 => float dtGraphics;
float currentGraphicsFrameTimeSeconds;

// -----------------------------------------------
// MOUSE TRACKING
// -----------------------------------------------

// 1,1 is top right
fun vec2 normalizedMousePos() {
    return @(GWindow.mousePos().x / GWindow.windowSize().x, 1 - GWindow.mousePos().y / GWindow.windowSize().y);
}

vec2 curFrameNormalizedMousePos;
vec2 prevFrameNormalizedMousePos;
fun void updateMousePos() {
    curFrameNormalizedMousePos => prevFrameNormalizedMousePos;
    normalizedMousePos() => curFrameNormalizedMousePos;
}

vec2 prevMouseVelocity; // for use by audio engine when interpolating between graphics frames
vec2 mouseVelocity;
vec2 prevMousePos;
fun void updateMouseVelocity() {
    normalizedMousePos() => vec2 currentMousePos;
    mouseVelocity => prevMouseVelocity;
    @((currentMousePos.x - prevMousePos.x) / dtGraphics, (currentMousePos.y - prevMousePos.y) / dtGraphics) => mouseVelocity;
    currentMousePos => prevMousePos;
}

fun void printMousePosAndVelocity() {
    while (true) {
        <<< "mouse pos x " + normalizedMousePos().x >>>;
        <<< "mouse pos y " + normalizedMousePos().y>>>;
        <<< "mouse velocity x " + mouseVelocity.x >>>;
        <<< "mouse velocity y " + mouseVelocity.y>>>;
        0.1::second => now;
    }
} //spork ~printMousePosAndVelocity();

// -----------------------------------------------
// GAME BOARD
// -----------------------------------------------

TextureDesc tex_desc;
1080 => tex_desc.width;
1080 => tex_desc.height;
Texture.FORMAT_RGBA16FLOAT => tex_desc.format;
Texture tex(tex_desc);

ShaderDesc mat_desc;
me.dir() + "BoardMat.wgsl" => mat_desc.vertexPath;
me.dir() + "BoardMat.wgsl" => mat_desc.fragmentPath;

Shader mat_shader(mat_desc);
mat_shader.name("Heightmap");

Material mat(mat_shader);
PlaneGeometry board_geo;
GMesh board(board_geo, mat) --> GG.scene();
board.sca(3.0);

// -----------------------------------------------
// HEIGHTMAP GENERATION
// -----------------------------------------------

// Simulates Agarwal et al resolution of 5.6 micrometers
0.000056 => float IN_PER_HEIGHT_SAMPLE;  // Note: increased 10x due to strange artifacting
10.0 => float WINDOW_WIDTH_IN;

// For texture alignment
1024 => int HMAP_TEX_WIDTH;

// Calculate texture dimension, round sample count to nearest HMAP_TEX_WIDTH
(WINDOW_WIDTH_IN / IN_PER_HEIGHT_SAMPLE) $ int / 4 => int heightmapTexels;
(heightmapTexels+HMAP_TEX_WIDTH-1)/HMAP_TEX_WIDTH => int heightmapRows;
heightmapRows * HMAP_TEX_WIDTH => heightmapTexels;
heightmapTexels * 4 => int heightmapSamples;

// Texture to be populated by the compute shader
TextureDesc hmap_tex_desc;
HMAP_TEX_WIDTH  => hmap_tex_desc.width;
heightmapRows*3 => hmap_tex_desc.height;
Texture.FORMAT_RGBA32FLOAT => hmap_tex_desc.format;
false => hmap_tex_desc.mips;
Texture hmap_tex(hmap_tex_desc);

8 => int WG_SIZE;

// The hmap shader dynamically generates a heightmap with two derivatives
ShaderDesc hmap_desc;
me.dir() + "Heightmap.wgsl" => hmap_desc.computePath;
Shader hmap_shader(hmap_desc);
ComputePass hmap(hmap_shader);
hmap.workgroup((HMAP_TEX_WIDTH + WG_SIZE - 1) / WG_SIZE, 
               (heightmapRows  + WG_SIZE - 1) / WG_SIZE, 
               1);

GG.outputPass() --> hmap;

// Noise parameters
10.0 => float freq;
0.5  => float amp;
2.0  => float lac;
0.5  => float gain;

UI_Float f(freq);
UI_Float a(amp);
UI_Float l(lac);
UI_Float g(gain);

fun setUniforms()
{
    mat.uniformFloat(0, freq);
    mat.uniformFloat(1, amp);
    mat.uniformFloat(2, lac);
    mat.uniformFloat(3, gain);

    // Amp scaled down to match surface roughness
    hmap.uniformFloat(0, freq);
    hmap.uniformFloat(1, amp * 0.0001);
    hmap.uniformFloat(2, lac);
    hmap.uniformFloat(3, gain);
}
setUniforms();
hmap.uniformFloat(4, IN_PER_HEIGHT_SAMPLE);
hmap.storageTexture(5, hmap_tex);

float heightmap[heightmapSamples * 3];

// Send heightmap from GPU to CPU (some latency)
fun void updateHeightmap() {
    while(true) {
        hmap_tex.read() => now;
        hmap_tex.data() @=> heightmap;
    }
} spork ~ updateHeightmap();

// Enum for heightmap index
0 => int H;
1 => int HPRIME;
2 => int HDOUBLEPRIME;

fun float sampleHeightmap(int hmapIdx, float u) {
    (heightmapSamples $ float * u) $ int => int sampleIdx;
    Math.clampi(sampleIdx, 0, heightmapSamples - 1) => sampleIdx;
    hmapIdx * heightmapSamples +=> sampleIdx;
    return heightmap[sampleIdx];
}

// FOR TESTING: playback heightmap directly as audio
Impulse heightmapPlayer => dac;
fun void playHeightMap(float heightmapToPlay[]) {
    for (int i; i < heightmapToPlay.size(); i++) {
        heightmapPlayer.next(heightmapToPlay[i] * 0.2); // arbitrary low gain for now
        1::samp => now;
    }
} // spork ~playHeightMap(heightmap); // for example

// -----------------------------------------------
// SOUND SYNTHESIS
// -----------------------------------------------

// constants copied from Agarwal et al paper
//float zeta = 0.95;
0.01 => float alphaMin;
0.05 => float alphaMax;
1 => float NMax; // Normal force is currently set from 0 to 1 depending on y position of mouse
0 => float NMin;

// apply nonlinearity with normal force bounds to get trajectory second derivative for a single height sample as per equations (4, 5, 6, 7) in Agarwal
fun float secondPartialOfS(float normalForce, float heightmapSecondDerivative) {
    (normalForce - NMin) / (NMax - NMin) => float v;
    (1 - v) * alphaMax + v * alphaMin => float alpha;
    return (1.0 / alpha) * Math.tanh(alpha * heightmapSecondDerivative);
}

0.5 => float scraperMass;
Impulse scrapePlayer => dac;
fun void setNextScraperAudioSample(float velocityX, float normalizedPositionX, float normalForce) {
    secondPartialOfS(normalForce, sampleHeightmap(HDOUBLEPRIME, normalizedPositionX)) => float SSecondPartial;
    scrapePlayer.next(scraperMass * velocityX * velocityX * SSecondPartial);
    
    //scrapePlayer.next(scraperMass * velocityX * velocityX * sampleHeightmap(HDOUBLEPRIME, normalizedPositionX));
}

0 => int counter;
fun void makeScrubbingSounds() {
    while (true) {
        samp => now;
        
        // interpolate mouse position between graphics frames
        (now / second - currentGraphicsFrameTimeSeconds) / dtGraphics => float interpolator;
        prevFrameNormalizedMousePos.x + interpolator * (curFrameNormalizedMousePos.x - prevFrameNormalizedMousePos.x) => float interpolatedMouseX;
        prevFrameNormalizedMousePos.y + interpolator * (curFrameNormalizedMousePos.y - prevFrameNormalizedMousePos.y) => float interpolatedMouseY;
        prevMouseVelocity.x + interpolator * (mouseVelocity.x - prevMouseVelocity.x) => float interpolatedMouseVelocityX;
        
        setNextScraperAudioSample(interpolatedMouseVelocityX, interpolatedMouseX, interpolatedMouseY);
     
        // // Logging
        // counter++;
        // if (counter % 100 == 0) {
        //    <<< "current mouse x: " + currentMouseX >>>;
        //    <<< "previous mouse x: " + prevMouseX >>>;
        //    <<< "interpolated mouse x: " + interpolatedMouseX >>>;
        //}
    }
} spork ~makeScrubbingSounds();

// -----------------------------------------------
// GAMELOOP AND UI
// -----------------------------------------------

while (true) {
    GG.nextFrame() => now;
    now / second => currentGraphicsFrameTimeSeconds;
    updateMousePos();
    updateMouseVelocity();

    if (UI.begin("Noise Parameters")) {
        false => int update;
        if (UI.slider("Frequency",  f, 1.0, 1000.0)) { f.val() => freq; true => update; }
        if (UI.slider("Amplitude",  a, 0.0, 1.0  )) { a.val() => amp;  true => update; }
        if (UI.slider("Lacunarity", l, 1.0, 3.0   )) { l.val() => lac;  true => update; }
        if (UI.slider("Gain",       g, 0.0, 1.0   )) { g.val() => gain; true => update; }
        
        if (update) { setUniforms(); }
    }
}