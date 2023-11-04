module imgui.fonts;

import imgui.stdb_truetype : stbtt_bakedchar, stbtt_aligned_quad,
    stbtt_BakeFontBitmap, STBTT_ifloor;

immutable float[4] g_tabStops = [150, 210, 270, 330];

enum MAX_CHARACTER_COUNT = 1024 * 16 * 4;
enum FIRST_CHARACTER = 32;
stbtt_bakedchar[MAX_CHARACTER_COUNT] g_cdata;

uint g_max_character_count = MAX_CHARACTER_COUNT;
uint maxCharacterCount() @trusted nothrow @nogc
{
    return g_max_character_count;
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
