
1.0/60.0 => float dt;

// 1,1 is top right
fun vec2 normalizedMousePos() {
    return @(GWindow.mousePos().x / GWindow.windowSize().x, 1 - GWindow.mousePos().y / GWindow.windowSize().y);
}

vec2 mouseVelocity;
vec2 prevMousePos;
fun void updateMouseVelocity() {
    normalizedMousePos() => vec2 currentMousePos;
    @((currentMousePos.x - prevMousePos.x) / dt, (currentMousePos.y - prevMousePos.y) / dt) => mouseVelocity;
    currentMousePos => prevMousePos;
}

fun printMousePosAndVelocity() {
    while (true) {
        <<< "mouse pos x " + normalizedMousePos().x >>>;
        <<< "mouse pos y " + normalizedMousePos().y>>>;
        <<< "mouse velocity x " + mouseVelocity.x >>>;
        <<< "mouse velocity y " + mouseVelocity.y>>>;
        0.1::second => now;
    }
} //spork ~printMousePosAndVelocity();


while (true) {
    GG.nextFrame() => now; 
    updateMouseVelocity();
}