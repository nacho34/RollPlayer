
1.0/60.0 => float dtGraphics;
float currentGraphicsFrameTimeSeconds;

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

// assume we sampled height positions horizontally at the original Agarwal et al resolution of 5.6 micrometers
0.0000056 => float inchesPerHeightSample;

 // pretend the window is this many inches wide in the simulation
10.0 => float windowWidthInches;

0.00001 => float inchesPerNoiseSample; // adjust density of noise
(windowWidthInches / inchesPerHeightSample) $ int => int heightmapSamples;
float heightmap[heightmapSamples];
Math.randomf() => float sampValue;
for (int i; i < heightmapSamples; i++) {
    if (i % ((inchesPerNoiseSample / inchesPerHeightSample) $ int) == 0)
        Math.randomf() * inchesPerHeightSample => sampValue; // set inchesPerHeightSample as the maximum height to avoid crazy acceleration
    sampValue => heightmap[i];
}

fun float sampleHeightmapNormalized(float heightmapToSample[], float samplingCoordZeroToOne) {
    (heightmapToSample.size() $ float * samplingCoordZeroToOne) $ int => int sampledLocation;
    (sampledLocation >= heightmapToSample.size()) ? heightmapToSample.size() - 1 : sampledLocation => sampledLocation;
    (sampledLocation <= 0) ? 0 : sampledLocation => sampledLocation;
    return heightmapToSample[sampledLocation];
}

// FOR TESTING: playback heightmap directly as audio
Impulse heightmapPlayer => dac;
fun void playHeightMap(float heightmapToPlay[]) {
    for (int i; i < heightmapToPlay.size(); i++) {
        heightmapPlayer.next(heightmapToPlay[i] * 0.2); // arbitrary low gain for now
        1::samp => now;
    }
} // spork ~playHeightMap(heightmap); // for example

// finite difference to get first derivative
fun float fdFirstDerivative(float fXPlusH, float fXMinusH, float H) {
    return (fXPlusH - fXMinusH) / 2 * H;
}

// finite difference to get second derivative
fun float fdSecondDerivative(float fXPlusH, float fX, float fXMinusH, float H) {
    return (fXPlusH - 2 * fX + fXMinusH) / (H * H);
}

float heightmapFirstDerivatives[heightmapSamples - 2];
float heightmapSecondDerivatives[heightmapSamples - 2];
for (1 => int i; i < heightmapSamples - 2; i++) {
    fdFirstDerivative(heightmap[i + 1], heightmap[i - 1], inchesPerHeightSample) => heightmapFirstDerivatives[i - 1];
    fdSecondDerivative(heightmap[i + 1], heightmap[i], heightmap[i - 1], inchesPerHeightSample) => heightmapSecondDerivatives[i - 1];
} // spork ~playHeightMap(heightmapSecondDerivative);

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
    secondPartialOfS(normalForce, sampleHeightmapNormalized(heightmapSecondDerivatives, normalizedPositionX)) => float SSecondPartial;
    scrapePlayer.next(scraperMass * velocityX * velocityX * SSecondPartial);
    
    //scrapePlayer.next(scraperMass * velocityX * velocityX * sampleHeightmapNormalized(heightmapSecondDerivatives, normalizedPositionX));
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

while (true) {
    GG.nextFrame() => now;
    now / second => currentGraphicsFrameTimeSeconds;
    updateMousePos();
    updateMouseVelocity();
}