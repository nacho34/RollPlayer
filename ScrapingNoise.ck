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
// GAME SETUP
// -----------------------------------------------

// Euler-Bernoulli Beam constants
[4.73004, 7.85320, 10.9956, 14.1372, 17.2788, 20.4204, 23.5619, 26.7035] @=> float BL[];

// EB Beam overtone ratios
float BEAM_FREQ_RATIOS[BL.size()];
for (0=>int i; i<BL.size(); i++)
{
    Math.pow(BL[i] / BL[0], 2.0) => BEAM_FREQ_RATIOS[i];
}

// Linear interpolation between two vectors
fun vec3 lerp(vec3 a, vec3 b, float t) { return (1.0-t) * a + t * b; }

// Rotate an input vector about the y axis
fun vec3 rotate2D(vec3 a, float theta)
{
    Math.cos(theta) * a.x - Math.sin(theta) * a.z => float xPrime;
    Math.sin(theta) * a.x + Math.cos(theta) * a.z => float zPrime;
    return @(xPrime, a.y, zPrime);
}

// Clamp a vector component-wise
fun vec3 clampv(vec3 value, float min, float max)
{
    return @(Math.clampf(value.x, min, max),
             Math.clampf(value.y, min, max),
             Math.clampf(value.z, min, max));
}

// Camera setup
GG.scene().camera().rotX(-Math.PI/2);
GG.scene().camera().pos(@(0, 40, 0));

// Noise material setup
ShaderDesc mat_desc;
me.dir() + "BoardMat.wgsl" => mat_desc.vertexPath;
me.dir() + "BoardMat.wgsl" => mat_desc.fragmentPath;

Shader matShader(mat_desc);
matShader.name("Heightmap");
Material mat(matShader);

// Colliders with impact sound synthesis
class Wall extends GGen {
    3.0 => float ampScale;       // Volume adjust

    // Damping constants
    10.0 => float alpha;          // Mass
    0.00005 => float beta;       // Stiffness

    // Per-mode oscillators
    SinOsc modes[BEAM_FREQ_RATIOS.size()];

    // omega, damping, sigma for mode amplitudes
    float omegas[modes.size()];
    float d[modes.size()];
    float sigmas[modes.size()];

    // To be recalculated on impact
    now - 1::hour => time t0;
    t0 => time lastImpact;
    float amplitudes[modes.size()];

    // w, h, w segments, h segments
    CubeGeometry geo(1.0, 1.0, 1.0, 1, 1, 1);
    PhongMaterial mat;
    mat.color(@(0.54, 0.41, 0.08));

    GMesh wallModel(geo, mat) --> this;
    wallModel.rotX(Math.PI/2.0);;

    fun Wall(vec3 pos, float rot, float size) 
    {
        this.pos(pos);
        this.rotY(rot);
        this.scaX(size);

        // Init modes
        for (0=>int i; i<modes.size(); i++)
        {
            220.0 + Math.random2f(-30.0, 30.0) => float freq;
            freq * BEAM_FREQ_RATIOS[i] => modes[i].freq;
            0 => modes[i].gain;
            modes[i] => dac;
        }

        // Precalculate constants for amplitudes
        for (0=>int i; i<modes.size(); i++)
        {
            modes[i].freq() * Math.TWO_PI => omegas[i];
            alpha * beta * omegas[i] * omegas[i] / 4 => d[i];
            (Math.cosh(BL[i]) - Math.cos(BL[i])) / 
            (Math.sinh(BL[i]) - Math.sin(BL[i])) => sigmas[i];
        
        }
    }

    // Modal synthesis based on Euler-Bernoulli beam model
    fun void synthesize()
    {
        while (true)
        {
            100::samp => now;
            for (0=>int i; i<modes.size(); i++)
            {
                (now - t0) / 1::second => float t;
                amplitudes[i] * Math.exp(-d[i] * t)
                                => modes[i].gain;
            }
        }
    } spork ~ synthesize();

    // Called on impact with ball, recomputes mode amplitudes and resets decay
    fun void impact(float strength, float pos) 
    {
        // Account for constant contact
        if (now - lastImpact < 0.2::second) 
        { 
            now => lastImpact;
            return;
        }
        now => lastImpact;
        now => t0;

        Math.clampf(strength*ampScale, 0.05, 0.1) => strength;

        for (0=>int i; i<amplitudes.size(); i++)
        {
            // Mode shape at impact position
            BL[i] * pos => float bX;
            strength * (Math.cosh(bX) + Math.cos(bX) -
                        sigmas[i] * (Math.sinh(bX) + Math.sin(bX)))
                        => amplitudes[i];
            Math.fabs(amplitudes[i]) => amplitudes[i];
        }
    }
}

// The star of the show!
class Marble extends GGen
{
    @(0,  0,  0) => vec3 vel;
    @(0, -1,  0) => vec3 gDir;
    50.0 => float g;
    0.90 => float fr;
    0.65 => float e;  // coeff of restiution

    0.0  => float spd;
    0.05 => float hmapSca;
    0.0  => float hmapPos;
    true => int hmapFwd;

    Wall @ walls[];

    GSphere ball --> this;
    ball.sca(2.0);  // So radius is 1.0 if this.scaX() is 1.0
    ball.color(@(0.54, 0.41, 0.08));

    this.sca(0.5);

    fun Marble() {}
    fun Marble(vec3 pos, Wall @ w[]) { this.pos(pos); w @=> walls; }

    fun void setGDir(vec3 dir) { dir @=> gDir; }

    fun int resolveCollision(Wall @ wall)
    {
        // Transform coordinates so rect is flat at origin
        rotate2D(this.pos(), wall.rotY()) @=> vec3 b;
        rotate2D(wall.pos(), wall.rotY()) @=> vec3 c; 
        c -=> b;

        wall.scaX() / 2.0 => float cx;
        wall.scaY() / 2.0 => float cz;
        
        // Intersect check
        if (Math.fabs(b.x) > this.scaX() + cx) { return false; }
        if (Math.fabs(b.z) > this.scaZ() + cz) { return false; }

        // Closest point on rectangle
        @(Math.clampf(b.x, -cx, cx), Math.clampf(b.z, -cz, cz)) @=> vec2 hitPos;

        // Makes sure there is contact
        @(b.x, b.z) - hitPos @=> vec2 d;
        if (d.dot(d) > this.scaX() * this.scaX()) { return false; }

        // Move ball out of wall
        d.normalize();
        hitPos + ((this.scaX()+0.01)*d) @=> vec2 newPos;

        // Return to world space
        @(newPos.x, 0, newPos.y) + c @=> vec3 newPosWorld;
        @(d.x, 0, d.y) @=> vec3 nWorld;
        rotate2D(newPosWorld, -wall.rotY()) @=> newPosWorld;
        rotate2D(nWorld, -wall.rotY()) @=> nWorld;

        // Synthesize wall sound on impact
        Math.sqrt(this.vel.dot(this.vel)) => float strength;
        hitPos.x / wall.scaX() + 0.5 => float hitPosNorm;
        wall.impact(strength, hitPosNorm);

        this.pos(newPosWorld);
        this.vel - ((1.0 + e) * this.vel.dot(nWorld) * nWorld) @=> this.vel;

        return true;
    }

    fun void update(float dt)
    {
        dt*g*gDir.x -=> this.vel.x;
        dt*g*gDir.z -=> this.vel.z;
        1.0-(fr*dt) *=> this.vel;  // Fake friction
        this.translate(this.vel*dt);

        Math.sqrt(this.vel.dot(this.vel)) => spd;
        spd*dt*hmapSca => float dp;
        if (!hmapFwd) -1 *=> dp;
        dp +=> hmapPos;

        if (hmapFwd) { if (hmapPos+dp >= 1.0) false => hmapFwd; }
        else { if (hmapPos+dp <= 0.0) true => hmapFwd; }

        for (0=>int iter; iter<10; iter++)
        {
            0 => int col;
            for (0=>int i; i<walls.size(); i++)
            {
                if (resolveCollision(walls[i])) { 1 => col; }
            }
            if (!col) { break; }
        } 
    }
}

// Controls game logic; all elements should be grucked to this
class Labyrinth extends GGen {
    Wall @ walls[4];
    Marble ball(@(0, 0, 0), walls) --> this;

    new Wall(@(-10, 0, 0), Math.PI/2, 21.0) @=> walls[0];
    new Wall(@( 10, 0, 0), Math.PI/2, 21.0) @=> walls[1];
    new Wall(@(0, 0,  10), 0, 19.0) @=> walls[2];
    new Wall(@(0, 0, -10), 0, 19.0) @=> walls[3];

    for(int i; i < walls.size(); i++) { walls[i] --> this; }

    PlaneGeometry boardGeo;
    GMesh gameBoard(boardGeo, mat) --> this;
    gameBoard.sca(21.0);
    gameBoard.rotX(Math.pi/2);
    gameBoard.posY(-0.5);

    Math.PI/8 => float rotMax;
    0.7 => float rotStr;
    @(0, 0, 0) => vec3 rotTarget;

    fun float getMarbleDistNorm() 
    { 
        return ball.hmapPos;
    }

    fun float getMarbleSpeed()
    {
        if (ball.hmapFwd) return ball.spd * ball.hmapSca;
        return -ball.spd * ball.hmapSca;
    }

    fun void update(float dt)
    {
        if (GWindow.key(GWindow.KEY_W)) rotStr*dt -=> rotTarget.x;
        if (GWindow.key(GWindow.KEY_S)) rotStr*dt +=> rotTarget.x;
        if (GWindow.key(GWindow.KEY_A)) rotStr*dt +=> rotTarget.z;
        if (GWindow.key(GWindow.KEY_D)) rotStr*dt -=> rotTarget.z;
        clampv(rotTarget, -rotMax, rotMax) @=> rotTarget;

        this.rot(lerp(this.rot(), rotTarget, dt*4.0));
        ball.setGDir(this.up()*-1);
    }
}

Labyrinth game --> GG.scene();

// -----------------------------------------------
// HEIGHTMAP GENERATION
// -----------------------------------------------

// Simulates Agarwal et al resolution of 5.6 micrometers
//0.0000056 => float IN_PER_HEIGHT_SAMPLE;
0.00002 => float IN_PER_HEIGHT_SAMPLE;
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
20.0 => float freq;
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
    hmap.uniformFloat(1, amp);
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

// Linearly-interpolated sampling
fun float sampleHeightmap(int hmapIdx, float u) {
    heightmapSamples $ float * u => float samplePos;
    Math.floor(samplePos) $ int => int sampleIdx;
    samplePos - sampleIdx $ float => float fract;
    Math.clampi(sampleIdx, 0, heightmapSamples - 1) => int idxLeft;
    Math.clampi(sampleIdx + 1, 0, heightmapSamples - 1) => int idxRight;
    hmapIdx * heightmapSamples +=> idxLeft;
    hmapIdx * heightmapSamples +=> idxRight;
    heightmap[idxLeft] => float sampleLeft;
    heightmap[idxRight] => float sampleRight;
    return sampleLeft + u*(sampleRight - sampleLeft);
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

0.001 => float scraperMass;
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
        
        (now / second - currentGraphicsFrameTimeSeconds) => float interpolator;
        game.getMarbleSpeed() => float spd;
        game.getMarbleDistNorm() + spd * interpolator => float pos;
        setNextScraperAudioSample(spd, pos, 0.5);


        // NOTE: must adjust scraper mass to switch back to mouse
        // interpolate mouse position between graphics frames
        // prevFrameNormalizedMousePos.x + interpolator * (curFrameNormalizedMousePos.x - prevFrameNormalizedMousePos.x) => float interpolatedMouseX;
        // prevFrameNormalizedMousePos.y + interpolator * (curFrameNormalizedMousePos.y - prevFrameNormalizedMousePos.y) => float interpolatedMouseY;
        // prevMouseVelocity.x + interpolator * (mouseVelocity.x - prevMouseVelocity.x) => float interpolatedMouseVelocityX;
        
        // setNextScraperAudioSample(interpolatedMouseVelocityX, interpolatedMouseX, interpolatedMouseY);
     
        //Logging
        counter++;
        if (counter % 1000 == 0) {
           //<<< "current mouse x: " + currentMouseX >>>;
           //<<< "previous mouse x: " + prevMouseX >>>;
           //    <<< "interpolated mouse x: " + interpolatedMouseX >>>;
           //    <<<"mouse vel" + interpolatedMouseVelocityX >>>;

           //     <<<"ball vel" + spd>>>;
           //     <<<"ball x" + pos>>>;
           //<<<interpolator>>>;
        }
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