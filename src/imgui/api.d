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
module imgui.api;

/**
   imgui is an immediate mode GUI. See also:
   http://sol.gfxile.net/imgui/

   This module contains the API of the library.
*/
import std.algorithm : max;
import std.math : floor, ceil, log10;
import std.string : sformat;
import std.range : Appender, appender, empty;
import std.conv : to;
import imgui.engine : Sizes, GuiState, GfxCmd, IMGUI_GFXCMD_SCISSOR, imguiGfxRect, IMGUI_GFXCMD_RECT, IMGUI_GFXCMD_LINE, imguiGfxLine, IMGUI_GFXCMD_TRIANGLE, IMGUI_GFXCMD_TEXT, imguiGfxText;
import imgui.gl3_renderer : imguiRenderGLInit, imguiRenderGLDestroy, toPackedRGBA, renderGLDraw;
import std.typecons : tuple;
import imgui.colorscheme : RGBA, ColorScheme, defaultColorScheme;
import std.exception : enforce;
///
enum TextAlign
{
    left,
    center,
    right,
}

/** The possible mouse buttons. These can be used as bitflags. */
enum MouseButton : ubyte
{
    left = 0x01,
    right = 0x02,
}

///
enum Enabled : bool
{
    no,
    yes,
}

/** Destroy the imgui library. */
void imguiDestroy()
{
    imguiRenderGLDestroy();
}

struct MouseInfo
{
    int x;
    int y;
    ubyte buttons;
    int dx;
    int dy;
    void reset()
    {
        x = 0;
        y = 0;
        buttons = 0;
        dx = 0;
        dy = 0;
    }
}

struct Rect
{
    int x;
    int y;
    int w;
    int h;
    bool inside(ref GuiState state, bool checkScroll = true)
    {
        return (!checkScroll || state.insideCurrentScroll) && state.mouseInfo.x >= x
            && state.mouseInfo.x <= x + w && state.mouseInfo.y >= y && state.mouseInfo.y <= y + h;
    }

}

// data to store for a ScrollArea
// some data needs to be stored between frames, some data only from a begin to a end scroll area call
struct ScrollAreaContext
{
    // info for next frames:
    int xOffset;
    int yOffset;

    // begin/end data:
    // The total area of the scrollarea component (including scrollbars and content)
    Rect scrollAreaRect;
    // The area that is used to show the scrolled content
    Rect viewport;
    Rect verticalScrollbar;
    Rect horizontalScrollbar;
    uint verticalScrollId;
    uint horizontalScrollId;
    int scrolledHorizontalPixels; // 0 for no horizontal scrolling
    int scrolledContentTop;
    int scrolledContentBottom;
    int getScrolledContentHeight()
    {
        return scrolledContentTop - scrolledContentBottom;
    }

    bool insideScrollArea;
    // info for next frame
    static struct RevealInfo
    {
        bool active;
        int yOffset;
        float percentage;
        int oldYOffset;
    }

    RevealInfo reveal;
}

class ImGui
{
    GuiState state;

    Appender!(GfxCmd[]) gfxCmdQueue;

    this(string fontPath, uint fontTextureSize = 1024)
    {
        gfxCmdQueue = appender!(GfxCmd[]);
        gfxCmdQueue.reserve(512);
        enforce(imguiRenderGLInit(fontPath, fontTextureSize));
    }

    /**
       TODO
       Begin a new frame. All batched commands after the call to
       $(D imguiBeginFrame) will be rendered as a single frame once
       $(D imguiRender) is called.

       Note: You should call $(D imguiEndFrame) after batching all
       commands to reset the input handling for the next frame.

       Example:
       -----
       int cursorX, cursorY;
       ubyte mouseButtons;
       int mouseScroll;

       /// start a new batch of commands for this frame (the batched commands)
       imguiBeginFrame(cursorX, cursorY, mouseButtons, mouseScroll);

       /// define your UI elements here
       imguiLabel("some text here");

       /// end the frame (this just resets the input control state, e.g. mouse button states)
       imguiEndFrame();

       /// now render the batched commands
       imguiRender();
       -----

       Params:

       cursorX = The cursor's last X position.
       cursorY = The cursor's last Y position.
       mouseButtons = The last mouse buttons pressed (a value or a combination of values of a $(D MouseButton)).
       mouseScroll = The last scroll value emitted by the mouse.
       unicodeChar = Unicode text input from the keyboard (usually the unicode result of last keypress).
       '0' means 'no text input'. Note that for text input to work, even Enter
       and backspace must be passed (encoded as 0x0D and 0x08, respectively),
       which may not be automatically handled by your input library's text
       input functionality (e.g. GLFW's getUnicode() does not do this).
    */
    public void beginFrame(MouseInfo mouseInfo, int width, int height, dchar unicodeChar = 0)
    {
        state.updateInput(mouseInfo, unicodeChar);
        state.beginFrame();
        state.width = width;
        state.height = height;
        gfxCmdQueue.clear;
    }

    private void addGfxCmdScissor(ref Rect r)
    {
        addGfxCmdScissor(r.x, r.y, r.w, r.h);
    }

    private void addGfxCmdScissor(int x, int y, int w, int h)
    {
        // dfmt off
        GfxCmd cmd = {
            type: IMGUI_GFXCMD_SCISSOR,
            flags: x < 0 ? 0 : 1,
            rect: imguiGfxRect(x, y, w, h),
        };
        // dfmt on
        gfxCmdQueue.put(cmd);
    }

    private void addGfxCmdRect(int x, int y, int w, int h, RGBA color)
    {
        // dfmt off
        GfxCmd cmd = {
            type: IMGUI_GFXCMD_RECT,
            color: color.toPackedRGBA(),
            rect: imguiGfxRect(x, y, w, h),
        };
        // dfmt on
        gfxCmdQueue.put(cmd);
    }

    public void addGfxCmdLine(int x1, int y1, int x2, int y2, int r, RGBA color)
    {
        // dfmt off
        GfxCmd cmd = {
            type: IMGUI_GFXCMD_LINE,
            color: color.toPackedRGBA(),
            line: imguiGfxLine(x1, y1, x2, y2, r),
        };
        // dfmt on
        gfxCmdQueue.put(cmd);
    }

    private void addGfxCmdRoundedRect(int x, int y, int w, int h, int r, RGBA color)
    {
        // dfmt off
        GfxCmd cmd = {
            type: IMGUI_GFXCMD_RECT,
            color: color.toPackedRGBA(),
            rect: imguiGfxRect(x, y, w, h, r),
        };
        // dfmt on
        gfxCmdQueue.put(cmd);
    }

    private void addGfxCmdTriangle(int x, int y, int w, int h, int flags, RGBA color)
    {
        // dfmt off
        GfxCmd cmd = {
            type: IMGUI_GFXCMD_TRIANGLE,
            flags: cast(byte) flags,
            color: color.toPackedRGBA(),
            rect: imguiGfxRect(x, y, w, h),
        };
        // dfmt on
        gfxCmdQueue.put(cmd);
    }

    private void addGfxCmdText(int x, int y, int align_, const(char)[] text, RGBA color)
    {
        // dfmt off
        GfxCmd cmd = {
            type: IMGUI_GFXCMD_TEXT,
            color: color.toPackedRGBA(),
            text: imguiGfxText(x, y, align_, text),
        };
        // dfmt on
        gfxCmdQueue.put(cmd);
    }

    /**
       Begin the definition of a new scrollable area.

       Once elements within the scrollable area are defined
       you must call $(D imguiEndScrollArea) to end the definition.

       Params:

       title = The title that will be displayed for this scroll area.
       xPos = The X position of the scroll area.
       yPos = The Y position of the scroll area.
       width = The width of the scroll area.
       height = The height of the scroll area.
       scroll = A pointer to a variable which will hold the current scroll value of the widget.
       colorScheme = Optionally override the current default color scheme when creating this element.

       Returns:

       $(D true) if the mouse was located inside the scrollable area.
    */
    public bool beginScrollArea(ref ScrollAreaContext context,
                         string title,
                         int xPos, int yPos, int width, int height,
                         bool scrollHorizontal = false, int scrolledHorizontalPixels = 2000,
                         const ref ColorScheme colorScheme = defaultColorScheme)
    {
        state.areaId++;
        state.widgetId = 0;
        context.verticalScrollId = (state.areaId << 16) | 0;
        context.horizontalScrollId = (state.areaId << 16) | 1;

        context.scrollAreaRect = Rect(xPos, yPos, width, height);
        context.viewport =
            Rect(xPos + Sizes.SCROLL_AREA_PADDING, yPos + Sizes.SCROLL_BAR_SIZE,
                 max(1, width - Sizes.SCROLL_AREA_PADDING * 4), // The max() ensures we never have zero- or negative-sized scissor rectangle when the window is very small,
                 max(1, height - Sizes.AREA_HEADER - Sizes.SCROLL_BAR_SIZE)); // avoiding a segfault.

        state.widgetX = xPos + Sizes.SCROLL_AREA_PADDING - context.xOffset;

        context.verticalScrollbar = Rect(xPos + width - Sizes.SCROLL_BAR_SIZE,
                                         yPos + Sizes.SCROLL_BAR_SIZE, Sizes.SCROLL_BAR_SIZE, height - Sizes.AREA_HEADER - Sizes.SCROLL_BAR_SIZE);
        context.horizontalScrollbar = Rect(context.scrollAreaRect.x, context.scrollAreaRect.y,
                                           context.scrollAreaRect.w - Sizes.SCROLL_BAR_SIZE, Sizes.SCROLL_BAR_SIZE);
        if (context.reveal.active)
        {
            // dfmt off
            context.yOffset = cast(int)(
              yPos + height - Sizes.AREA_HEADER + context.yOffset
              - context.reveal.yOffset
              - context.viewport.h * context.reveal.percentage);
            // dfmt on
            context.yOffset.clamp(0, context.getScrolledContentHeight() - context.viewport.h);
            context.reveal.active = false;
        }

        state.widgetY = yPos + height - Sizes.AREA_HEADER + context.yOffset;
        state.widgetW = scrollHorizontal ? scrolledHorizontalPixels : width - Sizes.SCROLL_AREA_PADDING
            * 4;

        context.scrolledHorizontalPixels = scrolledHorizontalPixels;

        context.scrolledContentTop = state.widgetY;

        context.insideScrollArea = state.inRect(xPos, yPos, width, height, false);
        state.insideCurrentScroll = context.insideScrollArea;

        addGfxCmdRoundedRect(cast(float) xPos, cast(float) yPos,
                             cast(float) width, cast(float) height, 6, colorScheme.scroll.area.back);

        addGfxCmdText(xPos + Sizes.AREA_HEADER / 2, yPos + height - Sizes.AREA_HEADER / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                      TextAlign.left, title, colorScheme.scroll.area.text);

        addGfxCmdScissor(context.viewport);
        return context.insideScrollArea;
    }

    public void revealNextElement(ref ScrollAreaContext context, float percentage = 0.5f)
    {
        context.reveal.active = true;
        context.reveal.yOffset = state.widgetY;
        context.reveal.percentage = percentage;
    }

    private auto verticalScrollbarRect(const ref Rect scrollbar)
    {
        return Rect(scrollbar.x + Sizes.SCROLL_AREA_PADDING / 2, scrollbar.y,
                    Sizes.SCROLL_BAR_HANDLE_SIZE, scrollbar.h);
    }

    private auto horizontalScrollbarRect(const ref Rect scrollbar)
    {
        return Rect(scrollbar.x, scrollbar.y + Sizes.SCROLL_AREA_PADDING / 2,
                    scrollbar.w, Sizes.SCROLL_BAR_HANDLE_SIZE);
    }

    private auto endScrollAreaVerticalScroller(ref ScrollAreaContext context,
                                       const ref ColorScheme colorScheme)
    {
        auto scroller = verticalScrollbarRect(context.verticalScrollbar);
        context.scrolledContentBottom = state.widgetY;
        int scrolledPixels = context.getScrolledContentHeight();

        float percentageVisible = cast(float) scroller.h / cast(float) scrolledPixels;
        bool visible = percentageVisible < 1;
        if (visible)
        {
            float percentageOfStart = cast(float)(scroller.y - context.scrolledContentBottom) / cast(
              float) scrolledPixels;
            percentageOfStart.clamp(0, 1);

            // Handle scroll bar logic.
            auto nob = Rect(scroller.x, scroller.y + cast(int)(percentageOfStart * scroller.h),
                            scroller.w, cast(int)(percentageVisible * scroller.h));

            const int range = scroller.h - (nob.h - 1);
            uint hid = context.verticalScrollId;
            state.buttonLogic(hid, nob.inside(state));

            if (state.isIdActive(hid))
            {

                if (state.wentActive)
                {
                    float u = cast(float)(nob.y - scroller.y) / cast(float) range;
                    state.dragY = state.mouseInfo.y;
                    state.dragOrigY = u;
                }

                if (state.dragY != state.mouseInfo.y)
                {
                    float u = state.dragOrigY + (state.mouseInfo.y - state.dragY) / cast(float) range;
                    u.clamp(0, 1);
                    context.yOffset = cast(int)((1 - u) * (scrolledPixels - scroller.h));
                }
            }

            auto color = state.isIdActive(hid) ? colorScheme.scroll.bar.thumbPress
                : (state.isIdHot(hid) ? colorScheme.scroll.bar.thumbHover
                   : colorScheme.scroll.bar.thumb);

            // vertical Bar
            // BG
            addGfxCmdRect(cast(float) scroller.x, cast(float) scroller.y,
                          cast(float) scroller.w, cast(float) scroller.h, colorScheme.scroll.bar.back);

            addGfxCmdRect(cast(float) nob.x, cast(float) nob.y,
                          cast(float) nob.w, cast(float) nob.h, color);
        }
        return tuple!("pixels", "visible")(scrolledPixels, visible);
    }

    private auto endScrollAreaHorizontalScroller(ref ScrollAreaContext context,
                                         const ref ColorScheme colorScheme)
    {
        auto scroller = horizontalScrollbarRect(context.horizontalScrollbar);

        float percentageVisible = (context.scrolledHorizontalPixels
                                   ? scroller.w / context.scrolledHorizontalPixels.to!float : 1.0f);
        bool visible = percentageVisible < 1;
        if (visible)
        {
            float percentageOfStart = (context.scrolledHorizontalPixels
                                       ? context.xOffset / context.scrolledHorizontalPixels.to!float : 0.0f);
            percentageOfStart.clamp(0, 1);

            // Handle scroll bar logic.
            auto visibleStart = percentageOfStart * (context.scrollAreaRect.w - Sizes.SCROLL_BAR_SIZE);
            auto visibleWidth = percentageVisible * (context.scrollAreaRect.w - Sizes.SCROLL_BAR_SIZE);
            auto nob = Rect(cast(int)(scroller.x + visibleStart), scroller.y,
                            cast(int) visibleWidth, scroller.h);

            const int range = scroller.w - (nob.w - 1);
            uint hid = context.horizontalScrollId;
            state.buttonLogic(hid, nob.inside(state));

            if (state.isIdActive(hid))
            {

                if (state.wentActive)
                {
                    float u = cast(float)(nob.x - scroller.x) / cast(float) range;
                    state.dragX = state.mouseInfo.x;
                    state.dragOrigX = u;
                }

                if (state.dragX != state.mouseInfo.x)
                {
                    float u = state.dragOrigX + (state.mouseInfo.x - state.dragX) / cast(float) range;
                    u.clamp(0, 1);
                    context.xOffset = cast(int)(u * (context.scrolledHorizontalPixels - scroller.w));
                }
            }

            auto color = state.isIdActive(hid) ? colorScheme.scroll.bar.thumbPress
                : (state.isIdHot(hid) ? colorScheme.scroll.bar.thumbHover
                   : colorScheme.scroll.bar.thumb);
            // horizontal bar
            // background
            addGfxCmdRect(context.scrollAreaRect.x,
                          context.scrollAreaRect.y + Sizes.SCROLL_AREA_PADDING / 2,
                          context.scrollAreaRect.w - Sizes.SCROLL_BAR_SIZE,
                          Sizes.SCROLL_BAR_HANDLE_SIZE, colorScheme.scroll.bar.back);

            addGfxCmdRect(nob.x, nob.y, nob.w, nob.h, color);
        }
        return tuple!("pixels", "visible")(context.scrolledHorizontalPixels, visible);
    }
    /**
       End the definition of the last scrollable element.

       Params:

       colorScheme = Optionally override the current default color scheme when creating this element.
    */
    public void endScrollArea(ref ScrollAreaContext context,
                       const ref ColorScheme colorScheme = defaultColorScheme)
    {
        // scrollbars are 2 scroll_area_paddings wide, with 0.5 before and after .. totalling 3 * scroll_area_paddings
        // on top is the header

        // Disable scissoring.
        addGfxCmdScissor(-1, -1, -1, -1);

        auto vertical = endScrollAreaVerticalScroller(context, colorScheme);
        auto horizontal = endScrollAreaHorizontalScroller(context, colorScheme);
        if (context.reveal.active)
        {
        }
        // Handle mouse scrolling.
        if (context.insideScrollArea) // && !anyActive())
        {
            if (vertical.visible)
            {
                if (state.mouseInfo.dy)
                {
                    context.yOffset += 20 * state.mouseInfo.dy;
                    context.yOffset.clamp(0, vertical.pixels - context.viewport.h);
                }
            }
            if (horizontal.visible)
            {
                if (state.mouseInfo.dx)
                {
                    context.xOffset += 20 * state.mouseInfo.dx;
                    context.xOffset.clamp(0, horizontal.pixels - context.viewport.w);
                }
            }
        }

        state.insideCurrentScroll = false;
    }

    /**
       Define a new button.

       Params:

       label = The text that will be displayed on the button.
       enabled = Set whether the button can be pressed.
       colorScheme = Optionally override the current default color scheme when creating this element.

       Returns:

       $(D true) if the button is enabled and was pressed.
       Note that pressing a button implies pressing and releasing the
       left mouse button while over the gui button.

       Example:
       -----
       void onPress() { }
       if (imguiButton("Push me"))  // button was pushed
       onPress();
       -----
    */
    public bool button(string label, Enabled enabled = Enabled.yes,
                const ref ColorScheme colorScheme = defaultColorScheme)
    {
        state.widgetId++;
        uint id = (state.areaId << 16) | state.widgetId;

        int x = state.widgetX;
        int y = state.widgetY - Sizes.BUTTON_HEIGHT;
        int w = state.widgetW;
        int h = Sizes.BUTTON_HEIGHT;
        state.widgetY -= Sizes.BUTTON_HEIGHT + Sizes.DEFAULT_SPACING;

        if ((y > state.height) || (y+h < 0))
        {
            return false;
        }

        bool over = enabled && state.inRect(x, y, w, h);
        addGfxCmdRoundedRect(x, y, w, h, 10, state.isIdActive(id)
                             ? colorScheme.button.backPress : colorScheme.button.back);

        auto color = enabled ? (state.isIdHot(id)
                                ? colorScheme.button.textHover : colorScheme.button.text)
            : colorScheme.button.textDisabled;
        addGfxCmdText(x + Sizes.BUTTON_HEIGHT / 2,
                      y + Sizes.BUTTON_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                      TextAlign.left, label, color);

        return state.buttonLogic(id, over);
    }

    /**
       Define a new checkbox.

       Params:

       label = The text that will be displayed on the button.
       checkState = A pointer to a variable which holds the current state of the checkbox.
       enabled = Set whether the checkbox can be pressed.
       colorScheme = Optionally override the current default color scheme when creating this element.

       Returns:

       $(D true) if the checkbox was toggled on or off.
       Note that toggling implies pressing and releasing the
       left mouse button while over the checkbox.

       Example:
       -----
       bool checkState = false;  // initially un-checked
       if (imguiCheck("checkbox", &checkState))  // checkbox was toggled
       writeln(checkState);  // check the current state
       -----
    */
    public bool checkbox(string label, bool* checkState, Enabled enabled = Enabled.yes,
                         const ref ColorScheme colorScheme = defaultColorScheme)
    {
        state.widgetId++;
        uint id = (state.areaId << 16) | state.widgetId;

        int x = state.widgetX;
        int y = state.widgetY - Sizes.BUTTON_HEIGHT;
        int w = state.widgetW;
        int h = Sizes.BUTTON_HEIGHT;
        state.widgetY -= Sizes.BUTTON_HEIGHT + Sizes.DEFAULT_SPACING;
        // TODO vertical clipping (see button)
        if ((y > state.height) || (y+h < 0))
        {
            return false;
        }

        bool over = enabled && state.inRect(x, y, w, h);
        bool res = state.buttonLogic(id, over);

        if (res)
        {
            *checkState = !(*checkState);
        }

        const int cx = x + Sizes.BUTTON_HEIGHT / 2 - Sizes.CHECK_SIZE / 2;
        const int cy = y + Sizes.BUTTON_HEIGHT / 2 - Sizes.CHECK_SIZE / 2;

        // dfmt off
        addGfxCmdRoundedRect(cx - 3, cy - 3,
                             Sizes.CHECK_SIZE + 6, Sizes.CHECK_SIZE + 6,
                             4, state.isIdActive(id) ? colorScheme.checkbox.press : colorScheme.checkbox.back);
        // dfmt on
        if (*checkState)
        {
            auto color = enabled ? (state.isIdActive(id)
                                    ? colorScheme.checkbox.checked : colorScheme.checkbox.doUncheck)
                : colorScheme.checkbox.disabledChecked;
            addGfxCmdRoundedRect(cx, cy, Sizes.CHECK_SIZE, Sizes.CHECK_SIZE, Sizes.CHECK_SIZE / 2 - 1, color);
        }

        auto color = enabled ? (state.isIdHot(id)
                                ? colorScheme.checkbox.textHover : colorScheme.checkbox.text)
            : colorScheme.checkbox.textDisabled;
        addGfxCmdText(x + Sizes.BUTTON_HEIGHT, y + Sizes.BUTTON_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                      TextAlign.left, label, color);

        return res;
    }

    /**
       Define a new item.

       Params:

       label = The text that will be displayed as the item.
       enabled = Set whether the item can be pressed.
       colorScheme = Optionally override the current default color scheme when creating this element.

       Returns:

       $(D true) if the item is enabled and was pressed.
       Note that pressing an item implies pressing and releasing the
       left mouse button while over the item.
    */
    public bool item(string label, Enabled enabled = Enabled.yes,
              const ref ColorScheme colorScheme = defaultColorScheme)
    {
        state.widgetId++;
        uint id = (state.areaId << 16) | state.widgetId;

        int x = state.widgetX;
        int y = state.widgetY - Sizes.BUTTON_HEIGHT;
        int w = state.widgetW;
        int h = Sizes.BUTTON_HEIGHT;
        state.widgetY -= Sizes.BUTTON_HEIGHT + Sizes.DEFAULT_SPACING;

        if ((y > state.height) || (y+h < 0))
        {
            return false;
        }

        // TODO vertical clipping see button
        bool over = enabled && state.inRect(x, y, w, h);
        bool res = state.buttonLogic(id, over);

        if (state.isIdHot(id))
        {
            addGfxCmdRoundedRect(cast(float) x, cast(float) y, cast(float) w,
                                 cast(float) h, 10, state.isIdActive(id)
                                 ? colorScheme.item.press : colorScheme.item.hover);
        }
        addGfxCmdText(x + Sizes.BUTTON_HEIGHT / 2, y + Sizes.BUTTON_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                      TextAlign.left, label, enabled ? colorScheme.item.text
                      : colorScheme.item.textDisabled);

        return res;
    }

    /**
       Define a new collapsable element.

       Params:

       label = The text that will be displayed as the item.
       subtext = Additional text displayed on the right of the label.
       checkState = A pointer to a variable which holds the current state of the collapsable element.
       enabled = Set whether the element can be pressed.
       colorScheme = Optionally override the current default color scheme when creating this element.

       Returns:

       $(D true) if the collapsable element is enabled and was pressed.
       Note that pressing a collapsable element implies pressing and releasing the
       left mouse button while over the collapsable element.
    */
    public bool collapse(string label, string subtext, bool* checkState,
                  Enabled enabled = Enabled.yes, const ref ColorScheme colorScheme = defaultColorScheme)
    {
        state.widgetId++;
        uint id = (state.areaId << 16) | state.widgetId;

        int x = state.widgetX;
        int y = state.widgetY - Sizes.BUTTON_HEIGHT;
        int w = state.widgetW;
        int h = Sizes.BUTTON_HEIGHT;
        state.widgetY -= Sizes.BUTTON_HEIGHT; // + DEFAULT_SPACING;

        const int cx = x + Sizes.BUTTON_HEIGHT / 2 - Sizes.CHECK_SIZE / 2;
        const int cy = y + Sizes.BUTTON_HEIGHT / 2 - Sizes.CHECK_SIZE / 2;

        bool over = enabled && state.inRect(x, y, w, h);
        bool res = state.buttonLogic(id, over);

        if (res)
        {
            *checkState = !(*checkState);
        }

        auto triangleColor = (*checkState) ? (state.isIdActive(id)
                                              ? colorScheme.collapse.doHide : colorScheme.collapse.shown) : state.isIdActive(id)
            ? colorScheme.collapse.doShow : colorScheme.collapse.hidden;
        addGfxCmdTriangle(cx, cy, Sizes.CHECK_SIZE, Sizes.CHECK_SIZE, 2, triangleColor);

        auto textColor = enabled ? (state.isIdHot(id)
                                    ? colorScheme.collapse.textHover : colorScheme.collapse.text)
            : colorScheme.collapse.textDisabled;
        addGfxCmdText(x + Sizes.BUTTON_HEIGHT, y + Sizes.BUTTON_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                      TextAlign.left, label, textColor);

        if (subtext)
            addGfxCmdText(x + w - Sizes.BUTTON_HEIGHT / 2, y + Sizes.BUTTON_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                          TextAlign.right, subtext, colorScheme.collapse.subtext);

        return res;
    }

    /**
       Define a new label.

       Params:

       label = The text that will be displayed as the label.
       colorScheme = Optionally override the current default color scheme when creating this element.
    */
    public void label(string label, const ref ColorScheme colorScheme = defaultColorScheme)
    {
        const int x = state.widgetX;
        const int y = state.widgetY - Sizes.BUTTON_HEIGHT;
        const int h = Sizes.BUTTON_HEIGHT;
        state.widgetY -= Sizes.BUTTON_HEIGHT;
        if ((y > state.height) || (y+h < 0))
        {
            return;
        }
        addGfxCmdText(x, y + Sizes.BUTTON_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                      TextAlign.left, label, colorScheme.label.text);
    }

    /**
       Define a new value.

       Params:

       label = The text that will be displayed as the value.
       colorScheme = Optionally override the current default color scheme when creating this element.
    */
    public void value(string label, const ref ColorScheme colorScheme = defaultColorScheme)
    {
        const int x = state.widgetX;
        const int y = state.widgetY - Sizes.BUTTON_HEIGHT;
        const int w = state.widgetW;
        const int h = Sizes.BUTTON_HEIGHT;
        state.widgetY -= Sizes.BUTTON_HEIGHT;
        if ((y > state.height) || (y+h < 0))
        {
            return;
        }
        addGfxCmdText(x + w - Sizes.BUTTON_HEIGHT / 2, y + Sizes.BUTTON_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                      TextAlign.right, label, colorScheme.value.text);
    }

    /**
       Define a new slider.

       Params:

       label = The text that will be displayed above the slider.
       sliderState = A pointer to a variable which holds the current slider value.
       minValue = The minimum value that the slider can hold.
       maxValue = The maximum value that the slider can hold.
       stepValue = The step at which the value of the slider will increase or decrease.
       enabled = Set whether the slider's value can can be changed with the mouse.
       colorScheme = Optionally override the current default color scheme when creating this element.

       Returns:

       $(D true) if the slider is enabled and was pressed.
       Note that pressing a slider implies pressing and releasing the
       left mouse button while over the slider.
    */
    public bool slider(string label, float* sliderState, float minValue, float maxValue,
                float stepValue, Enabled enabled = Enabled.yes,
                const ref ColorScheme colorScheme = defaultColorScheme)
    {
        state.widgetId++;
        uint id = (state.areaId << 16) | state.widgetId;

        int x = state.widgetX;
        int y = state.widgetY - Sizes.BUTTON_HEIGHT;
        int w = state.widgetW;
        int h = Sizes.SLIDER_HEIGHT;
        state.widgetY -= Sizes.SLIDER_HEIGHT + Sizes.DEFAULT_SPACING;
        if ((y > state.height) || (y+h < 0))
        {
            return false;
        }

        addGfxCmdRoundedRect(x, y, w, h, 4, colorScheme.slider.back);

        const int range = w - Sizes.SLIDER_MARKER_WIDTH;

        float u = (*sliderState - minValue) / (maxValue - minValue);
        u.clamp(0, 1);

        int m = cast(int)(u * range);

        bool over = enabled && state.inRect(x + m, y, Sizes.SLIDER_MARKER_WIDTH, Sizes.SLIDER_HEIGHT);
        bool res = state.buttonLogic(id, over);
        bool valChanged = false;

        if (state.isIdActive(id))
        {
            if (state.wentActive)
            {
                state.dragX = state.mouseInfo.x;
                state.dragOrigX = u;
            }

            if (state.dragX != state.mouseInfo.x)
            {
                u = state.dragOrigX + cast(float)(state.mouseInfo.x - state.dragX) / cast(float) range;
                u.clamp(0, 1);

                *sliderState = minValue + u * (maxValue - minValue);
                *sliderState = floor(*sliderState / stepValue + 0.5f) * stepValue; // Snap to stepValue
                m = cast(int)(u * range);
                valChanged = true;
            }
        }

        auto color = state.isIdActive(id) ? colorScheme.slider.thumbPress
            : (state.isIdHot(id) ? colorScheme.slider.thumbHover : colorScheme.slider.thumb);
        addGfxCmdRoundedRect(x + m, y, Sizes.SLIDER_MARKER_WIDTH, Sizes.SLIDER_HEIGHT, 4, color);

        // TODO: fix this, take a look at 'nicenum'.
        // todo: this should display sub 0.1 if the step is low enough.
        int digits = cast(int)(ceil(log10(stepValue)));
        char[16] fmtBuf;
        auto fmt = sformat(fmtBuf, "%%.%df", digits >= 0 ? 0 : -digits);
        char[32] msgBuf;
        string msg = sformat(msgBuf, fmt, *sliderState).idup;

        auto sliderTextColor = enabled ? (state.isIdHot(id)
                                          ? colorScheme.slider.textHover : colorScheme.slider.text)
            : colorScheme.slider.textDisabled;
        auto sliderValueColor = enabled ? (state.isIdHot(id)
                                           ? colorScheme.slider.valueHover : colorScheme.slider.value)
            : colorScheme.slider.valueDisabled;
        addGfxCmdText(x + Sizes.SLIDER_HEIGHT / 2, y + Sizes.SLIDER_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                      TextAlign.left, label, sliderTextColor);
        addGfxCmdText(x + w - Sizes.SLIDER_HEIGHT / 2, y + Sizes.SLIDER_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                      TextAlign.right, msg, sliderValueColor);

        return res || valChanged;
    }

    /** Define a text input field.
     *
     * Params:
     *
     * text           = Label that will be placed beside the text input field.
     * buffer         = Buffer to store entered text.
     * usedSlice      = Slice of buffer that stores text entered so far.
     * forceInputable = Force the text input field to be inputable regardless of whether it
     *                  has been selected by the user? Useful to e.g. make a text field
     *                  inputable immediately after it appears in a newly opened dialog.
     * colorScheme    = Optionally override the current default color scheme for this element.
     *
     * Returns: true if the user has entered and confirmed the text (by pressing Enter), false
     *          otherwise.
     *
     * Example (using GLFW):
     * --------------------
     * static dchar staticUnicode;
     * // Buffer to store text input
     * char[128] textInputBuffer;
     * // Slice of textInputBuffer
     * char[] textEntered;
     *
     * extern(C) static void getUnicode(GLFWwindow* w, uint unicode)
     * {
     *     staticUnicode = unicode;
     * }
     *
     * extern(C) static void getKey(GLFWwindow* w, int key, int scancode, int action, int mods)
     * {
     *     if(action != GLFW_PRESS) { return; }
     *     if(key == GLFW_KEY_ENTER)          { staticUnicode = 0x0D; }
     *     else if(key == GLFW_KEY_BACKSPACE) { staticUnicode = 0x08; }
     * }
     *
     * void init()
     * {
     *     GLFWwindow* window;
     *
     *     // ... init the window here ...
     *
     *     // Not really needed, but makes it obvious what we're doing
     *     textEntered = textInputBuffer[0 .. 0];
     *     glfwSetCharCallback(window, &getUnicode);
     *     glfwSetKeyCallback(window, &getKey);
     * }
     *
     * void frame()
     * {
     *     // These should be defined somewhere
     *     int mouseX, mouseY, mouseScroll;
     *     ubyte mousebutton;
     *
     *     // .. code here ..
     *
     *     // Pass text input to imgui
     *     imguiBeginFrame(cast(int)mouseX, cast(int)mouseY, mousebutton, mouseScroll, staticUnicode);
     *     // reset staticUnicode for the next frame
     *
     *     staticUnicode = 0;
     *
     *     if(imguiTextInput("Text input:", textInputBuffer, textEntered))
     *     {
     *         import std.stdio;
     *         writeln("Entered text is: ", textEntered);
     *         // Reset entered text for next input (use e.g. textEntered.dup if you need a copy).
     *         textEntered = textInputBuffer[0 .. 0];
     *     }
     *
     *     // .. more code here ..
     * }
     * --------------------
     */
    public bool textInput(string label, char[] buffer, ref char[] usedSlice,
                   bool forceInputable = false, const ref ColorScheme colorScheme = defaultColorScheme)
    {
        assert(buffer.ptr == usedSlice.ptr && buffer.length >= usedSlice.length,
               "The usedSlice parameter on imguiTextInput must be a slice to the buffer "
               ~ "parameter");

        // Label
        state.widgetId++;
        uint id = (state.areaId << 16) | state.widgetId;
        int x = state.widgetX;
        int y = state.widgetY - Sizes.BUTTON_HEIGHT;
        addGfxCmdText(x, y + Sizes.BUTTON_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                      TextAlign.left, label, colorScheme.textInput.label);

        bool res = false;
        // Handle control input if any (Backspace to erase characters, Enter to confirm).
        // Backspace
        if (state.isIdInputable(id) && state.unicode == 0x08
            && state.unicode != state.lastUnicode && !usedSlice.empty)
        {
            usedSlice = usedSlice[0 .. $ - 1];
        }
        // Pressing Enter "confirms" the input.
        else if (state.isIdInputable(id) && state.unicode == 0x0D
                 && state.unicode != state.lastUnicode)
        {
            state.inputable = 0;
            res = true;
        }
        else if (state.isIdInputable(id) && state.unicode != 0 && state.unicode != state
                 .lastUnicode)
        {
            import std.utf;

            char[4] codePoints;
            const codePointCount = std.utf.encode(codePoints, state.unicode);
            // Only add the character into the buffer if we can fit it there.
            if (buffer.length - usedSlice.length >= codePointCount)
            {
                usedSlice = buffer[0 .. usedSlice.length + codePointCount];
                usedSlice[$ - codePointCount .. $] = codePoints[0 .. codePointCount];
            }
        }

        // Draw buffer data
        uint labelLen = cast(uint)(state.getTextLength(label) + 0.5f);
        x += labelLen;
        int w = state.widgetW - labelLen - Sizes.DEFAULT_SPACING * 2;
        int h = Sizes.BUTTON_HEIGHT;
        bool over = state.inRect(x, y, w, h);
        state.textInputLogic(id, over, forceInputable);
        addGfxCmdRoundedRect(cast(float)(x + Sizes.DEFAULT_SPACING), cast(float) y,
                             cast(float) w, cast(float) h, 10, state.isIdInputable(id)
                             ? colorScheme.textInput.back : colorScheme.textInput.backDisabled);
        addGfxCmdText(x + Sizes.DEFAULT_SPACING * 2,
                      y + Sizes.BUTTON_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                      TextAlign.left, usedSlice, state.isIdInputable(id)
                      ? colorScheme.textInput.text : colorScheme.textInput.textDisabled);

        state.widgetY -= Sizes.BUTTON_HEIGHT + Sizes.DEFAULT_SPACING;
        return res;
    }

    /** Add horizontal indentation for elements to be added. */
    public void indent()
    {
        state.widgetX += Sizes.INDENT_SIZE;
        state.widgetW -= Sizes.INDENT_SIZE;
    }

    /** Remove horizontal indentation for elements to be added. */
    public void unindent()
    {
        state.widgetX -= Sizes.INDENT_SIZE;
        state.widgetW += Sizes.INDENT_SIZE;
    }

    /** Add vertical space as a separator below the last element. */
    public void separator()
    {
        state.widgetY -= Sizes.DEFAULT_SPACING * 3;
    }

    /**
       Add a horizontal line as a separator below the last element.

       Params:
       colorScheme = Optionally override the current default color scheme when creating this element.
    */
    public void separatorLine(const ref ColorScheme colorScheme = defaultColorScheme)
    {
        int x = state.widgetX;
        int y = state.widgetY - Sizes.DEFAULT_SPACING * 2;
        int w = state.widgetW;
        int h = 1;
        state.widgetY -= Sizes.DEFAULT_SPACING * 4;
        if ((y > state.height) || (y+h < 0))
        {
            return;
        }

        addGfxCmdRect(x, y, w, h, colorScheme.separator);
    }

    /**
       Draw text.

       Params:
       color = Optionally override the current default text color when creating this element.
    */
    public void drawText(int xPos, int yPos, TextAlign textAlign, string text,
                  RGBA color = defaultColorScheme.generic.text)
    {
        addGfxCmdText(xPos, yPos, textAlign, text, color);
    }

    /**
       Draw a line.

       Params:
       colorScheme = Optionally override the current default color scheme when creating this element.
    */
    public void drawLine(int x0, int y0, int x1, int y1, int r,
                  RGBA color = defaultColorScheme.generic.line)
    {
        addGfxCmdLine(x0, y0, x1, y1, r, color);
    }

    /**
       Draw a rectangle.

       Params:
       colorScheme = Optionally override the current default color scheme when creating this element.
    */
    public void drawRect(int xPos, int yPos, int width, int height,
                  RGBA color = defaultColorScheme.generic.rect)
    {
        addGfxCmdRect(xPos, yPos, width, height, color);
    }

    /**
       Draw a rounded rectangle.

       Params:
       colorScheme = Optionally override the current default color scheme when creating this element.
    */
    public void drawRoundedRect(int x, int y, int width, int height, int r,
                         RGBA color = defaultColorScheme.generic.roundRect)
    {
        addGfxCmdRoundedRect(x, y, width, height, r, color);
    }
    /** End the list of batched commands for the current frame. */
    public void endFrame()
    {
        state.clearInput();
    }

    /** Render all of the batched commands for the current frame. */
    public void render()
    {
        renderGLDraw(gfxCmdQueue[], state.width, state.height);
    }

}

public void clamp(T)(ref T value, const T minValue, const T maxValue)
{
    if (value < minValue)
    {
        value = minValue;
    }
    else if (value > maxValue)
    {
        value = maxValue;
    }
}
