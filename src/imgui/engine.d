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
module imgui.engine;

import std.math;
import std.stdio;
import std.string;

import imgui.api;
import imgui.gl3_renderer;

package:

enum GFXCMD_QUEUE_SIZE = 5000;
enum BUTTON_HEIGHT = 60;
enum SLIDER_HEIGHT = 40;
enum SLIDER_MARKER_WIDTH = 10;
enum CHECK_SIZE = 8;
enum DEFAULT_SPACING = 4;
enum TEXT_HEIGHT = 35;
enum TEXT_BASELINE = 5;
enum SCROLL_AREA_PADDING = 6;
enum SCROLL_BAR_SIZE = SCROLL_AREA_PADDING * 3;
enum SCROLL_BAR_HANDLE_SIZE = SCROLL_AREA_PADDING * 2;
enum INDENT_SIZE = 16;
enum AREA_HEADER = 35;

// Pull render interface.
alias imguiGfxCmdType = int;
enum : imguiGfxCmdType
{
    IMGUI_GFXCMD_RECT,
    IMGUI_GFXCMD_TRIANGLE,
    IMGUI_GFXCMD_LINE,
    IMGUI_GFXCMD_TEXT,
    IMGUI_GFXCMD_SCISSOR,
}

struct imguiGfxRect
{
    short x, y, w, h, r;
}

struct imguiGfxText
{
    short x, y, align_;
    const(char)[] text;
}

struct imguiGfxLine
{
    short x0, y0, x1, y1, r;
}

struct GfxCmd
{
    char type;
    char flags;
    byte[2] pad;
    uint color;

    union
    {
        imguiGfxLine line;
        imguiGfxRect rect;
        imguiGfxText text;
    }
}

struct GuiState
{
public:
    bool left;
    bool leftPressed, leftReleased;
    MouseInfo mouseInfo = MouseInfo(-1, -1, 0, 0, 0);
    // 'unicode' value passed to updateInput.
    dchar unicode;
    // 'unicode' value passed to updateInput on previous frame.
    //
    // Used to detect that unicode (text) input has changed.
    dchar lastUnicode;
    // ID of the 'inputable' widget (widget we're entering input into, e.g. text input).
    //
    // A text input becomes 'inputable' when it is 'hot' and left-clicked.
    //
    // 0 if no widget is inputable
    uint inputable;
    uint active;
    // The 'hot' widget (hovered over input widget).
    //
    // 0 if no widget is inputable
    uint hot;
    // The widget that will be 'hot' in the next frame.
    uint hotToBe;
    // These two are probably unused? (set but not read?)
    bool isHot;
    bool isActive;

    bool wentActive;
    int dragX, dragY;
    float dragOrigX, dragOrigY;
    int widgetX, widgetY, widgetW = 100;
    bool insideCurrentScroll;

    uint areaId;
    uint widgetId;
    bool anyActive()
    {
        return active != 0;
    }

    bool isIdActive(uint id)
    {
        return active == id;
    }

    /// Is the widget with specified ID 'inputable' for e.g. text input?
    bool isIdInputable(uint id)
    {
        return inputable == id;
    }

    bool isIdHot(uint id)
    {
        return hot == id;
    }

    bool inRect(int x, int y, int w, int h, bool checkScroll = true)
    {
        // dfmt off
        return (!checkScroll || insideCurrentScroll)
            && mouseInfo.x >= x && mouseInfo.x <= x + w
            && mouseInfo.y >= y  && mouseInfo.y <= y + h;
        // dfmt on
    }

    void clearInput()
    {
        leftPressed = false;
        leftReleased = false;
        mouseInfo.reset();
    }

    void clearActive()
    {
        active = 0;

        // mark all UI for this frame as processed
        clearInput();
    }

    void setActive(uint id)
    {
        active = id;
        inputable = 0;
        wentActive = true;
    }

    // Set the inputable widget to the widget with specified ID.
    //
    // A text input becomes 'inputable' when it is 'hot' and left-clicked.
    //
    // 0 if no widget is inputable
    void setInputable(uint id)
    {
        inputable = id;
    }

    void setHot(uint id)
    {
        hotToBe = id;
    }

    bool buttonLogic(uint id, bool over)
    {
        bool res = false;

        // process down
        if (!anyActive())
        {
            if (over)
                setHot(id);

            if (isIdHot(id) && leftPressed)
                setActive(id);
        }

        // if button is active, then react on left up
        if (isIdActive(id))
        {
            isActive = true;

            if (over)
                setHot(id);

            if (leftReleased)
            {
                if (isIdHot(id))
                    res = true;
                clearActive();
            }
        }

        // Not sure if this does anything (g_state.isHot doesn't seem to be used).
        if (isIdHot(id))
            isHot = true;

        return res;
    }

    /** Input logic for text input fields.
 *
 * Params:
 *
 * id             = ID of the text input widget
 * over           = Is the mouse hovering over the text input widget?
 * forceInputable = Force the text input widget to be inputable regardless of whether it's
 *                  hovered and clicked by the mouse or not.
 */
    void textInputLogic(uint id, bool over, bool forceInputable)
    {
        // If nothing else is active, we check for mouse over to make the widget hot in the
        // next frame, and if both hot and LMB is pressed (or forced), make it inputable.
        if (!anyActive())
        {
            if (over)
            {
                setHot(id);
            }
            if (forceInputable || isIdHot(id) && leftPressed)
            {
                setInputable(id);
            }
        }
        // Not sure if this does anything (g_state.isHot doesn't seem to be used).
        if (isIdHot(id))
        {
            isHot = true;
        }
    }

    /* Update user input on the beginning of a frame.
 *
 * Params:
 *
 * mx          = Mouse X position.
 * my          = Mouse Y position.
 * mbut        = Mouse buttons pressed (a combination of values of a $(D MouseButton)).
 * scroll      = Mouse wheel movement.
 * unicodeChar = Unicode text input from the keyboard (usually the unicode result of last
 *               keypress).
 */
    void updateInput(MouseInfo mouseInfo, dchar unicodeChar)
    {
        bool left = (mouseInfo.buttons & MouseButton.left) != 0;

        this.mouseInfo = mouseInfo;
        this.leftPressed = !this.left && left;
        this.leftReleased = this.left && !left;
        this.left = left;

        // Ignore characters we can't draw
        if (unicodeChar > maxCharacterCount())
        {
            unicodeChar = 0;
        }
        this.lastUnicode = this.unicode;
        this.unicode = unicodeChar;
    }

    // Separate from gl3_renderer.getTextLength so api doesn't directly call renderer.
    float getTextLength(const(char)[] text)
    {
        return imgui.gl3_renderer.getTextLength(text);
    }
}
