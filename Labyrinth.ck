
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

// Noise parameters
10.0 => float freq;
1.0  => float amp;
2.0  => float lac;
0.5  => float gain;

fun setUniforms()
{
    mat.uniformFloat(0, freq);
    mat.uniformFloat(1, amp );
    mat.uniformFloat(2, lac );
    mat.uniformFloat(3, gain);
}
setUniforms();

UI_Float f(freq);
UI_Float a(amp);
UI_Float l(lac);
UI_Float g(gain);

while (true)
{
    GG.nextFrame() => now;

    if (UI.begin("Noise Parameters")) {
        false => int update;
        if (UI.slider("Frequency",  f, 1.0, 100.0)) { f.val() => freq; true => update; }
        if (UI.slider("Amplitude",  a, 0.0, 1.0  )) { a.val() => amp;  true => update; }
        if (UI.slider("Lacunarity", l, 1.0, 3.0  )) { l.val() => lac;  true => update; }
        if (UI.slider("Gain",       g, 0.0, 1.0  )) { g.val() => gain; true => update; }
        
        if (update) { setUniforms(); }
    }
}
