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

/++
   imgui is an immediate mode GUI. See also:
   http://sol.gfxile.net/imgui/

   This module contains the API of the library.
   Coordinates start with 0,0 in the lower left corner of the screen and

    ^
   0,3
    |
    |
   0,0--3,0->
+/
import std.algorithm : max, min, map;
import std.array : join;
import std.math : floor, ceil, log10;
import std.string : sformat;
import std.format : format;
import std.range : Appender, appender, empty;
import std.conv : to, text;
import imgui.engine : GuiState, Command, Type, Rect, Line, Text, Vector2i, GlobalAlpha;

//import imgui.gl3_renderer : imguiRenderGLInit, imguiRenderGLDestroy, toPackedRGBA, renderGLDraw;
import std.typecons : tuple;
import imgui.colorscheme : RGBA, ColorScheme, defaultColorScheme;
import std.exception : enforce;
import std.datetime.systime : SysTime, Clock;
import deetween : Tween, easeLinear, TweenMode;
import std.uni : byCodePoint;
import std.array : array;

struct Sizes
{
    enum LINE_HEIGHT = 60;
    enum SLIDER_MARKER_WIDTH = 10;
    enum CHECK_SIZE = TEXT_HEIGHT - TEXT_BASELINE - 10;
    enum DEFAULT_SPACING = 4;
    enum TEXT_HEIGHT = 35;
    enum TEXT_BASELINE = 5;
    enum SCROLL_AREA_PADDING = 6;
    enum SCROLL_BAR_SIZE = SCROLL_AREA_PADDING * 3;
    enum SCROLL_BAR_HANDLE_SIZE = SCROLL_AREA_PADDING * 2;
    enum INDENT_SIZE = 16;
}

struct Animations
{
    enum DURATION = 0.3;

}
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

bool inside(Rect r, ref GuiState state, bool checkScroll = true)
{
    return (!checkScroll || state.insideCurrentScroll) && state.mouseInfo.x >= r.x
        && state.mouseInfo.x <= r.x + r.w && state.mouseInfo.y >= r.y
        && state.mouseInfo.y <= r.y + r.h;
}

class Animation
{
    Tween animation;
    SysTime startOfAnimation;
    this(Tween tween)
    {
        this.animation = tween;
        startOfAnimation = Clock.currTime;
    }

    auto hasFinished()
    {
        return animation.hasFinished;
    }

    void elapsedTime(float elapsedTime)
    {
        animation.elapsedTime(elapsedTime);
    }

    auto now()
    {
        return animation.now;
    }

    void tick(SysTime now)
    {
        animation.elapsedTime((now - startOfAnimation).total!"msecs" / 1000.0f);
    }
}

struct ScrollAreaContext
{
    Vector2i offset;
    int scrolledContentHeight;
    Animation animation;
    float alpha;
    void animate(SysTime t)
    {
        if (animation !is null)
        {
            animation.tick(t);
            alpha = animation.now;
        }
    }

    bool isVisible()
    {
        return alpha > 0.0f;
    }

    static struct RevealInfo
    {
        bool active;
        int yOffset;
        float percentage;
        int oldYOffset;
    }

    /// Toggle visibility (usually with animation of alpha)
    void toggle()
    {
        if (animation is null)
        {
            animation = new Animation(Tween(0, 1, Animations.DURATION, TweenMode.bomb));
        }
        else if (animation.animation.b == 1.0f)
        {
            animation = new Animation(Tween(animation.now, 0, Animations.DURATION, TweenMode.bomb));
        }
        else
        {
            animation = new Animation(Tween(animation.now, 1, Animations.DURATION, TweenMode.bomb));
        }
    }

    RevealInfo reveal;
}

private struct LocalScrollAreaContext
{
    uint verticalScrollId;
    uint horizontalScrollId;
    int scrolledContentTop;

    // The total area of the scrollarea component (including scrollbars and content)
    Rect scrollAreaRect;
    // the viewport on the scrolled area (scrollarearect - scrollbars)
    Rect viewport;

    Rect verticalScrollbar;
    Rect horizontalScrollbar;
    int scrolledHorizontalPixels; // 0 for no horizontal scrolling
    bool insideScrollArea;
}

void addScissor(Commands commands, int x, int y, int w, int h)
{
    // dfmt off
    Command cmd = {
        type: Type.SCISSOR,
        rect: Rect(x, y, w, h),
    };
    // dfmt on
    commands.put(cmd);
}

void addScissor(Commands commands, ref Rect r)
{
    commands.addScissor(r.x, r.y, r.w, r.h);
}

void addDisableScissor(Commands commands)
{
    Command cmd = {type: Type.DISABLE_SCISSOR,};
    commands.put(cmd);
}

void addRect(Commands commands, int x, int y, int w, int h, RGBA color)
{
    // dfmt off
    Command cmd = {
        type: Type.RECT,
        color: color.toPackedRGBA(),
        rect: Rect(x, y, w, h),
    };
    // dfmt on
    commands.put(cmd);
}

void addRoundedRect(Commands commands, int x, int y, int w, int h, int r, RGBA color)
{
    // dfmt off
    Command cmd = {
        type: Type.RECT,
        color: color.toPackedRGBA(),
        rect: Rect(x, y, w, h, r),
    };
    // dfmt on
    commands.put(cmd);
}

void addLine(Commands commands, int x1, int y1, int x2, int y2, int r, RGBA color)
{
    // dfmt off
    Command cmd = {
        type: Type.LINE,
        color: color.toPackedRGBA(),
        line: Line(x1, y1, x2, y2, r),
    };
    // dfmt on
    commands.put(cmd);
}

void addArrowDown(Commands commands, int x, int y, int w, int h, RGBA color)
{
    // dfmt off
    Command cmd = {
        type: Type.ARROW_DOWN,
        color: color.toPackedRGBA(),
        rect: Rect(x, y, w, h),
    };
    // dfmt on
    commands.put(cmd);
}

void addArrowRight(Commands commands, int x, int y, int w, int h, RGBA color)
{
    // dfmt off
    Command cmd = {
        type: Type.ARROW_RIGHT,
        color: color.toPackedRGBA(),
        rect: Rect(x, y, w, h),
    };
    // dfmt on
    commands.put(cmd);
}

void addGlobalAlpha(Commands commands, float alpha)
{
    // dfmt off
    Command cmd =
        {
            type: Type.GLOBAL_ALPHA,
            alpha: GlobalAlpha(alpha),
        };
    // dfmt on
    commands.put(cmd);
}

void addText(Commands commands, int x, int y, int alignment, const(char)[] text, RGBA color)
{
    // dfmt off
    Command cmd =
        {
            type: Type.TEXT,
            color: color.toPackedRGBA(),
            text: Text(x, y, alignment, text),
        };
    // dfmt on
    commands.put(cmd);
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

class Layout
{
    GuiState initialGuiState;

    void push(ref GuiState state)
    {
        this.initialGuiState = state;
    }

    void pop(ref GuiState state)
    {
    }

    // called after each widget
    void update(ref GuiState state)
    {
    }
}

class LineLayout : Layout
{
    override void push(ref GuiState state)
    {
        super.push(state);
    }

    override void pop(ref GuiState state)
    {
    }

    override void update(ref GuiState state)
    {
        state.widgetY -= Sizes.LINE_HEIGHT + Sizes.DEFAULT_SPACING;
    }
}

class ColumnLayout : Layout
{
    int[] columns;
    int index;
    this(int[] columns)
    {
        this.columns = columns;
        this.index = 0;
    }

    override void push(ref GuiState state)
    {
        super.push(state);
        if (columns[index] < 0)
        {
            state.widgetW = initialGuiState.widgetW + columns[index] - Sizes.DEFAULT_SPACING;
        }
    }

    override void pop(ref GuiState state)
    {
        state.widgetW = initialGuiState.widgetW;
        state.widgetY -= Sizes.LINE_HEIGHT + Sizes.DEFAULT_SPACING;
        state.widgetX = initialGuiState.widgetX;
    }

    override void update(ref GuiState state)
    {
        index++;
        if (index < columns.length)
        {
            state.widgetX = state.widgetX + state.widgetW + Sizes.DEFAULT_SPACING;
            if (columns[index] < 0)
            {
                state.widgetW = state.widgetW + columns[index] - Sizes.DEFAULT_SPACING;
            }
            else
            {
                state.widgetW = initialGuiState.widgetW - state.widgetW - Sizes.DEFAULT_SPACING;
            }
        }
    }
}

class HotKey
{
    dchar[] keys;
    string description;
    this(dchar[] keys, string description)
    {
        this.keys = keys;
        this.description = description;
    }

    void toString(Sink)(Sink sink)
    {
        foreach (index, key; keys)
        {
            if (index > 0)
            {
                sink(", ");
            }
            sink("'");
            sink(key.to!string);
            sink("'");
        }
        sink(": ");
        sink(description);
    }

}

alias Commands = Appender!(Command[]);
class ImGui(T)
{
    GuiState state;
    Commands commands;

    T implementation;
    this(string fontPath, uint fontTextureSize = 1024)
    {
        commands = appender!(Command[]);
        commands.reserve(512);
        implementation = new T(fontPath, fontTextureSize);
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
    public void frame(MouseInfo mouseInfo, int width, int height,
            ref dchar unicodeChar, void delegate() builder)
    {
        state.updateInput(mouseInfo, unicodeChar);
        state.beginFrame();
        state.width = width;
        state.height = height;
        commands.clear;
        builder();
        unicodeChar = 0;
        state.clearInput();
        state.clearHotkeys();
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
    public bool scrollArea(ref ScrollAreaContext context, int xPos, int yPos, int width,
            int height, void delegate() header, void delegate() builder, bool scrollHorizontal = false,
            int scrolledHorizontalPixels = 2000,
            const ref ColorScheme colorScheme = defaultColorScheme,)
    {
        state.inScroll = false;
        state.areaId++;
        state.widgetId = 0;
        commands.addGlobalAlpha(context.alpha);
        commands.addRoundedRect(xPos, yPos, width, height, 6, colorScheme.scroll.area.back);

        state.widgetX = xPos + Sizes.SCROLL_AREA_PADDING - context.offset.x;
        state.widgetY = yPos + height;
        state.widgetW = width - 2 * Sizes.SCROLL_AREA_PADDING;
        state.pushLayout(new LineLayout());
        header();
        state.inScroll = true;
        LocalScrollAreaContext localContext;
        state.widgetId++;
        localContext.verticalScrollId = (state.areaId << 16) | state.widgetId;
        state.widgetId++;
        localContext.horizontalScrollId = (state.areaId << 16) | state.widgetId;
        state.widgetId++;
        height = state.widgetY - yPos;
        localContext.scrollAreaRect = Rect(xPos, yPos, width, height);
        localContext.viewport = Rect(xPos + Sizes.SCROLL_AREA_PADDING,
                yPos + Sizes.SCROLL_BAR_SIZE, max(1, width - Sizes.SCROLL_AREA_PADDING * 4), // The max() ensures we never have zero- or negative-sized scissor rectangle when the window is very small,
                max(1, height - Sizes.SCROLL_BAR_SIZE)); // avoiding a segfault.

        localContext.verticalScrollbar = Rect(xPos + width - Sizes.SCROLL_BAR_SIZE,
                yPos + Sizes.SCROLL_BAR_SIZE, Sizes.SCROLL_BAR_SIZE,
                height - Sizes.SCROLL_BAR_SIZE);
        localContext.horizontalScrollbar = Rect(localContext.scrollAreaRect.x, localContext.scrollAreaRect.y,
                localContext.scrollAreaRect.w - Sizes.SCROLL_BAR_SIZE, Sizes.SCROLL_BAR_SIZE);
        if (context.reveal.active)
        {
            // dfmt off
            context.offset.y =
                cast(int)(yPos
                          + height
                          + context.offset.y
                          - context.reveal.yOffset
                          - localContext.viewport.h * context.reveal.percentage)
                .clamp(0, context.scrolledContentHeight - localContext.viewport.h);
            // dfmt on
            context.reveal.active = false;
        }
        localContext.scrolledHorizontalPixels = scrolledHorizontalPixels;

        state.widgetY = yPos + height + context.offset.y;

        localContext.scrolledContentTop = state.widgetY;

        localContext.insideScrollArea = state.inRect(xPos, yPos, width, height, false);
        state.insideCurrentScroll = localContext.insideScrollArea;
        commands.addScissor(localContext.viewport);
        builder();
        state.popLayout();
        endScrollArea(context, localContext);
        return localContext.insideScrollArea;
    }

    public void revealNextElement(ref ScrollAreaContext context, float percentage = 0.5f)
    {
        context.reveal.active = true;
        context.reveal.yOffset = state.widgetY;
        context.reveal.percentage = percentage;
    }

    private auto endScrollAreaVerticalScroller(ref ScrollAreaContext context,
            ref LocalScrollAreaContext localContext, const ref ColorScheme colorScheme)
    {
        const int scrolledContentBottom = state.widgetY;
        context.scrolledContentHeight = localContext.scrolledContentTop - scrolledContentBottom;
        const scroller = localContext.verticalScrollbar.verticalScrollbarRect;
        const scrolledPixels = context.scrolledContentHeight;

        const percentageVisible = cast(float) scroller.h / cast(float) scrolledPixels;
        const visible = percentageVisible < 1;
        if (visible)
        {
            const float percentageOfStart = (cast(float)(
                    scroller.y - scrolledContentBottom) / cast(float) scrolledPixels).clamp(0.0f,
                    1.0f);

            // Handle scroll bar logic.
            const nob = Rect(scroller.x, scroller.y + cast(int)(percentageOfStart * scroller.h),
                    scroller.w, cast(int)(percentageVisible * scroller.h));

            const int range = scroller.h - (nob.h - 1);
            const uint hid = localContext.verticalScrollId;
            state.buttonLogic(hid, nob.inside(state));

            if (state.isIdActive(hid))
            {

                if (state.wentActive)
                {
                    const float u = cast(float)(nob.y - scroller.y) / cast(float) range;
                    state.drag.y = state.mouseInfo.y;
                    state.dragOrigin.y = u;
                }

                if (state.drag.y != state.mouseInfo.y)
                {
                    const float u = (state.dragOrigin.y + (
                            state.mouseInfo.y - state.drag.y) / cast(float) range).clamp(0.0f,
                            1.0f);
                    context.offset.y = cast(int)((1 - u) * (scrolledPixels - scroller.h));
                }
            }

            const RGBA color = state.isIdActive(hid) ? colorScheme.scroll.bar.thumbPress
                : (state.isIdHot(hid) ? colorScheme.scroll.bar.thumbHover
                        : colorScheme.scroll.bar.thumb);

            // vertical Bar
            // BG
            commands.addRect(scroller.x, scroller.y, scroller.w, scroller.h,
                    colorScheme.scroll.bar.back);

            commands.addRect(nob.x, nob.y, nob.w, nob.h, color);
        }
        return tuple!("pixels", "visible")(scrolledPixels, visible);
    }

    private auto endScrollAreaHorizontalScroller(ref ScrollAreaContext context,
            ref LocalScrollAreaContext localContext, const ref ColorScheme colorScheme)
    {
        const Rect scroller = localContext.horizontalScrollbar.horizontalScrollbarRect;

        const float percentageVisible = (localContext.scrolledHorizontalPixels
                ? scroller.w / localContext.scrolledHorizontalPixels.to!float : 1.0f);
        const bool visible = percentageVisible < 1;
        if (visible)
        {
            // dfmt off
            const float percentageOfStart = (
              (localContext.scrolledHorizontalPixels ? context.offset.x / localContext.scrolledHorizontalPixels.to!float : 0.0f)
            ).clamp(0, 1);
            // dfmt on

            // Handle scroll bar logic.
            const float visibleStart = percentageOfStart * (
                    localContext.scrollAreaRect.w - Sizes.SCROLL_BAR_SIZE);
            const float visibleWidth = percentageVisible * (
                    localContext.scrollAreaRect.w - Sizes.SCROLL_BAR_SIZE);
            const Rect nob = Rect(cast(int)(scroller.x + visibleStart),
                    scroller.y, cast(int) visibleWidth, scroller.h);

            const int range = scroller.w - (nob.w - 1);
            const uint hid = localContext.horizontalScrollId;
            state.buttonLogic(hid, nob.inside(state));

            if (state.isIdActive(hid))
            {

                if (state.wentActive)
                {
                    const float u = cast(float)(nob.x - scroller.x) / cast(float) range;
                    state.drag.x = state.mouseInfo.x;
                    state.dragOrigin.x = u;
                }

                if (state.drag.x != state.mouseInfo.x)
                {
                    // dfmt off
                    const float u = (state.dragOrigin.x + (state.mouseInfo.x - state.drag.x) / cast(float) range)
                        .clamp(0, 1);
                    // dfmt on
                    context.offset.x = cast(int)(
                            u * (localContext.scrolledHorizontalPixels - scroller.w));
                }
            }

            const RGBA color = state.isIdActive(hid) ? colorScheme.scroll.bar.thumbPress
                : (state.isIdHot(hid) ? colorScheme.scroll.bar.thumbHover
                        : colorScheme.scroll.bar.thumb);
            // horizontal bar
            // background
            commands.addRect(localContext.scrollAreaRect.x,
                    localContext.scrollAreaRect.y + Sizes.SCROLL_AREA_PADDING / 2,
                    localContext.scrollAreaRect.w - Sizes.SCROLL_BAR_SIZE,
                    Sizes.SCROLL_BAR_HANDLE_SIZE, colorScheme.scroll.bar.back);

            commands.addRect(nob.x, nob.y, nob.w, nob.h, color);
        }
        return tuple!("pixels", "visible")(localContext.scrolledHorizontalPixels, visible);
    }
    /**
       End the definition of the last scrollable element.

       Params:

       colorScheme = Optionally override the current default color scheme when creating this element.
    */
    private void endScrollArea(ref ScrollAreaContext context,
            ref LocalScrollAreaContext localContext,
            const ref ColorScheme colorScheme = defaultColorScheme)
    {
        // scrollbars are 2 scroll_area_paddings wide, with 0.5 before and after .. totalling 3 * scroll_area_paddings
        // on top is the header

        commands.addDisableScissor();

        const vertical = endScrollAreaVerticalScroller(context, localContext, colorScheme);
        const horizontal = endScrollAreaHorizontalScroller(context, localContext, colorScheme);

        // Handle mouse scrolling.
        if (localContext.insideScrollArea) // && !anyActive())
        {
            if (vertical.visible)
            {
                if (state.mouseInfo.dy)
                {
                    context.offset.y = (context.offset.y + 20 * state.mouseInfo.dy)
                        .clamp(0, vertical.pixels - localContext.viewport.h);
                }
            }
            if (horizontal.visible)
            {
                if (state.mouseInfo.dx)
                {
                    context.offset.x = (context.offset.x + 20 * state.mouseInfo.dx)
                        .clamp(0, horizontal.pixels - localContext.viewport.w);
                }
            }
        }

        state.insideCurrentScroll = false;
    }

    public void pushLayout(Layout layout)
    {
        state.pushLayout(layout);
    }

    public void popLayout()
    {
        state.popLayout();
    }
    /++
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
    +/
    public bool button(string label, Enabled enabled = Enabled.yes,
            const ref ColorScheme colorScheme = defaultColorScheme)
    {
        state.widgetId++;
        const uint id = (state.areaId << 16) | state.widgetId;
        const int x = state.widgetX;
        const int y = state.widgetY - Sizes.LINE_HEIGHT;
        const int w = state.widgetW;
        const int h = Sizes.LINE_HEIGHT;
        state.layout.update(state);

        if ((y > state.height) || (y + h < 0))
        {
            return false;
        }

        const bool over = enabled && state.inRect(x, y, w, h, state.inScroll);
        commands.addRoundedRect(x, y, w, h, 10, state.isIdActive(id)
                ? colorScheme.button.backPress : colorScheme.button.back);

        const RGBA color = enabled ? (state.isIdHot(id)
                ? colorScheme.button.textHover : colorScheme.button.text)
            : colorScheme.button.textDisabled;
        commands.addText(x + Sizes.LINE_HEIGHT / 2,
                y + Sizes.LINE_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
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
    public bool checkbox(const string label, bool* checkState,
            const Enabled enabled = Enabled.yes, const ref ColorScheme colorScheme = defaultColorScheme)
    {
        state.widgetId++;
        const uint id = (state.areaId << 16) | state.widgetId;

        const int x = state.widgetX;
        const int y = state.widgetY - Sizes.LINE_HEIGHT;
        const int w = state.widgetW;
        const int h = Sizes.LINE_HEIGHT;
        state.layout.update(state);
        if ((y > state.height) || (y + h < 0))
        {
            return false;
        }

        const bool over = enabled && state.inRect(x, y, w, h);
        const bool res = state.buttonLogic(id, over);

        if (res)
        {
            *checkState = !(*checkState);
        }

        const int cx = x + Sizes.LINE_HEIGHT / 2 - Sizes.CHECK_SIZE / 2;
        const int cy = y + Sizes.LINE_HEIGHT / 2 - Sizes.CHECK_SIZE / 2;

        // dfmt off
        commands.addRoundedRect(cx - 3, cy - 3,
                             Sizes.CHECK_SIZE + 6, Sizes.CHECK_SIZE + 6,
                             4, state.isIdActive(id) ? colorScheme.checkbox.press : colorScheme.checkbox.back);
        // dfmt on
        if (*checkState)
        {
            const RGBA color = enabled ? (state.isIdActive(id)
                    ? colorScheme.checkbox.checked : colorScheme.checkbox.doUncheck)
                : colorScheme.checkbox.disabledChecked;
            commands.addRoundedRect(cx, cy, Sizes.CHECK_SIZE, Sizes.CHECK_SIZE,
                    Sizes.CHECK_SIZE / 2 - 1, color);
        }

        const RGBA color = enabled ? (state.isIdHot(id)
                ? colorScheme.checkbox.textHover : colorScheme.checkbox.text)
            : colorScheme.checkbox.textDisabled;
        commands.addText(x + Sizes.LINE_HEIGHT,
                y + Sizes.LINE_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
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
        const uint id = (state.areaId << 16) | state.widgetId;

        const int x = state.widgetX;
        const int y = state.widgetY - Sizes.LINE_HEIGHT;
        const int w = state.widgetW;
        const int h = Sizes.LINE_HEIGHT;
        state.layout.update(state);

        if ((y > state.height) || (y + h < 0))
        {
            return false;
        }

        // TODO vertical clipping see button
        const bool over = enabled && state.inRect(x, y, w, h);
        const bool res = state.buttonLogic(id, over);

        if (state.isIdHot(id))
        {
            commands.addRoundedRect(x, y, w, h, 10, state.isIdActive(id)
                    ? colorScheme.item.press : colorScheme.item.hover);
        }
        commands.addText(x + Sizes.LINE_HEIGHT / 2,
                y + Sizes.LINE_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
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
        const uint id = (state.areaId << 16) | state.widgetId;

        const int x = state.widgetX;
        const int y = state.widgetY - Sizes.LINE_HEIGHT;
        const int w = state.widgetW;
        const int h = Sizes.LINE_HEIGHT;
        state.layout.update(state);

        const int cx = x + Sizes.LINE_HEIGHT / 2 - Sizes.CHECK_SIZE / 2;
        const int cy = y + Sizes.LINE_HEIGHT / 2 - Sizes.CHECK_SIZE / 2;

        const bool over = enabled && state.inRect(x, y, w, h);
        const bool res = state.buttonLogic(id, over);

        if (res)
        {
            *checkState = !(*checkState);
        }

        // dfmt off
        const RGBA color = enabled ?
            (state.isIdHot(id) ? colorScheme.collapse.textHover : colorScheme.collapse.text)
            : colorScheme.collapse.textDisabled;
        // dfmt on
        if (*checkState)
        {
            commands.addArrowRight(cx, cy, Sizes.CHECK_SIZE, Sizes.CHECK_SIZE, color);
        }
        else
        {
            commands.addArrowDown(cx, cy, Sizes.CHECK_SIZE, Sizes.CHECK_SIZE, color);
        }

        commands.addText(x + Sizes.LINE_HEIGHT,
                y + Sizes.LINE_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                TextAlign.left, label, color);

        if (subtext)
        {
            commands.addText(x + w - Sizes.LINE_HEIGHT / 2,
                    y + Sizes.LINE_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                    TextAlign.right, subtext, colorScheme.collapse.subtext);
        }
        return *checkState;
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
        const int y = state.widgetY - Sizes.LINE_HEIGHT;
        const int h = Sizes.LINE_HEIGHT;
        state.layout.update(state);
        if ((y > state.height) || (y + h < 0))
        {
            return;
        }
        commands.addText(x, y + Sizes.LINE_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
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
        const int y = state.widgetY - Sizes.LINE_HEIGHT;
        const int w = state.widgetW;
        const int h = Sizes.LINE_HEIGHT;
        state.layout.update(state);
        if ((y > state.height) || (y + h < 0))
        {
            return;
        }
        commands.addText(x + w - Sizes.LINE_HEIGHT / 2,
                y + Sizes.LINE_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                TextAlign.right, label, colorScheme.value.text);
    }

    private static string formatSliderValue(float step, float value)
    {
        int digits = cast(int)(ceil(log10(step)));
        char[16] fmtBuf;
        auto fmt = sformat(fmtBuf, "%%.%df", digits >= 0 ? 0 : -digits);
        char[32] msgBuf;
        return sformat(msgBuf, fmt, value).idup;
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
    public bool slider(string label, float* sliderState, float minValue, float maxValue, float stepValue,
            Enabled enabled = Enabled.yes, const ref ColorScheme colorScheme = defaultColorScheme)
    {
        state.widgetId++;
        const uint id = (state.areaId << 16) | state.widgetId;

        const int x = state.widgetX;
        const int y = state.widgetY - Sizes.LINE_HEIGHT;
        const int w = state.widgetW;
        const int h = Sizes.LINE_HEIGHT;
        state.layout.update(state);
        if ((y > state.height) || (y + h < 0))
        {
            return false;
        }

        commands.addRoundedRect(x, y, w, h, 4, colorScheme.slider.back);

        const int range = w - Sizes.SLIDER_MARKER_WIDTH;

        float u = ((*sliderState - minValue) / (maxValue - minValue)).clamp(0, 1);

        int m = cast(int)(u * range);

        const bool over = enabled && state.inRect(x + m, y,
                Sizes.SLIDER_MARKER_WIDTH, Sizes.LINE_HEIGHT);
        const bool res = state.buttonLogic(id, over);
        bool valChanged = false;

        if (state.isIdActive(id))
        {
            if (state.wentActive)
            {
                state.drag.x = state.mouseInfo.x;
                state.dragOrigin.x = u;
            }

            if (state.drag.x != state.mouseInfo.x)
            {
                u = (state.dragOrigin.x + cast(float)(
                        state.mouseInfo.x - state.drag.x) / cast(float) range).clamp(0, 1);

                *sliderState = minValue + u * (maxValue - minValue);
                *sliderState = floor(*sliderState / stepValue + 0.5f) * stepValue; // Snap to stepValue
                m = cast(int)(u * range);
                valChanged = true;
            }
        }

        const RGBA color = state.isIdActive(id) ? colorScheme.slider.thumbPress
            : (state.isIdHot(id) ? colorScheme.slider.thumbHover : colorScheme.slider.thumb);
        commands.addRoundedRect(x, y, Sizes.SLIDER_MARKER_WIDTH + m,
                Sizes.LINE_HEIGHT, 4, colorScheme.slider.thumb);
        commands.addRoundedRect(x + m, y, Sizes.SLIDER_MARKER_WIDTH, Sizes.LINE_HEIGHT, 4, color);

        const string message = formatSliderValue(stepValue, *sliderState);

        // dfmt off
        const RGBA sliderTextColor = enabled ?
            (state.isIdHot(id) ? colorScheme.slider.textHover : colorScheme.slider.text)
            : colorScheme.slider.textDisabled;
        const RGBA sliderValueColor = enabled ?
            (state.isIdHot(id) ? colorScheme.slider.valueHover : colorScheme.slider.value)
            : colorScheme.slider.valueDisabled;
        commands.addText(x + Sizes.LINE_HEIGHT / 2,
                         y + Sizes.LINE_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                         TextAlign.left, label, sliderValueColor);
        commands.addText(x + w - Sizes.LINE_HEIGHT / 2,
                         y + Sizes.LINE_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                         TextAlign.right, message, sliderValueColor);
        // dfmt on
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
    public bool textInput(string label, ref string buffer, bool forceInputable = false,
            const ref ColorScheme colorScheme = defaultColorScheme)
    {
        // Label
        state.widgetId++;
        uint id = (state.areaId << 16) | state.widgetId;
        int x = state.widgetX;
        int y = state.widgetY - Sizes.LINE_HEIGHT;
        commands.addText(x, y + Sizes.LINE_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                TextAlign.left, label, colorScheme.textInput.label);

        bool res = false;
        // Handle control input if any (Backspace to erase characters, Enter to confirm).
        // Backspace
        if (state.isIdInputable(id) && state.unicode == 0x08 && state.unicode != state.lastUnicode)
        {
            if (!buffer.empty)
            {
                buffer = buffer.byCodePoint.array[0 .. $ - 1].text;
            }
            state.unicode = 0;
        }
        // Pressing Enter "confirms" the input.
        else if (state.isIdInputable(id) && state.unicode == 0x0D
                && state.unicode != state.lastUnicode)
        {
            state.inputable = 0;
            res = true;
            state.unicode = 0;
        }
        else if (state.isIdInputable(id) && state.unicode == 0x27
                && state.unicode != state.lastUnicode)
        {
            state.inputable = 0;
            res = false;
            state.unicode = 0;
        }
        else if (state.isIdInputable(id) && state.unicode != 0 && state.unicode != state
                .lastUnicode)
        {
            import std.utf;

            char[4] codePoints;
            const codePointCount = std.utf.encode(codePoints, state.unicode);
            // Only add the character into the buffer if we can fit it there.
            buffer ~= codePoints[0 .. codePointCount];
            state.unicode = 0;
        }
        // Draw buffer data
        uint labelLen = cast(uint)(state.getTextLength(label) + 0.5f);
        x += labelLen;
        int w = state.widgetW - labelLen - Sizes.DEFAULT_SPACING * 2;
        int h = Sizes.LINE_HEIGHT;
        bool over = state.inRect(x, y, w, h, state.inScroll);
        state.textInputLogic(id, over, forceInputable);
        commands.addRoundedRect(x + Sizes.DEFAULT_SPACING, y, w, h, 10,
                state.isIdInputable(id) ? colorScheme.textInput.back
                : colorScheme.textInput.backDisabled);
        commands.addText(x + Sizes.DEFAULT_SPACING * 2,
                y + Sizes.LINE_HEIGHT / 2 - Sizes.TEXT_HEIGHT / 2 + Sizes.TEXT_BASELINE,
                TextAlign.left, buffer, state.isIdInputable(id)
                ? colorScheme.textInput.text : colorScheme.textInput.textDisabled);

        state.widgetY -= Sizes.LINE_HEIGHT + Sizes.DEFAULT_SPACING;
        return res;
    }

    public void hotKey(dchar key, string description, void delegate() callback)
    {
        if (description !is null)
        {
            state.add(new HotKey([key], description));
        }
        if (state.unicode == key)
        {
            callback();
            state.unicode = 0;
        }
    }

    public void hotKey(dchar[] keys, string description, void delegate() callback)
    {
        if (description !is null)
        {
            state.add(new HotKey(keys, description));
        }
        foreach (key; keys)
        {
            hotKey(key, null, callback);
        }
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
        if ((y > state.height) || (y + h < 0))
        {
            return;
        }

        commands.addRect(x, y, w, h, colorScheme.separator);
    }

    /**
       Draw text.

       Params:
       color = Optionally override the current default text color when creating this element.
    */
    public void drawText(int xPos, int yPos, TextAlign textAlign, string text,
            RGBA color = defaultColorScheme.generic.text)
    {
        commands.addText(xPos, yPos, textAlign, text, color);
    }

    /**
       Draw a line.

       Params:
       colorScheme = Optionally override the current default color scheme when creating this element.
    */
    public void drawLine(int x0, int y0, int x1, int y1, int r,
            RGBA color = defaultColorScheme.generic.line)
    {
        commands.addLine(x0, y0, x1, y1, r, color);
    }

    /**
       Draw a rectangle.

       Params:
       colorScheme = Optionally override the current default color scheme when creating this element.
    */
    public void drawRect(int xPos, int yPos, int width, int height,
            RGBA color = defaultColorScheme.generic.rect)
    {
        commands.addRect(xPos, yPos, width, height, color);
    }

    /**
       Draw a rounded rectangle.

       Params:
       colorScheme = Optionally override the current default color scheme when creating this element.
    */
    public void drawRoundedRect(int x, int y, int width, int height, int r,
            RGBA color = defaultColorScheme.generic.roundRect)
    {
        commands.addRoundedRect(x, y, width, height, r, color);
    }

    /** Render all of the batched commands for the current frame. */
    public void render()
    {
        implementation.render(commands[], state.width, state.height);
    }

}

// like std.algorithm.comparison : clamp, but border1 and border2 need not be in the right order
public T clamp(T)(const T value, const T border1, const T border2)
{
    T minValue = min(border1, border2);
    T maxValue = max(border1, border2);
    if (value < minValue)
    {
        return minValue;
    }
    else if (value > maxValue)
    {
        return maxValue;
    }
    return value;
}
