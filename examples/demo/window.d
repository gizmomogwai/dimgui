/+ helper to work with glfw +/
module window;

import std.algorithm : min;
import std.exception : enforce;
import std.functional : toDelegate;
import std.stdio : stderr;
import std.string : format;

import bindbc.opengl : loadOpenGL, GL_TRUE, GLSupport;
import bindbc.glfw : GLFWwindow, glfwGetCursorPos, loadGLFW, glfwSupport,
    glfwGetWindowSize, glfwGetFramebufferSize, GLFW_PRESS, glfwInit,
    glfwGetVideoMode, glfwGetMouseButton, GLFW_MOUSE_BUTTON_LEFT,
    GLFW_MOUSE_BUTTON_RIGHT, glfwGetPrimaryMonitor, glfwWindowHint;
import bindbc.glfw : GLFW_VISIBLE, GLFW_OPENGL_DEBUG_CONTEXT, GLFW_CONTEXT_VERSION_MAJOR, GLFW_CONTEXT_VERSION_MINOR,
    GLFW_OPENGL_FORWARD_COMPAT, GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE, glfwCreateWindow;
import bindbc.glfw : glfwSetWindowUserPointer, glfwSetFramebufferSizeCallback,
    glfwSetWindowSize, glfwSetScrollCallback, glfwSetWindowPos,
    glfwMakeContextCurrent, glfwSwapInterval, glfwShowWindow, glfwGetWindowUserPointer;

void loadBindBCGlfw()
{
    import bindbc.loader.sharedlib;

    const result = loadGLFW();
    if (result != glfwSupport)
    {
        string errorMessage = "Cannot load glfw:";
        foreach (info; bindbc.loader.sharedlib.errors)
        {
            import std.conv : to;

            errorMessage ~= "\n  %s".format(info.message.to!string);
        }
        throw new Exception(errorMessage);
    }
}

class Window
{
    struct MouseInfo
    {
        int x;
        int y;
        ubyte button;
    }

    struct ScrollInfo
    {
        double xOffset;
        double yOffset;
        void reset()
        {
            xOffset = 0;
            yOffset = 0;
        }
    }

    GLFWwindow* window;
    int width;
    int height;
    ScrollInfo scroll;
    alias KeyCallback = void delegate(Window w, int key, int scancode, int action, int mods);
    KeyCallback keyCallback;

    ScrollInfo getAndResetScrollInfo()
    {
        ScrollInfo res = scroll;
        scroll.reset;
        return res;
    }

    MouseInfo getMouseInfo()
    {
        double mouseX;
        double mouseY;
        window.glfwGetCursorPos(&mouseX, &mouseY);

        static double mouseXToWindowFactor = 0;
        static double mouseYToWindowFactor = 0;
        if (mouseXToWindowFactor == 0) // need to initialize
        {
            int virtualWindowWidth;
            int virtualWindowHeight;
            window.glfwGetWindowSize(&virtualWindowWidth, &virtualWindowHeight);
            if (virtualWindowWidth != 0 && virtualWindowHeight != 0)
            {
                int frameBufferWidth;
                int frameBufferHeight;
                window.glfwGetFramebufferSize(&frameBufferWidth, &frameBufferHeight);
                mouseXToWindowFactor = double(frameBufferWidth) / virtualWindowWidth;
                mouseYToWindowFactor = double(frameBufferHeight) / virtualWindowHeight;
            }
        }
        mouseX *= mouseXToWindowFactor;
        mouseY *= mouseYToWindowFactor;

        ubyte buttonState = 0;
        buttonState |= window.glfwGetMouseButton(GLFW_MOUSE_BUTTON_LEFT) == GLFW_PRESS ? 0x1 : 0x0;
        buttonState |= window.glfwGetMouseButton(GLFW_MOUSE_BUTTON_RIGHT) == GLFW_PRESS ? 0x2 : 0x0;
        return MouseInfo(cast(int) mouseX, height - cast(int) mouseY, buttonState);
    }

    this(KeyCallback keyCallback, int width = 800, int height = 600)
    {
        import std.stdio : writeln;

        this.keyCallback = keyCallback;
        loadBindBCGlfw();
        glfwInit();

        auto vidMode = glfwGetVideoMode(glfwGetPrimaryMonitor());
        this.width = min(width, vidMode.width);
        this.height = min(height, vidMode.height);
        writeln(vidMode.width);
        // set the window to be initially inivisible since we're repositioning it.
        glfwWindowHint(GLFW_VISIBLE, 0);

        // enable debugging
        glfwWindowHint(GLFW_OPENGL_DEBUG_CONTEXT, 1);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
        glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

        window = glfwCreateWindow(width, height, "test", null, null);
        enforce(window);
        window.glfwSetWindowUserPointer(cast(void*) this);
        //window.glfwSetKeyCallback(&staticKeyCallback);
        window.glfwSetFramebufferSizeCallback(&staticSizeCallback);
        window.glfwSetWindowSize(width, height);
        window.glfwSetScrollCallback(&staticScrollCallback);

        int w, h;
        window.glfwGetFramebufferSize(&w, &h);
        staticSizeCallback(window, w, h);

        // center the window on the screen
        window.glfwSetWindowPos((vidMode.width - width) / 2, (vidMode.height - height) / 2);

        // activate an opengl context.
        window.glfwMakeContextCurrent();
        enforce(GLSupport.gl33 == loadOpenGL());

        // turn v-sync off.
        glfwSwapInterval(0);

        // finally show the window
        window.glfwShowWindow();
    }

    void scrollCallback(double xOffset, double yOffset)
    {
        this.scroll.xOffset = -xOffset;
        this.scroll.yOffset = -yOffset;
    }

    void sizeCallback(int width, int height)
    {
        this.width = width;
        this.height = height;
        import std.stdio : writeln;

        writeln("width=", this.width, " height=", this.height);
    }
}

extern (C)
{
    void staticKeyCallback(GLFWwindow* window, int key, int scancode, int action, int mods) nothrow
    {
        try
        {
            auto w = cast(Window) window.glfwGetWindowUserPointer();
            w.keyCallback(w, key, scancode, action, mods);
        }
        catch (Throwable t)
        {
            assert(0);
        }
    }

    void staticScrollCallback(GLFWwindow* window, double xOffset, double yOffset) nothrow
    {
        try
        {
            auto w = cast(Window) window.glfwGetWindowUserPointer;
            w.scrollCallback(xOffset, yOffset);
        }
        catch (Throwable t)
        {
            assert(0);
        }
    }

    void staticSizeCallback(GLFWwindow* window, int width, int height) nothrow
    {
        try
        {
            auto w = cast(Window) window.glfwGetWindowUserPointer();
            w.sizeCallback(width, height);
        }
        catch (Throwable t)
        {
            assert(0);
        }
    }
}
