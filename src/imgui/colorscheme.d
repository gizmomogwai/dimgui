module imgui.colorscheme;
/** A color scheme contains all the configurable GUI element colors. */
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
    RGBA*[] walkColors() return
    {
        RGBA*[] colors;
        static void collect(T)(ref T aggregate, ref RGBA*[] colors)
        {
            foreach (ref field; aggregate.tupleof)
            {
                static if (is(typeof(field) == RGBA))
                {
                    colors ~= &field;
                }
                else static if (is(typeof(field) == struct))
                {
                    collect(field, colors);
                }
            }
        }

        collect(this, colors);
        return colors;
    }

    ///
    static struct Generic
    {
        RGBA text = RGBA(255, 255, 255, 200); /// Used by imguiDrawText.
        RGBA line = RGBA(255, 255, 255, 96); /// Used by imguiDrawLine.
        RGBA rect = RGBA(128, 128, 128, 96); /// Used by imguiDrawRect.
        RGBA roundRect = RGBA(128, 128, 128, 96); /// Used by imguiDrawRoundedRect.
        RGBA background = RGBA(31, 33, 38); /// Window clear color.
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
        RGBA textMatch = RGBA(255, 200, 90); /// Highlighted characters, e.g. search matches.
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
ColorScheme defaultColorScheme;

/**
    The Zenburn palette of the Emacs theme (zenburn-default-colors-alist,
    https://github.com/bbatsov/zenburn-emacs, version 2.11.0).

    `Plus` suffixes are lighter, `Minus` suffixes darker variants.
*/
struct ZenburnPalette
{
    enum foregroundMinus1 = RGBA(0x65, 0x65, 0x55);
    enum foregroundMinus05 = RGBA(0x98, 0x98, 0x90);
    enum foreground = RGBA(0xDC, 0xDC, 0xCC);
    enum foregroundPlus1 = RGBA(0xFF, 0xFF, 0xEF);
    enum foregroundPlus2 = RGBA(0xFF, 0xFF, 0xFD);
    enum backgroundMinus2 = RGBA(0x00, 0x00, 0x00);
    enum backgroundMinus1 = RGBA(0x2B, 0x2B, 0x2B);
    enum backgroundMinus08 = RGBA(0x30, 0x30, 0x30);
    enum backgroundMinus05 = RGBA(0x38, 0x38, 0x38);
    enum background = RGBA(0x3F, 0x3F, 0x3F);
    enum backgroundPlus05 = RGBA(0x49, 0x49, 0x49);
    enum backgroundPlus1 = RGBA(0x4F, 0x4F, 0x4F);
    enum backgroundPlus2 = RGBA(0x5F, 0x5F, 0x5F);
    enum backgroundPlus3 = RGBA(0x6F, 0x6F, 0x6F);
    enum redMinus6 = RGBA(0x6C, 0x33, 0x33);
    enum redMinus5 = RGBA(0x7C, 0x43, 0x43);
    enum redMinus4 = RGBA(0x8C, 0x53, 0x53);
    enum redMinus3 = RGBA(0x9C, 0x63, 0x63);
    enum redMinus2 = RGBA(0xAC, 0x73, 0x73);
    enum redMinus1 = RGBA(0xBC, 0x83, 0x83);
    enum red = RGBA(0xCC, 0x93, 0x93);
    enum redPlus1 = RGBA(0xDC, 0xA3, 0xA3);
    enum redPlus2 = RGBA(0xEC, 0xB3, 0xB3);
    enum orange = RGBA(0xDF, 0xAF, 0x8F);
    enum yellowMinus2 = RGBA(0xD0, 0xBF, 0x8F);
    enum yellowMinus1 = RGBA(0xE0, 0xCF, 0x9F);
    enum yellow = RGBA(0xF0, 0xDF, 0xAF);
    enum greenMinus5 = RGBA(0x2F, 0x4F, 0x2F);
    enum greenMinus4 = RGBA(0x3F, 0x5F, 0x3F);
    enum greenMinus3 = RGBA(0x4F, 0x6F, 0x4F);
    enum greenMinus2 = RGBA(0x5F, 0x7F, 0x5F);
    enum greenMinus1 = RGBA(0x6F, 0x8F, 0x6F);
    enum green = RGBA(0x7F, 0x9F, 0x7F);
    enum greenPlus1 = RGBA(0x8F, 0xB2, 0x8F);
    enum greenPlus2 = RGBA(0x9F, 0xC5, 0x9F);
    enum greenPlus3 = RGBA(0xAF, 0xD8, 0xAF);
    enum greenPlus4 = RGBA(0xBF, 0xEB, 0xBF);
    enum cyan = RGBA(0x93, 0xE0, 0xE3);
    enum bluePlus3 = RGBA(0xBD, 0xE0, 0xF3);
    enum bluePlus2 = RGBA(0xAC, 0xE0, 0xE3);
    enum bluePlus1 = RGBA(0x94, 0xBF, 0xF3);
    enum blue = RGBA(0x8C, 0xD0, 0xD3);
    enum blueMinus1 = RGBA(0x7C, 0xB8, 0xBB);
    enum blueMinus2 = RGBA(0x6C, 0xA0, 0xA3);
    enum blueMinus3 = RGBA(0x5C, 0x88, 0x8B);
    enum blueMinus4 = RGBA(0x4C, 0x70, 0x73);
    enum blueMinus5 = RGBA(0x36, 0x60, 0x60);
    enum magenta = RGBA(0xDC, 0x8C, 0xC3);
}

/**
    Zenburn color scheme built from `ZenburnPalette`.

    Like the Emacs theme, all colors are opaque: backgrounds are
    neutral greys and accent colors are used for text only. Activate it
    with `defaultColorScheme = zenburnColorScheme;` or pass it per widget.
*/
immutable ColorScheme zenburnColorScheme = () {
    ColorScheme scheme;
    with (ZenburnPalette)
    {
        with (scheme)
        {
            generic.text = foreground;
            generic.line = backgroundPlus3;
            generic.rect = backgroundPlus1;
            generic.roundRect = backgroundPlus1;
            generic.background = background;

            // Emacs mode-line / header-line: bg-1 with yellow title.
            scroll.area.back = backgroundMinus1;
            scroll.area.text = yellow;
            scroll.bar.back = background;
            scroll.bar.thumb = backgroundPlus3;
            scroll.bar.thumbHover = foregroundMinus05;
            scroll.bar.thumbPress = foreground;

            button.text = foreground;
            button.textHover = yellow;
            button.textDisabled = foregroundMinus1;
            button.back = backgroundPlus1;
            button.backPress = backgroundPlus2;

            textInput.label = foreground;
            textInput.text = foreground;
            textInput.textDisabled = foregroundMinus05;
            textInput.back = backgroundPlus1;
            textInput.backDisabled = backgroundPlus05;

            checkbox.back = backgroundPlus1;
            checkbox.press = backgroundPlus2;
            checkbox.checked = foreground;
            checkbox.doUncheck = foregroundMinus05;
            checkbox.disabledChecked = foregroundMinus1;
            checkbox.text = foreground;
            checkbox.textHover = yellow;
            checkbox.textDisabled = foregroundMinus1;

            // Emacs hl-line and region.
            item.hover = backgroundPlus05;
            item.press = backgroundPlus2;
            item.text = foreground;
            item.textDisabled = foregroundMinus1;
            item.textMatch = yellow;

            collapse.shown = foreground;
            collapse.hidden = foreground;
            collapse.doShow = yellow;
            collapse.doHide = yellow;
            collapse.text = foreground;
            collapse.textHover = yellow;
            collapse.textDisabled = foregroundMinus1;
            collapse.subtext = green;

            label.text = foreground;
            value.text = foreground;

            slider.back = background;
            slider.thumb = backgroundPlus2;
            slider.thumbHover = backgroundPlus3;
            slider.thumbPress = foregroundMinus05;
            slider.text = foreground;
            slider.textHover = yellow;
            slider.textDisabled = foregroundMinus1;
            slider.value = foreground;
            slider.valueHover = yellow;
            slider.valueDisabled = foregroundMinus1;

            separator = backgroundPlus2;
        }
    }
    return scheme;
}();

@("Zenburn scheme builds at compile time") unittest
{
    assert(zenburnColorScheme.button.text == RGBA(0xDC, 0xDC, 0xCC));
}

@("walkColors reaches every color, including nested ones") unittest
{
    ColorScheme scheme;
    foreach (color; scheme.walkColors)
    {
        *color = RGBA(1, 2, 3);
    }
    assert(scheme.textInput.back == RGBA(1, 2, 3));
    assert(scheme.scroll.bar.thumb == RGBA(1, 2, 3));
    assert(scheme.separator == RGBA(1, 2, 3));
}

@("Zenburn palette has all 48 Emacs colors") unittest
{
    static assert(__traits(allMembers, ZenburnPalette).length == 48);
    assert(ZenburnPalette.redMinus6 == RGBA(0x6C, 0x33, 0x33));
    assert(ZenburnPalette.magenta == RGBA(0xDC, 0x8C, 0xC3));
}
