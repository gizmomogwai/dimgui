/*
 * Copyright (c) 2009-2010 Mikko Mononen memon@inside.org
 *
 * This software is provided 'as-is', without any express or implied
 * warranty.  In no event will the authors be held liable for any damages
 * arising from the use of this software.
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 */
module imgui.gl3_renderer;

import bindbc.opengl : GLuint, glBindTexture, glBindVertexArray, glBindBuffer,
    glBufferData, glDrawArrays, loadOpenGL, GL_TEXTURE_2D,
    GL_ARRAY_BUFFER, GL_STATIC_DRAW, GL_TRIANGLES, GLSupport, glDeleteTextures,
    glDeleteVertexArrays, glDeleteBuffers, glDeleteProgram,
    glViewport, glUseProgram, glActiveTexture, glUniform2f, glUniform1i,
    glDisable, glEnable, glScissor, GL_TEXTURE0, GL_SCISSOR_TEST;
import core.stdc.stdlib : free, malloc;
import core.stdc.string : memset;
import imgui.api : RGBA, TextAlign;
import imgui.engine : GfxCmd, IMGUI_GFXCMD_RECT, IMGUI_GFXCMD_LINE,
    IMGUI_GFXCMD_TRIANGLE, IMGUI_GFXCMD_TEXT, IMGUI_GFXCMD_SCISSOR, Sizes;
import imgui.stdb_truetype : stbtt_bakedchar, stbtt_aligned_quad,
    stbtt_BakeFontBitmap, STBTT_ifloor;
import std.exception : enforce;
import std.file : read;
import std.math : sqrt, PI, cos, sin;
import std.algorithm : min;

private:
// Draw up to 65536 unicode glyphs.  What this will actually do is draw *only glyphs the
// font supports* until it will run out of glyphs or texture space (determined by
// g_font_texture_size).  The actual number of glyphs will be in thousands (ASCII is
// guaranteed, the rest will depend mainly on what the font supports, e.g. if it
// supports common European characters such as á or š they will be there because they
// are "early" in Unicode)
//
// Note that g_cdata uses memory of stbtt_bakedchar.sizeof * MAX_CHARACTER_COUNT which
// at the moment is 20 * 65536 or 1.25 MiB.
enum MAX_CHARACTER_COUNT = 1024 * 16 * 4;
enum FIRST_CHARACTER = 32;

/** Globals start. */

// A 1024x1024 font texture takes 1MiB of memory, and should be enough for thousands of
// glyphs (at the fixed 15.0f size imgui uses).
//
// Some examples:
//
// =================================================== ============ =============================
// Font                                                Texture size Glyps fit
// =================================================== ============ =============================
// GentiumPlus-R                                       512x512      2550 (all glyphs in the font)
// GentiumPlus-R                                       256x256      709
// DroidSans (the small version included for examples) 512x512      903 (all glyphs in the font)
// DroidSans (the small version included for examples) 256x256      497
// =================================================== ============ =============================
//
// This was measured after the optimization to reuse null character glyph, which is in
// BakeFontBitmap in stdb_truetype.d
uint g_font_texture_size = 1024;
float[TEMP_COORD_COUNT * 2] g_tempCoords;
float[TEMP_COORD_COUNT * 2] g_tempNormals;
float[TEMP_COORD_COUNT * 12 + (TEMP_COORD_COUNT - 2) * 6] g_tempVertices;
float[TEMP_COORD_COUNT * 12 + (TEMP_COORD_COUNT - 2) * 6] g_tempTextureCoords;
float[TEMP_COORD_COUNT * 24 + (TEMP_COORD_COUNT - 2) * 12] g_tempColors;
float[CIRCLE_VERTS * 2] g_circleVerts;
uint g_max_character_count = MAX_CHARACTER_COUNT;
stbtt_bakedchar[MAX_CHARACTER_COUNT] g_cdata;
GLuint g_ftex = 0;
GLuint g_whitetex = 0;
GLuint g_vao = 0;
GLuint[3] g_vbos = [0, 0, 0];
GLuint g_program = 0;
GLuint g_programViewportLocation = 0;
GLuint g_programTextureLocation = 0;

/** Globals end. */

enum TEMP_COORD_COUNT = 100;
enum int CIRCLE_VERTS = 8 * 4;
immutable float[4] g_tabStops = [150, 210, 270, 330];

package:

uint maxCharacterCount() @trusted nothrow @nogc
{
    return g_max_character_count;
}

void imguifree(void* ptr, void*  /*userptr*/ )
{
    free(ptr);
}

void* imguimalloc(size_t size, void*  /*userptr*/ )
{
    return malloc(size);
}

uint toPackedRGBA(RGBA color)
{
    // dfmt off
    return
        (color.r <<  0) |
        (color.g <<  8) |
        (color.b << 16) |
        (color.a << 24);
    // dfmt on
}

void drawPolygon(const(float)[] coords, float r, uint col)
{
    const numCoords = min(TEMP_COORD_COUNT, coords.length / 2);

    for (uint i = 0, j = numCoords - 1; i < numCoords; j = i++)
    {
        const(float)* v0 = &coords[j * 2];
        const(float)* v1 = &coords[i * 2];
        float dx = v1[0] - v0[0];
        float dy = v1[1] - v0[1];
        float d = sqrt(dx * dx + dy * dy);

        if (d > 0)
        {
            d = 1.0f / d;
            dx *= d;
            dy *= d;
        }
        g_tempNormals[j * 2 + 0] = dy;
        g_tempNormals[j * 2 + 1] = -dx;
    }

    const float[4] colf = [
        (col & 0xff) / 255.0f, ((col >> 8) & 0xff) / 255.0f,
        ((col >> 16) & 0xff) / 255.0f, ((col >> 24) & 0xff) / 255.0f
    ];
    const float[4] colTransf = [
        (col & 0xff) / 255.0f, ((col >> 8) & 0xff) / 255.0f, ((col >> 16) & 0xff) / 255.0f,
        0f
    ];

    for (uint i = 0, j = numCoords - 1; i < numCoords; j = i++)
    {
        float dlx0 = g_tempNormals[j * 2 + 0];
        float dly0 = g_tempNormals[j * 2 + 1];
        float dlx1 = g_tempNormals[i * 2 + 0];
        float dly1 = g_tempNormals[i * 2 + 1];
        float dmx = (dlx0 + dlx1) * 0.5f;
        float dmy = (dly0 + dly1) * 0.5f;
        float dmr2 = dmx * dmx + dmy * dmy;

        if (dmr2 > 0.000001f)
        {
            float scale = 1.0f / dmr2;

            if (scale > 10.0f)
                scale = 10.0f;
            dmx *= scale;
            dmy *= scale;
        }
        g_tempCoords[i * 2 + 0] = coords[i * 2 + 0] + dmx * r;
        g_tempCoords[i * 2 + 1] = coords[i * 2 + 1] + dmy * r;
    }

    int vSize = numCoords * 12 + (numCoords - 2) * 6;
    int uvSize = numCoords * 2 * 6 + (numCoords - 2) * 2 * 3;
    int cSize = numCoords * 4 * 6 + (numCoords - 2) * 4 * 3;
    float* v = g_tempVertices.ptr;
    float* uv = g_tempTextureCoords.ptr;
    memset(uv, 0, uvSize * float.sizeof);
    float* c = g_tempColors.ptr;
    memset(c, 1, cSize * float.sizeof);

    float* ptrV = v;
    float* ptrC = c;

    for (uint i = 0, j = numCoords - 1; i < numCoords; j = i++)
    {
        *ptrV = coords[i * 2];
        *(ptrV + 1) = coords[i * 2 + 1];
        ptrV += 2;
        *ptrV = coords[j * 2];
        *(ptrV + 1) = coords[j * 2 + 1];
        ptrV += 2;
        *ptrV = g_tempCoords[j * 2];
        *(ptrV + 1) = g_tempCoords[j * 2 + 1];
        ptrV += 2;
        *ptrV = g_tempCoords[j * 2];
        *(ptrV + 1) = g_tempCoords[j * 2 + 1];
        ptrV += 2;
        *ptrV = g_tempCoords[i * 2];
        *(ptrV + 1) = g_tempCoords[i * 2 + 1];
        ptrV += 2;
        *ptrV = coords[i * 2];
        *(ptrV + 1) = coords[i * 2 + 1];
        ptrV += 2;

        *ptrC = colf[0];
        *(ptrC + 1) = colf[1];
        *(ptrC + 2) = colf[2];
        *(ptrC + 3) = colf[3];
        ptrC += 4;
        *ptrC = colf[0];
        *(ptrC + 1) = colf[1];
        *(ptrC + 2) = colf[2];
        *(ptrC + 3) = colf[3];
        ptrC += 4;
        *ptrC = colTransf[0];
        *(ptrC + 1) = colTransf[1];
        *(ptrC + 2) = colTransf[2];
        *(ptrC + 3) = colTransf[3];
        ptrC += 4;
        *ptrC = colTransf[0];
        *(ptrC + 1) = colTransf[1];
        *(ptrC + 2) = colTransf[2];
        *(ptrC + 3) = colTransf[3];
        ptrC += 4;
        *ptrC = colTransf[0];
        *(ptrC + 1) = colTransf[1];
        *(ptrC + 2) = colTransf[2];
        *(ptrC + 3) = colTransf[3];
        ptrC += 4;
        *ptrC = colf[0];
        *(ptrC + 1) = colf[1];
        *(ptrC + 2) = colf[2];
        *(ptrC + 3) = colf[3];
        ptrC += 4;
    }

    for (uint i = 2; i < numCoords; ++i)
    {
        *ptrV = coords[0];
        *(ptrV + 1) = coords[1];
        ptrV += 2;
        *ptrV = coords[(i - 1) * 2];
        *(ptrV + 1) = coords[(i - 1) * 2 + 1];
        ptrV += 2;
        *ptrV = coords[i * 2];
        *(ptrV + 1) = coords[i * 2 + 1];
        ptrV += 2;

        *ptrC = colf[0];
        *(ptrC + 1) = colf[1];
        *(ptrC + 2) = colf[2];
        *(ptrC + 3) = colf[3];
        ptrC += 4;
        *ptrC = colf[0];
        *(ptrC + 1) = colf[1];
        *(ptrC + 2) = colf[2];
        *(ptrC + 3) = colf[3];
        ptrC += 4;
        *ptrC = colf[0];
        *(ptrC + 1) = colf[1];
        *(ptrC + 2) = colf[2];
        *(ptrC + 3) = colf[3];
        ptrC += 4;
    }

    glBindTexture(GL_TEXTURE_2D, g_whitetex);

    glBindVertexArray(g_vao);
    glBindBuffer(GL_ARRAY_BUFFER, g_vbos[0]);
    glBufferData(GL_ARRAY_BUFFER, vSize * float.sizeof, v, GL_STATIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, g_vbos[1]);
    glBufferData(GL_ARRAY_BUFFER, uvSize * float.sizeof, uv, GL_STATIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, g_vbos[2]);
    glBufferData(GL_ARRAY_BUFFER, cSize * float.sizeof, c, GL_STATIC_DRAW);
    glDrawArrays(GL_TRIANGLES, 0, (numCoords * 2 + numCoords - 2) * 3);
}

void drawRect(float x, float y, float w, float h, float fth, uint col)
{
    const float[4 * 2] verts = [
        x + 0.5f, y + 0.5f, x + w - 0.5f, y + 0.5f, x + w - 0.5f, y + h - 0.5f,
        x + 0.5f, y + h - 0.5f,
    ];
    drawPolygon(verts, fth, col);
}

/*
   void drawEllipse(float x, float y, float w, float h, float fth, uint col)
   {
        float verts[CIRCLE_VERTS*2];
        const(float)* cverts = g_circleVerts;
        float* v = verts;

        for (int i = 0; i < CIRCLE_VERTS; ++i)
        {
 * v++ = x + cverts[i*2]*w;
 * v++ = y + cverts[i*2+1]*h;
        }

        drawPolygon(verts, CIRCLE_VERTS, fth, col);
   }
 */

void drawRoundedRect(float x, float y, float w, float h, float r, float fth, uint col)
{
    const uint n = CIRCLE_VERTS / 4;
    float[(n + 1) * 4 * 2] verts;
    const(float)* cverts = g_circleVerts.ptr;
    float* v = verts.ptr;

    for (uint i = 0; i <= n; ++i)
    {
        *v++ = x + w - r + cverts[i * 2] * r;
        *v++ = y + h - r + cverts[i * 2 + 1] * r;
    }

    for (uint i = n; i <= n * 2; ++i)
    {
        *v++ = x + r + cverts[i * 2] * r;
        *v++ = y + h - r + cverts[i * 2 + 1] * r;
    }

    for (uint i = n * 2; i <= n * 3; ++i)
    {
        *v++ = x + r + cverts[i * 2] * r;
        *v++ = y + r + cverts[i * 2 + 1] * r;
    }

    for (uint i = n * 3; i < n * 4; ++i)
    {
        *v++ = x + w - r + cverts[i * 2] * r;
        *v++ = y + r + cverts[i * 2 + 1] * r;
    }

    *v++ = x + w - r + cverts[0] * r;
    *v++ = y + r + cverts[1] * r;

    drawPolygon(verts, fth, col);
}

void drawLine(float x0, float y0, float x1, float y1, float r, float fth, uint col)
{
    float dx = x1 - x0;
    float dy = y1 - y0;
    float d = sqrt(dx * dx + dy * dy);

    if (d > 0.0001f)
    {
        d = 1.0f / d;
        dx *= d;
        dy *= d;
    }
    float nx = dy;
    float ny = -dx;
    float[4 * 2] verts;
    r -= fth;
    r *= 0.5f;

    if (r < 0.01f)
        r = 0.01f;
    dx *= r;
    dy *= r;
    nx *= r;
    ny *= r;

    verts[0] = x0 - dx - nx;
    verts[1] = y0 - dy - ny;

    verts[2] = x0 - dx + nx;
    verts[3] = y0 - dy + ny;

    verts[4] = x1 + dx + nx;
    verts[5] = y1 + dy + ny;

    verts[6] = x1 + dx - nx;
    verts[7] = y1 + dy - ny;

    drawPolygon(verts, fth, col);
}

void loadBindBCOpenGL()
{
    const result = loadOpenGL();

    (result == GLSupport.gl33).enforce("need opengl 3.3 support");
}

bool imguiRenderGLInit(const(char)[] fontpath, const uint fontTextureSize)
{
    import bindbc.opengl;

    loadBindBCOpenGL();
    for (int i = 0; i < CIRCLE_VERTS; ++i)
    {
        float a = cast(float) i / cast(float) CIRCLE_VERTS * PI * 2;
        g_circleVerts[i * 2 + 0] = cos(a);
        g_circleVerts[i * 2 + 1] = sin(a);
    }

    // Load font.
    ubyte[] ttfBuffer = cast(ubyte[]) fontpath.read;
    ubyte[] bmap = new ubyte[g_font_texture_size * g_font_texture_size];

    const result = stbtt_BakeFontBitmap(ttfBuffer.ptr, 0, Sizes.TEXT_HEIGHT, bmap.ptr, g_font_texture_size,
            g_font_texture_size, FIRST_CHARACTER, g_max_character_count, g_cdata.ptr);
    // If result is negative, we baked less than max characters so update the max
    // character count.
    if (result < 0)
    {
        g_max_character_count = -result;
    }

    // can free ttf_buffer at this point
    glGenTextures(1, &g_ftex);
    glBindTexture(GL_TEXTURE_2D, g_ftex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RED, g_font_texture_size,
            g_font_texture_size, 0, GL_RED, GL_UNSIGNED_BYTE, bmap.ptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

    // can free ttf_buffer at this point
    ubyte white_alpha = 255;
    glGenTextures(1, &g_whitetex);
    glBindTexture(GL_TEXTURE_2D, g_whitetex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RED, 1, 1, 0, GL_RED, GL_UNSIGNED_BYTE, &white_alpha);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

    glGenVertexArrays(1, &g_vao);
    glGenBuffers(3, g_vbos.ptr);

    glBindVertexArray(g_vao);
    glEnableVertexAttribArray(0);
    glEnableVertexAttribArray(1);
    glEnableVertexAttribArray(2);

    glBindBuffer(GL_ARRAY_BUFFER, g_vbos[0]);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, GL_FLOAT.sizeof * 2, null);
    glBufferData(GL_ARRAY_BUFFER, 0, null, GL_STATIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, g_vbos[1]);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, GL_FLOAT.sizeof * 2, null);
    glBufferData(GL_ARRAY_BUFFER, 0, null, GL_STATIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, g_vbos[2]);
    glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, GL_FLOAT.sizeof * 4, null);
    glBufferData(GL_ARRAY_BUFFER, 0, null, GL_STATIC_DRAW);
    g_program = glCreateProgram();

    string vs = `
#version 150
uniform vec2 Viewport;
in vec2 VertexPosition;
in vec2 VertexTexCoord;
in vec4 VertexColor;
out vec2 texCoord;
out vec4 vertexColor;
void main(void)
{
    vertexColor = VertexColor;
    texCoord = VertexTexCoord;
    gl_Position = vec4(VertexPosition * 2.0 / Viewport - 1.0, 0.f, 1.0);
}`;
    GLuint vso = glCreateShader(GL_VERTEX_SHADER);
    auto vsPtr = vs.ptr;
    glShaderSource(vso, 1, &vsPtr, null);
    glCompileShader(vso);
    glAttachShader(g_program, vso);

    string fs = `
#version 150
in vec2 texCoord;
in vec4 vertexColor;
uniform sampler2D Texture;
out vec4  Color;
void main(void)
{
    float alpha = texture(Texture, texCoord).r;
    Color = vec4(vertexColor.rgb, vertexColor.a * alpha);
}`;
    GLuint fso = glCreateShader(GL_FRAGMENT_SHADER);

    auto fsPtr = fs.ptr;
    glShaderSource(fso, 1, &fsPtr, null);
    glCompileShader(fso);
    glAttachShader(g_program, fso);

    glBindAttribLocation(g_program, 0, "VertexPosition");
    glBindAttribLocation(g_program, 1, "VertexTexCoord");
    glBindAttribLocation(g_program, 2, "VertexColor");
    glBindFragDataLocation(g_program, 0, "Color");
    glLinkProgram(g_program);
    glDeleteShader(vso);
    glDeleteShader(fso);

    glUseProgram(g_program);
    g_programViewportLocation = glGetUniformLocation(g_program, "Viewport");
    g_programTextureLocation = glGetUniformLocation(g_program, "Texture");

    glUseProgram(0);

    return true;
}

void imguiRenderGLDestroy()
{
    if (g_ftex)
    {
        glDeleteTextures(1, &g_ftex);
        g_ftex = 0;
    }

    if (g_vao)
    {
        glDeleteVertexArrays(1, &g_vao);
        glDeleteBuffers(3, g_vbos.ptr);
        g_vao = 0;
    }

    if (g_program)
    {
        glDeleteProgram(g_program);
        g_program = 0;
    }
}

void getBakedQuad(stbtt_bakedchar* chardata, int pw, int ph, int char_index,
        float* xpos, float* ypos, stbtt_aligned_quad* q)
{
    stbtt_bakedchar* b = chardata + char_index;
    int round_x = STBTT_ifloor(*xpos + b.xoff);
    int round_y = STBTT_ifloor(*ypos - b.yoff);

    q.x0 = round_x;
    q.y0 = round_y;
    q.x1 = round_x + b.x1 - b.x0;
    q.y1 = round_y - b.y1 + b.y0;

    q.s0 = b.x0 / cast(float) pw;
    q.t0 = b.y0 / cast(float) pw;
    q.s1 = b.x1 / cast(float) ph;
    q.t1 = b.y1 / cast(float) ph;

    *xpos += b.xadvance;
}

float getTextLength(stbtt_bakedchar* chardata, const(char)[] text)
{
    float xpos = 0;
    float len = 0;

    // The cast(string) is only there for UTF-8 decoding.
    foreach (dchar c; cast(string) text)
    {
        if (c == '\t')
        {
            for (int i = 0; i < 4; ++i)
            {
                if (xpos < g_tabStops[i])
                {
                    xpos = g_tabStops[i];
                    break;
                }
            }
        }
        else if (cast(int) c >= FIRST_CHARACTER
                && cast(int) c < FIRST_CHARACTER + g_max_character_count)
        {
            stbtt_bakedchar* b = chardata + c - FIRST_CHARACTER;
            int round_x = STBTT_ifloor((xpos + b.xoff) + 0.5);
            len = round_x + b.x1 - b.x0 + 0.5f;
            xpos += b.xadvance;
        }
    }

    return len;
}

float getTextLength(const(char)[] text)
{
    return getTextLength(g_cdata.ptr, text);
}

void drawText(float x, float y, const(char)[] text, int align_, uint color)
{
    if (!g_ftex)
        return;

    if (!text)
        return;

    if (align_ == TextAlign.center)
        x -= getTextLength(g_cdata.ptr, text) / 2;
    else if (align_ == TextAlign.right)
        x -= getTextLength(g_cdata.ptr, text);

    const r = (color & 0xff) / 255.0f;
    const g = ((color >> 8) & 0xff) / 255.0f;
    const b = ((color >> 16) & 0xff) / 255.0f;
    const a = ((color >> 24) & 0xff) / 255.0f;

    // assume orthographic projection with units = screen pixels, origin at top left
    glBindTexture(GL_TEXTURE_2D, g_ftex);

    const float ox = x;

    // The cast(string) is only there for UTF-8 decoding.
    //foreach (ubyte c; cast(ubyte[])text)
    foreach (dchar c; cast(string) text)
    {
        if (c == '\t')
        {
            for (int i = 0; i < 4; ++i)
            {
                if (x < g_tabStops[i] + ox)
                {
                    x = g_tabStops[i] + ox;
                    break;
                }
            }
        }
        else if (c >= FIRST_CHARACTER && c < FIRST_CHARACTER + g_max_character_count)
        {
            stbtt_aligned_quad q;
            getBakedQuad(g_cdata.ptr, g_font_texture_size, g_font_texture_size,
                    c - FIRST_CHARACTER, &x, &y, &q);

            float[12] v = [
                q.x0, q.y0, q.x1, q.y1, q.x1, q.y0, q.x0, q.y0, q.x0, q.y1, q.x1,
                q.y1,
            ];
            float[12] uv = [
                q.s0, q.t0, q.s1, q.t1, q.s1, q.t0, q.s0, q.t0, q.s0, q.t1, q.s1,
                q.t1,
            ];
            float[24] cArr = [
                r, g, b, a, r, g, b, a, r, g, b, a, r, g, b, a, r, g, b, a, r, g,
                b, a,
            ];
            glBindVertexArray(g_vao);
            glBindBuffer(GL_ARRAY_BUFFER, g_vbos[0]);
            glBufferData(GL_ARRAY_BUFFER, 12 * float.sizeof, v.ptr, GL_STATIC_DRAW);
            glBindBuffer(GL_ARRAY_BUFFER, g_vbos[1]);
            glBufferData(GL_ARRAY_BUFFER, 12 * float.sizeof, uv.ptr, GL_STATIC_DRAW);
            glBindBuffer(GL_ARRAY_BUFFER, g_vbos[2]);
            glBufferData(GL_ARRAY_BUFFER, 24 * float.sizeof, cArr.ptr, GL_STATIC_DRAW);
            glDrawArrays(GL_TRIANGLES, 0, 6);
        }
    }
}

void renderGLDraw(GfxCmd[] commands, int width, int height)
{
    glViewport(0, 0, width, height);
    glUseProgram(g_program);
    glActiveTexture(GL_TEXTURE0);
    glUniform2f(g_programViewportLocation, width, height);
    glUniform1i(g_programTextureLocation, 0);

    glDisable(GL_SCISSOR_TEST);

    foreach (ref cmd; commands)
    {
        if (cmd.type == IMGUI_GFXCMD_RECT)
        {
            auto y = cmd.rect.y + 0.5f;
            auto h = cmd.rect.h - 1;

            if (cmd.rect.r == 0)
            {
                drawRect(cmd.rect.x + 0.5f, y, cmd.rect.w - 1, h, 1.0f, cmd.color);
            }
            else
            {
                drawRoundedRect(cmd.rect.x + 0.5f, y, cmd.rect.w - 1, h,
                        cmd.rect.r, 1.0f, cmd.color);
            }
        }
        else if (cmd.type == IMGUI_GFXCMD_LINE)
        {
            drawLine(cmd.line.x0, cmd.line.y0, cmd.line.x1, cmd.line.y1,
                    cmd.line.r, 1.0f, RGBA(255, 0, 0, 255).toPackedRGBA); //cmd.color);
        }
        else if (cmd.type == IMGUI_GFXCMD_TRIANGLE)
        {
            if (cmd.flags == 1)
            {
                const float[3 * 2] verts = [
                    cmd.rect.x + 0.5f, cmd.rect.y + 0.5f,
                    cmd.rect.x + 0.5f + cmd.rect.w - 1,
                    cmd.rect.y + 0.5f + cmd.rect.h / 2 - 0.5f, cmd.rect.x + 0.5f,
                    cmd.rect.y + 0.5f + cmd.rect.h - 1,
                ];
                drawPolygon(verts, 1.0f, cmd.color);
            }

            if (cmd.flags == 2)
            {
                const float[3 * 2] verts = [
                    cmd.rect.x + 0.5f, cmd.rect.y + 0.5f + cmd.rect.h - 1,
                    cmd.rect.x + 0.5f + cmd.rect.w / 2 - 0.5f, cmd.rect.y + 0.5f,
                    cmd.rect.x + 0.5f + cmd.rect.w - 1,
                    cmd.rect.y + 0.5f + cmd.rect.h - 1,
                ];
                drawPolygon(verts, 1.0f, cmd.color);
            }
        }
        else if (cmd.type == IMGUI_GFXCMD_TEXT)
        {
            drawText(cmd.text.x, cmd.text.y, cmd.text.text, cmd.text.align_, cmd.color);
        }
        else if (cmd.type == IMGUI_GFXCMD_SCISSOR)
        {
            if (cmd.flags)
            {
                glEnable(GL_SCISSOR_TEST);
                glScissor(cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h);
            }
            else
            {
                glDisable(GL_SCISSOR_TEST);
            }
        }
    }

    glDisable(GL_SCISSOR_TEST);
}
