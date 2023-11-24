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

import imgui.api : MouseInfo, MouseButton, Sizes, Layout, HotKey;
import std.range : popBack, empty;

package:

// Pull render interface.
enum Type
{
    RECT,
    ARROW_DOWN,
    ARROW_RIGHT,
    LINE,
    TEXT,
    SCISSOR,
    DISABLE_SCISSOR,
    GLOBAL_ALPHA,
}

struct Rect
{
    int x, y, w, h, r;
}

struct Vector2i
{
    int x;
    int y;
}

struct Vector2f
{
    float x;
    float y;
}

struct Text
{
    int x, y, align_;
    string text;
}

struct Line
{
    int x0, y0, x1, y1, r;
    bool outside(int height)
    {
        return (y0 < 0 && y1 < 0) || (y0 > height && y1 > height);
    }
}

struct GlobalAlpha
{
    float alpha;
}

struct Command
{
    Type type;
    uint color;
    union
    {
        Line line;
        Rect rect;
        Text text;
        GlobalAlpha alpha;
    }
}

struct GuiState
{
public:
    int width;
    int height;
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

    bool wentActive;
    Vector2i drag;
    Vector2f dragOrigin;
    int widgetX;
    int widgetY;
    int widgetW = 100;
    bool insideCurrentScroll;

    uint areaId;
    uint widgetId;
    bool inScroll;

    Layout[] layoutStack;

    HotKey[] hotkeys;

    void clearHotkeys()
    {
        hotkeys.length = 0;
        hotkeys.assumeSafeAppend();
    }

    void add(HotKey hotkey)
    {
        hotkeys ~= hotkey;
    }

    void pushLayout(Layout l)
    {
        l.push(this);
        layoutStack.assumeSafeAppend() ~= l;
    }

    void popLayout()
    {
        layoutStack[$ - 1].pop(this);
        layoutStack.popBack();
    }

    Layout layout()
    {
        return layoutStack[$ - 1];
    }

    bool anyActive()
    {
        return active != 0;
    }

    bool isIdActive(uint id)
    {
        return active == id;
    }

    void beginFrame()
    {
        wentActive = false;
        hot = hotToBe;
        hotToBe = 0;

        widgetX = 0;
        widgetY = 0;
        widgetW = 0;

        areaId = 1;
        widgetId = 1;
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
            {
                setHot(id);
            }

            if (isIdHot(id) && leftPressed)
            {
                setActive(id);
            }
        }

        // if button is active, then react on left up
        if (isIdActive(id))
        {
            if (over)
                setHot(id);

            if (leftReleased)
            {
                if (isIdHot(id))
                    res = true;
                clearActive();
            }
        }

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
        import imgui.fonts : maxCharacterCount;

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
    float getTextLength(string text)
    {
        import imgui.fonts : getTextLength;

        return getTextLength(text);
    }
}
