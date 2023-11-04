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
module imgui.renderer.opengl33;

import bindbc.opengl : loadOpenGL, GLSupport;
import bindbc.opengl : GLint, GLuint, glBindTexture, glBindVertexArray,
    glBindBuffer, glBufferData, glDrawArrays, loadOpenGL,
    GL_TEXTURE_2D, GL_ARRAY_BUFFER, GL_STATIC_DRAW, GL_TRIANGLES, GLSupport,
    glDeleteTextures, glDeleteVertexArrays, glDeleteBuffers,
    glDeleteProgram, glViewport, glUseProgram, glActiveTexture,
    glUniform1f, glUniform2f, glUniform1i, glDisable, glEnable, glScissor,
    GL_TEXTURE0, GL_SCISSOR_TEST, glGenTextures, glTexImage2D, GL_RED,
    GL_UNSIGNED_BYTE, glTexParameteri, GL_TEXTURE_MIN_FILTER, GL_TEXTURE_MAG_FILTER,
    GL_LINEAR, glGenVertexArrays, glGenBuffers, glEnableVertexAttribArray,
    glVertexAttribPointer, GL_FLOAT, GL_FALSE, glCreateProgram, glCreateShader,
    glShaderSource, glCompileShader, glAttachShader, GL_VERTEX_SHADER, GL_FRAGMENT_SHADER,
    glBindAttribLocation, glLinkProgram, glGetProgramiv, glGetProgramInfoLog,
    glDeleteShader, glGetUniformLocation, glBindFragDataLocation,
    GL_LINK_STATUS, glGetError, GLenum, GL_NO_ERROR, GL_INVALID_ENUM,
    GL_INVALID_VALUE, GL_INVALID_OPERATION, GL_OUT_OF_MEMORY,
    glGetIntegerv, glGetShaderiv, GLchar, GLsizei, glGetShaderInfoLog, GL_COMPILE_STATUS, GLfloat;
import std.string : format;
import std.array : join;
import core.stdc.string : memset;
import imgui.api : TextAlign, Sizes;
import imgui.fonts : MAX_CHARACTER_COUNT, g_max_character_count,
    maxCharacterCount, FIRST_CHARACTER, g_cdata, getTextLength, g_tabStops;
import imgui.stdb_truetype : stbtt_bakedchar, stbtt_aligned_quad,
    stbtt_BakeFontBitmap, STBTT_ifloor;
import imgui.colorscheme : RGBA;
import imgui.engine : Command, Type;
import std.exception : enforce;
import std.file : read;
import std.math : sqrt, PI, cos, sin;
import std.algorithm : min;
import std.conv : to;

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

void checkOglErrors()
{
    string[] errors;
    GLenum error = glGetError();
    while (error != GL_NO_ERROR)
    {
        errors ~= "OGL error %s (%s)".format(error, glGetErrorString(error));
        error = glGetError();
    }
    if (errors.length > 0)
    {
        throw new Exception(errors.join("\n"));
    }
}

private string glGetErrorString(GLenum error)
{
    switch (error)
    {
    case GL_INVALID_ENUM:
        return "GL_INVALID_ENUM";
    case GL_INVALID_VALUE:
        return "GL_INVALID_VALUE";
    case GL_INVALID_OPERATION:
        return "GL_INVALID_OPERATION";
        //case GL_INVALID_FRAMEBUFFER_OPERATION:
        //return "GL_INVALID_FRAMEBUFFER_OPERATION";
    case GL_OUT_OF_MEMORY:
        return "GL_OUT_OF_MEMORY";
    default:
        throw new Exception("Unknown OpenGL error code %s".format(error));
    }
}

void checkShader(GLuint shader)
{
    GLint success;
    shader.glGetShaderiv(GL_COMPILE_STATUS, &success);
    checkOglErrors;
    if (!success)
    {
        GLchar[1024] infoLog;
        GLsizei logLen;
        shader.glGetShaderInfoLog(1024, &logLen, infoLog.ptr);
        checkOglErrors;

        auto errors = (infoLog[0 .. logLen - 1]).to!string;
        success.enforce("Error compiling shader\n  errors: '%s'".format(errors));
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

/++
 + Opengl33 Driver for api.ImGui(T)
 +/
public class Opengl33
{

    private enum uint FONT_TEXTURE_SIZE = 1024;

    private GLuint program = 0;
    private GLuint programViewportLocation = 0;
    private GLuint programTextureLocation = 0;
    private GLuint globalAlphaLocation = 0;
    private GLuint[3] vbos = [0, 0, 0];

    private enum int CIRCLE_VERTS = 8 * 4;
    private float[CIRCLE_VERTS * 2] circleVerts;
    private GLuint fontTexture = 0;
    private GLuint vao = 0;
    private GLuint whiteTexture = 0;

    private enum TEMP_COORD_COUNT = 100;

    private float[TEMP_COORD_COUNT * 12 + (TEMP_COORD_COUNT - 2) * 6] tempVertices;
    private float[TEMP_COORD_COUNT * 12 + (TEMP_COORD_COUNT - 2) * 6] tempTextureCoords;
    private float[TEMP_COORD_COUNT * 24 + (TEMP_COORD_COUNT - 2) * 12] tempColors;

    this(const(char)[] fontpath, const uint fontTextureSize)
    {
        {
            const result = loadOpenGL();
            (result == GLSupport.gl33).enforce("need opengl 3.3 support");
        }
        for (int i = 0; i < CIRCLE_VERTS; ++i)
        {
            float a = cast(float) i / cast(float) CIRCLE_VERTS * PI * 2;
            circleVerts[i * 2 + 0] = cos(a);
            circleVerts[i * 2 + 1] = sin(a);
        }

        // Load font.
        ubyte[] ttfBuffer = cast(ubyte[]) fontpath.read;
        ubyte[] bmap = new ubyte[FONT_TEXTURE_SIZE * FONT_TEXTURE_SIZE];

        const result = stbtt_BakeFontBitmap(ttfBuffer.ptr, 0, Sizes.TEXT_HEIGHT, bmap.ptr, FONT_TEXTURE_SIZE,
                FONT_TEXTURE_SIZE, FIRST_CHARACTER, g_max_character_count, g_cdata.ptr);
        // If result is negative, we baked less than max characters so update the max
        // character count.
        if (result < 0)
        {
            g_max_character_count = -result;
        }

        // can free ttf_buffer at this point
        glGenTextures(1, &fontTexture);
        glBindTexture(GL_TEXTURE_2D, fontTexture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RED, FONT_TEXTURE_SIZE,
                FONT_TEXTURE_SIZE, 0, GL_RED, GL_UNSIGNED_BYTE, bmap.ptr);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

        // can free ttf_buffer at this point
        ubyte white_alpha = 255;
        glGenTextures(1, &whiteTexture);
        glBindTexture(GL_TEXTURE_2D, whiteTexture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RED, 1, 1, 0, GL_RED, GL_UNSIGNED_BYTE, &white_alpha);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

        glGenVertexArrays(1, &vao);
        glGenBuffers(3, vbos.ptr);

        glBindVertexArray(vao);
        glEnableVertexAttribArray(0);
        glEnableVertexAttribArray(1);
        glEnableVertexAttribArray(2);

        glBindBuffer(GL_ARRAY_BUFFER, vbos[0]);
        glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, GL_FLOAT.sizeof * 2, null);
        glBufferData(GL_ARRAY_BUFFER, 0, null, GL_STATIC_DRAW);
        glBindBuffer(GL_ARRAY_BUFFER, vbos[1]);
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, GL_FLOAT.sizeof * 2, null);
        glBufferData(GL_ARRAY_BUFFER, 0, null, GL_STATIC_DRAW);
        glBindBuffer(GL_ARRAY_BUFFER, vbos[2]);
        glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, GL_FLOAT.sizeof * 4, null);
        glBufferData(GL_ARRAY_BUFFER, 0, null, GL_STATIC_DRAW);
        program = glCreateProgram();

        string vertexShader = `
#version 150
uniform vec2 viewport;
in vec2 vertexPosition;
in vec2 vertexTextureCoordinate;
in vec4 vertexColor;
out vec2 textureCoordinate;
out vec4 color;
void main(void)
{
    textureCoordinate = vertexTextureCoordinate;
    color = vertexColor;
    gl_Position = vec4(vertexPosition * 2.0 / viewport - 1.0, 0.f, 1.0);
}`;
        GLuint vertexShaderObject = glCreateShader(GL_VERTEX_SHADER);
        auto vertexShaderCStr = vertexShader.ptr;
        glShaderSource(vertexShaderObject, 1, &vertexShaderCStr, null);
        glCompileShader(vertexShaderObject);
        vertexShaderObject.checkShader;
        checkOglErrors;
        glAttachShader(program, vertexShaderObject);

        string fragmentShader = `
#version 150
in vec2 textureCoordinate;
in vec4 color;
uniform sampler2D sampler;
uniform float globalAlpha;
out vec4 fragmentColor;
void main(void)
{
    float alpha = texture(sampler, textureCoordinate).r;
    fragmentColor = vec4(color.rgb, color.a * alpha * globalAlpha);
}`;
        GLuint fragmentShaderObject = glCreateShader(GL_FRAGMENT_SHADER);

        auto fragmentShaderCStr = fragmentShader.ptr;
        glShaderSource(fragmentShaderObject, 1, &fragmentShaderCStr, null);
        glCompileShader(fragmentShaderObject);
        fragmentShaderObject.checkShader;
        checkOglErrors;
        glAttachShader(program, fragmentShaderObject);

        glBindAttribLocation(program, 0, "vertexPosition");
        glBindAttribLocation(program, 1, "vertexTexCoord");
        glBindAttribLocation(program, 2, "vertexColor");
        glBindFragDataLocation(program, 0, "fragmentColor");
        glLinkProgram(program);
        GLint success;
        program.glGetProgramiv(GL_LINK_STATUS, &success);
        if (success == 0)
        {
            static GLchar[1024] logBuff;
            static GLsizei logLen;
            program.glGetProgramInfoLog(logBuff.sizeof, &logLen, logBuff.ptr);
            throw new Exception("Error: linking program: %s".format(
                    logBuff[0 .. logLen - 1].to!string));
        }

        checkOglErrors;
        glDeleteShader(vertexShaderObject);
        glDeleteShader(fragmentShaderObject);

        glUseProgram(program);
        checkOglErrors;
        programViewportLocation = glGetUniformLocation(program, "viewport");
        programTextureLocation = glGetUniformLocation(program, "sampler");
        globalAlphaLocation = glGetUniformLocation(program, "globalAlpha");
        checkOglErrors;

        glUseProgram(0);
    }

    public ~this()
    {
        if (fontTexture)
        {
            glDeleteTextures(1, &fontTexture);
            fontTexture = 0;
        }

        if (vao)
        {
            glDeleteVertexArrays(1, &vao);
            glDeleteBuffers(3, vbos.ptr);
            vao = 0;
        }

        if (program)
        {
            glDeleteProgram(program);
            program = 0;
        }
    }

    public void render(Command[] commands, int width, int height)
    {
        glViewport(0, 0, width, height);
        glUseProgram(program);
        glActiveTexture(GL_TEXTURE0);
        glUniform2f(programViewportLocation, width, height);
        glUniform1i(programTextureLocation, 0);

        glDisable(GL_SCISSOR_TEST);

        foreach (ref cmd; commands)
        {
            final switch (cmd.type)
            {
            case Type.RECT:
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
                break;
            case Type.LINE:
                drawLine(cmd.line.x0, cmd.line.y0, cmd.line.x1, cmd.line.y1,
                        cmd.line.r, 1.0f, cmd.color);
                break;
            case Type.ARROW_DOWN:
                // dfmt off
                const float[3 * 2] verts =
                    [
                      cmd.rect.x + 0.5f, cmd.rect.y + 0.5f + cmd.rect.h - 1,
                      cmd.rect.x + 0.5f + cmd.rect.w / 2 - 0.5f, cmd.rect.y + 0.5f,
                      cmd.rect.x + 0.5f + cmd.rect.w - 1, cmd.rect.y + 0.5f + cmd.rect.h - 1,
                    ];
                // dfmt on
                drawPolygon(verts, 1.0f, cmd.color);
                break;
            case Type.ARROW_RIGHT:
                // dfmt off
                const float[3 * 2] verts =
                    [
                      cmd.rect.x + 0.5f, cmd.rect.y + 0.5f,
                      cmd.rect.x + 0.5f + cmd.rect.w - 1, cmd.rect.y + 0.5f + cmd.rect.h / 2 - 0.5f,
                      cmd.rect.x + 0.5f, cmd.rect.y + 0.5f + cmd.rect.h - 1,
                    ];
                // dfmt on
                drawPolygon(verts, 1.0f, cmd.color);
                break;
            case Type.TEXT:
                drawText(cmd.text.x, cmd.text.y, cmd.text.text,
                        cmd.text.align_, cmd.color);
                break;
            case Type.SCISSOR:
                glEnable(GL_SCISSOR_TEST);
                glScissor(cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h);
                break;
            case Type.DISABLE_SCISSOR:
                glDisable(GL_SCISSOR_TEST);
                break;
            case Type.GLOBAL_ALPHA:
                glUniform1f(globalAlphaLocation, cmd.alpha.alpha);
                break;
            }
        }

        glDisable(GL_SCISSOR_TEST);
    }

    private void drawLine(float x0, float y0, float x1, float y1, float r, float fth, uint col)
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

    private void drawRect(float x, float y, float w, float h, float fth, uint col)
    {
        const float[4 * 2] verts = [
            x + 0.5f, y + 0.5f, x + w - 0.5f, y + 0.5f, x + w - 0.5f, y + h - 0.5f,
            x + 0.5f, y + h - 0.5f,
        ];
        drawPolygon(verts, fth, col);
    }

    private void drawRoundedRect(float x, float y, float w, float h, float r, float fth, uint col)
    {
        const uint n = CIRCLE_VERTS / 4;
        float[(n + 1) * 4 * 2] verts;
        const(float)* cverts = circleVerts.ptr;
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

    private void drawText(float x, float y, const(char)[] text, int align_, uint color)
    {
        if (!fontTexture)
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
        glBindTexture(GL_TEXTURE_2D, fontTexture);

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
                getBakedQuad(g_cdata.ptr, FONT_TEXTURE_SIZE, FONT_TEXTURE_SIZE,
                        c - FIRST_CHARACTER, &x, &y, &q);

                float[12] v = [
                    q.x0, q.y0, q.x1, q.y1, q.x1, q.y0, q.x0, q.y0, q.x0, q.y1,
                    q.x1, q.y1,
                ];
                float[12] uv = [
                    q.s0, q.t0, q.s1, q.t1, q.s1, q.t0, q.s0, q.t0, q.s0, q.t1,
                    q.s1, q.t1,
                ];
                float[24] cArr = [
                    r, g, b, a, r, g, b, a, r, g, b, a, r, g, b, a, r, g, b, a, r,
                    g, b, a,
                ];
                glBindVertexArray(vao);
                glBindBuffer(GL_ARRAY_BUFFER, vbos[0]);
                glBufferData(GL_ARRAY_BUFFER, 12 * float.sizeof, v.ptr, GL_STATIC_DRAW);
                glBindBuffer(GL_ARRAY_BUFFER, vbos[1]);
                glBufferData(GL_ARRAY_BUFFER, 12 * float.sizeof, uv.ptr, GL_STATIC_DRAW);
                glBindBuffer(GL_ARRAY_BUFFER, vbos[2]);
                glBufferData(GL_ARRAY_BUFFER, 24 * float.sizeof, cArr.ptr, GL_STATIC_DRAW);
                glDrawArrays(GL_TRIANGLES, 0, 6);
            }
        }
    }

    private void drawPolygon(const(float)[] coords, float r, uint col)
    {
        const numCoords = min(TEMP_COORD_COUNT, coords.length / 2);

        const float[4] colf = [
            (col & 0xff) / 255.0f, ((col >> 8) & 0xff) / 255.0f,
            ((col >> 16) & 0xff) / 255.0f, ((col >> 24) & 0xff) / 255.0f
        ];
        const float[4] colTransf = [
            (col & 0xff) / 255.0f, ((col >> 8) & 0xff) / 255.0f, ((col >> 16) & 0xff) / 255.0f,
            0f
        ];

        int vSize = numCoords * 12 + (numCoords - 2) * 6;
        int uvSize = numCoords * 2 * 6 + (numCoords - 2) * 2 * 3;
        int cSize = numCoords * 4 * 6 + (numCoords - 2) * 4 * 3;
        float* ptrV = tempVertices.ptr;
        float* ptrC = tempColors.ptr;

        for (uint i = 0, j = numCoords - 1; i < numCoords; j = i++)
        {
            *ptrV = coords[i * 2];
            *(ptrV + 1) = coords[i * 2 + 1];
            ptrV += 2;
            *ptrV = coords[j * 2];
            *(ptrV + 1) = coords[j * 2 + 1];
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

        glBindTexture(GL_TEXTURE_2D, whiteTexture);

        glBindVertexArray(vao);
        glBindBuffer(GL_ARRAY_BUFFER, vbos[0]);
        glBufferData(GL_ARRAY_BUFFER, vSize * float.sizeof, tempVertices.ptr, GL_STATIC_DRAW);
        glBindBuffer(GL_ARRAY_BUFFER, vbos[1]);
        glBufferData(GL_ARRAY_BUFFER, uvSize * float.sizeof, tempTextureCoords.ptr, GL_STATIC_DRAW);
        glBindBuffer(GL_ARRAY_BUFFER, vbos[2]);
        glBufferData(GL_ARRAY_BUFFER, cSize * float.sizeof, tempColors.ptr, GL_STATIC_DRAW);
        glDrawArrays(GL_TRIANGLES, 0, (numCoords * 2 + numCoords - 2) * 3);
    }

}
