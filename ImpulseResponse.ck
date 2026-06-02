
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
// Impulse resp imp
// -----------------------------------------------
5 => int IRRows;
6 => int IRCols;
SndBuf IRs[IRRows][IRCols];

"IRs/wood_block/" => string baseFolder;
for (int row; row < IRRows; row++) {
    for (int col; col < IRCols; col++) {
        IRs[row][col].read(baseFolder + "Row" + (row + 1) + "/0" + (col + 1) + ".wav");
        IRs[row][col] => dac;
    }
}

// test: play the impulse response interpolated across the screen when clicked
fun void handleIRTrigger() {
    (now / second - currentGraphicsFrameTimeSeconds) / dtGraphics => float interpolator;
    prevFrameNormalizedMousePos.x + interpolator * (curFrameNormalizedMousePos.x - prevFrameNormalizedMousePos.x) => float interpolatedMouseX;
    prevFrameNormalizedMousePos.y + interpolator * (curFrameNormalizedMousePos.y - prevFrameNormalizedMousePos.y) => float interpolatedMouseY;
    prevMouseVelocity.x + interpolator * (mouseVelocity.x - prevMouseVelocity.x) => float interpolatedMouseVelocityX;
    
    (interpolatedMouseY * (IRRows - 1)) $ int => int IRRow;
    (interpolatedMouseY * (IRRows - 1) - IRRow $ float) => float IRRowInterp;
    (IRRow >= IRRows) ? IRRows : IRRow => IRRow;
    
    (interpolatedMouseX * (IRCols - 1)) $ int => int IRCol;
    (interpolatedMouseX * (IRCols - 1) - IRCol $ float) => float IRColInterp;
    (IRCol >= IRCols) ? IRCols : IRCol => IRCol;
    
    if (GWindow.mouseLeftDown()) {
        IRs[IRRow][IRCol].gain((1 - IRRowInterp) * (1 - IRColInterp));
        IRs[IRRow][IRCol].pos(0);
        
        IRs[IRRow + 1][IRCol].gain(IRRowInterp * (1 - IRColInterp));
        IRs[IRRow + 1][IRCol].pos(0);
        
        IRs[IRRow][IRCol + 1].gain((1 - IRRowInterp) * IRColInterp);
        IRs[IRRow][IRCol + 1].pos(0);
        
        IRs[IRRow + 1][IRCol + 1].gain(IRRowInterp* IRColInterp);
        IRs[IRRow + 1][IRCol + 1].pos(0);
    }
}       

while (true) {
    GG.nextFrame() => now;
    updateMousePos();
    updateMouseVelocity();
    now / second => currentGraphicsFrameTimeSeconds;
    handleIRTrigger();
}

