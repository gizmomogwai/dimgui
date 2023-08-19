module imgui.colorscheme;
/** A color scheme contains all the configurable GUI element colors. */
import std.range : chain, only;

///
struct RGBA
{
    ubyte r;
    ubyte g;
    ubyte b;
    ubyte a = 255;

    RGBA opBinary(string op)(RGBA rgba)
    {
        RGBA res = this;

        mixin("res.r = cast(ubyte)res.r " ~ op ~ " rgba.r;");
        mixin("res.g = cast(ubyte)res.g " ~ op ~ " rgba.g;");
        mixin("res.b = cast(ubyte)res.b " ~ op ~ " rgba.b;");
        mixin("res.a = cast(ubyte)res.a " ~ op ~ " rgba.a;");

        return res;
    }
}

struct ColorScheme
{
    /**
        Return a range of all colors. This gives you ref access,
        which means you can modify the values.
    */
    auto walkColors()
    {
        return chain((&generic.text).only, (&generic.line).only,
                (&generic.rect).only, (&generic.roundRect).only,
                (&scroll.area.back).only, (&scroll.area.text).only,
                (&scroll.bar.back).only, (&scroll.bar.thumb).only,
                (&scroll.bar.thumbHover).only, (&scroll.bar.thumbPress).only,
                (&button.text).only, (&button.textHover).only,
                (&button.textDisabled).only, (&button.back).only,
                (&button.backPress).only, (&checkbox.back).only,
                (&checkbox.press).only, (&checkbox.checked).only,
                (&checkbox.doUncheck).only, (&checkbox.disabledChecked).only,
                (&checkbox.text).only, (&checkbox.textHover).only,
                (&checkbox.textDisabled).only, (&item.hover).only,
                (&item.press).only, (&item.text).only, (&item.textDisabled)
                    .only, (&collapse.shown).only, (&collapse.hidden).only,
                (&collapse.doShow).only, (&collapse.doHide).only,
                (&collapse.textHover).only, (&collapse.text).only,
                (&collapse.textDisabled).only, (&collapse.subtext).only,
                (&label.text).only, (&value.text).only, (&slider.back).only,
                (&slider.thumb).only, (&slider.thumbHover).only,
                (&slider.thumbPress).only, (&slider.text).only,
                (&slider.textHover).only, (&slider.textDisabled).only,
                (&slider.value).only, (&slider.valueHover).only,
                (&slider.valueDisabled).only, (&separator).only);
    }

    ///
    static struct Generic
    {
        RGBA text; /// Used by imguiDrawText.
        RGBA line; /// Used by imguiDrawLine.
        RGBA rect; /// Used by imguiDrawRect.
        RGBA roundRect; /// Used by imguiDrawRoundedRect.
    }

    ///
    static struct Scroll
    {
        ///
        static struct Area
        {
            RGBA back = RGBA(0, 0, 0, 192);
            RGBA text = RGBA(255, 255, 255, 128);
        }

        ///
        static struct Bar
        {
            RGBA back = RGBA(0, 0, 0, 196);
            RGBA thumb = RGBA(255, 255, 255, 64);
            RGBA thumbHover = RGBA(255, 196, 0, 96);
            RGBA thumbPress = RGBA(255, 196, 0, 196);
        }

        Area area; ///
        Bar bar; ///
    }

    ///
    static struct Button
    {
        RGBA text = RGBA(255, 255, 255, 200);
        RGBA textHover = RGBA(255, 196, 0, 255);
        RGBA textDisabled = RGBA(128, 128, 128, 200);
        RGBA back = RGBA(128, 128, 128, 96);
        RGBA backPress = RGBA(128, 128, 128, 196);
    }

    ///
    static struct TextInput
    {
        RGBA label = RGBA(255, 255, 255, 255);
        RGBA text = RGBA(0, 0, 0, 255);
        RGBA textDisabled = RGBA(255, 255, 255, 255);
        RGBA back = RGBA(255, 196, 0, 255);
        RGBA backDisabled = RGBA(128, 128, 128, 96);
    }

    ///
    static struct Checkbox
    {
        /// Checkbox background.
        RGBA back = RGBA(128, 128, 128, 96);

        /// Checkbox background when it's pressed.
        RGBA press = RGBA(128, 128, 128, 196);

        /// An enabled and checked checkbox.
        RGBA checked = RGBA(255, 255, 255, 255);

        /// An enabled and checked checkbox which was just pressed to be disabled.
        RGBA doUncheck = RGBA(255, 255, 255, 200);

        /// A disabled but checked checkbox.
        RGBA disabledChecked = RGBA(128, 128, 128, 200);

        /// Label color of the checkbox.
        RGBA text = RGBA(255, 255, 255, 200);

        /// Label color of a hovered checkbox.
        RGBA textHover = RGBA(255, 196, 0, 255);

        /// Label color of an disabled checkbox.
        RGBA textDisabled = RGBA(128, 128, 128, 200);
    }

    ///
    static struct Item
    {
        RGBA hover = RGBA(255, 196, 0, 96);
        RGBA press = RGBA(255, 196, 0, 196);
        RGBA text = RGBA(255, 255, 255, 200);
        RGBA textDisabled = RGBA(128, 128, 128, 200);
    }

    ///
    static struct Collapse
    {
        RGBA shown = RGBA(255, 255, 255, 200);
        RGBA hidden = RGBA(255, 255, 255, 200);

        RGBA doShow = RGBA(255, 196, 0, 255);
        RGBA doHide = RGBA(255, 196, 0, 255);

        RGBA text = RGBA(255, 255, 255, 200);
        RGBA textHover = RGBA(255, 196, 0, 255);
        RGBA textDisabled = RGBA(128, 128, 128, 200);

        RGBA subtext = RGBA(255, 255, 255, 128);
    }

    ///
    static struct Label
    {
        RGBA text = RGBA(255, 255, 255, 255);
    }

    ///
    static struct Value
    {
        RGBA text = RGBA(255, 255, 255, 200);
    }

    ///
    static struct Slider
    {
        RGBA back = RGBA(0, 0, 0, 128);
        RGBA thumb = RGBA(255, 255, 255, 64);
        RGBA thumbHover = RGBA(255, 196, 0, 128);
        RGBA thumbPress = RGBA(255, 255, 255, 255);

        RGBA text = RGBA(255, 255, 255, 200);
        RGBA textHover = RGBA(255, 196, 0, 255);
        RGBA textDisabled = RGBA(128, 128, 128, 200);

        RGBA value = RGBA(255, 255, 255, 200);
        RGBA valueHover = RGBA(255, 196, 0, 255);
        RGBA valueDisabled = RGBA(128, 128, 128, 200);
    }

    /// Colors for the generic imguiDraw* functions.
    Generic generic;

    /// Colors for the scrollable area.
    Scroll scroll;

    /// Colors for button elements.
    Button button;

    /// Colors for text input elements.
    TextInput textInput;

    /// Colors for checkbox elements.
    Checkbox checkbox;

    /// Colors for item elements.
    Item item;

    /// Colors for collapse elements.
    Collapse collapse;

    /// Colors for label elements.
    Label label;

    /// Colors for value elements.
    Value value;

    /// Colors for slider elements.
    Slider slider;

    /// Color for the separator line.
    RGBA separator = RGBA(255, 255, 255, 32);
}

/**
    The current default color scheme.

    You can configure this scheme, it will be used by
    default by GUI element creation functions unless
    you explicitly pass a custom color scheme.
*/
__gshared ColorScheme defaultColorScheme;
