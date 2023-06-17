module demo;

import std.exception;
import std.file;
import std.path;
import std.stdio;
import std.string;

import bindbc.opengl;
import bindbc.glfw;

import imgui;
import window;

struct GUI
{
    ImGui gui;
    Window window;
    this(Window window)
    {
        this.window = window;
        string fontPath = thisExePath().dirName().buildPath("../").buildPath("DroidSans.ttf");
        gui = new ImGui(fontPath);
    }

    string lastInfo;

    void render()
    {
        glClearColor(0.8f, 0.8f, 0.8f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glDisable(GL_DEPTH_TEST);

        auto mouse = window.getMouseInfo();
        auto scrollInfo = window.getAndResetScrollInfo();
        gui.frame(
            MouseInfo(mouse.x, mouse.y, mouse.button, cast(int) scrollInfo.xOffset, cast(int) scrollInfo.yOffset),
            window.width, window.height, 0, () {
        enum BORDER = 10;
        int x = BORDER;
        static ScrollAreaContext scrollArea1;
        enum scrollArea1W = 400;

        gui.scrollArea(scrollArea1, "Scroll area 1", x, BORDER, scrollArea1W,
                window.height - 2 * BORDER, () {
            x += scrollArea1W;

            if (gui.button("Button"))
            {
                writeln("button pressed");
            }

            gui.button("Disabled button", Enabled.no);
            gui.item("Item");
            gui.item("Disabled item", Enabled.no);
            for (int i = 0; i < 1000; ++i)
            {
                gui.item("Item %s".format(i), Enabled.no);
            }
            /+
        if (imguiCheck("Checkbox", &checkState1))
            lastInfo = "Toggled the checkbox to: '%s'".format(checkState1 ? "On" : "Off");

        // should not be clickable
        enforce(!imguiCheck("Inactive disabled checkbox", &checkState2, Enabled.no));

        enforce(!imguiCheck("Inactive enabled checkbox", &checkState3, Enabled.no));

        if (imguiTextInput("Text input:", textInputBuffer, textEntered))
        {
            lastTextEntered = textEntered.idup;
            textEntered = textInputBuffer[0 .. 0];
        }
        imguiLabel("Entered text: " ~ lastTextEntered);

        if (imguiCollapse("Collapse", collapseState1 ? "max" : "min", &collapseState1))
            lastInfo = "subtext changed to: '%s'".format(collapseState1 ? "Maximized" : "Minimized");

        if (collapseState1)
        {
            imguiIndent();
            imguiLabel("Collapsable element 1");
            imguiLabel("Collapsable element 2");
            imguiItem("Collapsable item 1");
            imguiItem("Collapsable item 2");
            imguiUnindent();
        }

        // should not be clickable
        enforce(!imguiCollapse("Disabled collapse", "subtext", &collapseState2, Enabled.no));

        imguiLabel("Label");
        imguiValue("Value");

        imguiLabel("Unicode characters");
        imguiValue("한글 é ý ú í ó á š žöäü");

        if (imguiSlider("Slider", &sliderValue1, 0.0, 100.0, 1.0f))
            lastInfo = "Slider clicked, current value is: '%s'".format(sliderValue1);

        // should not be clickable
        enforce(!imguiSlider("Disabled slider", &sliderValue2, 0.0, 100.0, 1.0f, Enabled.no));

        imguiIndent();
        imguiLabel("Indented");
        imguiUnindent();
        imguiLabel("Unindented");

        imguiEndScrollArea();

        xCursor += 10;
        imguiBeginScrollArea("Scroll area 2", xCursor, 10, scrollAreaWidth,
                scrollAreaHeight, &scrollArea2);
        xCursor += scrollAreaWidth;
        imguiSeparatorLine();
        imguiSeparator();

        foreach (i; 0 .. 100)
        {
            imguiLabel("A wall of text %s".format(i));
        }

        imguiEndScrollArea();

        xCursor += 10;
        imguiBeginScrollArea("Scroll area 3", xCursor, 10, scrollAreaWidth,
                scrollAreaHeight, &scrollArea3);
        xCursor += scrollAreaWidth;
        imguiLabel(lastInfo);
        imguiEndScrollArea();

        xCursor += 10;
        imguiBeginScrollArea("Scroll area 4", xCursor, 10, scrollAreaWidth,
                scrollAreaHeight, &scrollArea4, true, 2000);
        xCursor += scrollAreaWidth;
        for (int i = 0; i < 100; ++i)
        {
            imguiLabel("long text abcdefghijklmnopqrstuvwxyz %d".format(i));
        }
        +/
        });

        x += BORDER;
        static ScrollAreaContext scrollArea2;
        int scrollArea2W = 400;
        gui.scrollArea(scrollArea2, "Collapsible", x, BORDER, scrollArea2W,
                window.height - 2 * BORDER, () {
            static bool collapsed = false;
            gui.collapse("Test1", "Test2", &collapsed);
            if (!collapsed)
            {
                for (int i = 0; i < 10; ++i)
                {
                    gui.button("Button %s".format(i));
                }
            }
        });
            });

        /+
        const graphicsXPos = xCursor + 10;

        imguiDrawText(graphicsXPos, scrollAreaHeight, TextAlign.left,
                "Free text", RGBA(32, 192, 32, 192));
        imguiDrawText(graphicsXPos + 100, windowHeight - 40, TextAlign.right,
                "Free text", RGBA(32, 32, 192, 192));
        imguiDrawText(graphicsXPos + 50, windowHeight - 60, TextAlign.center,
                "Free text", RGBA(192, 32, 32, 192));

        imguiDrawLine(graphicsXPos, windowHeight - 80, graphicsXPos + 100,
                windowHeight - 60, 1.0f, RGBA(32, 192, 32, 192));
        imguiDrawLine(graphicsXPos, windowHeight - 100, graphicsXPos + 100,
                windowHeight - 80, 2.0, RGBA(32, 32, 192, 192));
        imguiDrawLine(graphicsXPos, windowHeight - 120, graphicsXPos + 100,
                windowHeight - 100, 3.0, RGBA(192, 32, 32, 192));

        imguiDrawRoundedRect(graphicsXPos, windowHeight - 240, 100, 100, 5.0,
                RGBA(32, 192, 32, 192));
        imguiDrawRoundedRect(graphicsXPos, windowHeight - 350, 100, 100, 10.0,
                RGBA(32, 32, 192, 192));
        imguiDrawRoundedRect(graphicsXPos, windowHeight - 470, 100, 100, 20.0,
                RGBA(192, 32, 32, 192));

        imguiDrawRect(graphicsXPos, windowHeight - 590, 100, 100, RGBA(32, 192, 32, 192));
        imguiDrawRect(graphicsXPos, windowHeight - 710, 100, 100, RGBA(32, 32, 192, 192));
        imguiDrawRect(graphicsXPos, windowHeight - 830, 100, 100, RGBA(192, 32, 32, 192));

        +/
        gui.render();
    }
}

int main(string[] args)
{
    int width = 1024, height = 768;

    Window window = new Window((Window w, int key, int /+scancode+/ , int action, int /+mods+/ ) {
        if ((key == '1') && (action == GLFW_RELEASE))
        {
            writeln("1 pressed");
            return;
        }
    });
    scope (exit)
    {
        // destroy(window);
        glfwTerminate();
    }

    GUI gui = GUI(window);

    //glfwSwapInterval(1);

    while (!window.window.glfwWindowShouldClose())
    {
        gui.render();

        /* Swap front and back buffers. */
        window.window.glfwSwapBuffers();

        /* Poll for and process events. */
        glfwPollEvents();
    }

    // Clean UI
    imguiDestroy();

    return 0;
}
