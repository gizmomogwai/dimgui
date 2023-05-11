module window;

/**
    Contains various helpers, common code, and initialization routines.
*/

import std.algorithm : min;
import std.exception : enforce;
import std.functional : toDelegate;
import std.stdio : stderr;
import std.string : format;

import bindbc.opengl;
import bindbc.glfw;

import glwtf.input;
import glwtf.window;

///
enum WindowMode
{
    fullscreen,
    windowed,
}

/**
    Create a window, an OpenGL 3.x context, and set up some other
    common routines for error handling, window resizing, etc.
*/
Window createWindow(string windowName, WindowMode windowMode = WindowMode.windowed, int width = 1024, int height = 768)
{
    loadGLFW();
    glfwInit();
    auto vidMode = glfwGetVideoMode(glfwGetPrimaryMonitor());

    // constrain the window size so it isn't larger than the desktop size.
    width = min(width, vidMode.width);
    height = min(height, vidMode.height);

    // set the window to be initially inivisible since we're repositioning it.
    glfwWindowHint(GLFW_VISIBLE, 0);

    // enable debugging
    glfwWindowHint(GLFW_OPENGL_DEBUG_CONTEXT, 1);

    Window window = createWindowContext(windowName, WindowMode.windowed, width, height);

    // center the window on the screen
    glfwSetWindowPos(window.window, (vidMode.width - width) / 2, (vidMode.height - height) / 2);

    // glfw-specific error routine (not a generic GL error handler)
    register_glfw_error_callback(&glfwErrorCallback);

    // anti-aliasing number of samples.
    window.samples = 4;

    // activate an opengl context.
    window.make_context_current();

    loadOpenGL();

    enforce(glGenBuffers !is null);

    // turn v-sync off.
    glfwSwapInterval(0);

    // finally show the window
    glfwShowWindow(window.window);

    return window;
}

/** Create a window and an OpenGL context. */
Window createWindowContext(string windowName, WindowMode windowMode, int width, int height)
{
    auto window = new Window();
    auto monitor = windowMode == WindowMode.fullscreen ? glfwGetPrimaryMonitor() : null;
    auto context = window.create_highest_available_context(width, height, windowName, monitor, null, GLFW_OPENGL_CORE_PROFILE);

    // ensure we've loaded a proper context
    enforce(context.major >= 3);

    return window;
}

/** Just emit errors to stderr on GLFW errors. */
void glfwErrorCallback(int code, string msg)
{
    stderr.writefln("Error (%s): %s", code, msg);
}

///
class GLException : Exception
{
    @safe pure nothrow this(string msg = "", string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        super(msg, file, line, next);
    }

    @safe pure nothrow this(string msg, Throwable next, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line, next);
    }
}

/**
    GL_ARB_debug_output or GL_KHR_debug callback.

    Throwing exceptions across language boundaries is ok as
    long as $(B GL_DEBUG_OUTPUT_SYNCHRONOUS_ARB) is enabled.
*/
extern (System)
private void glErrorCallback(GLenum source, GLenum type, GLuint id, GLenum severity, GLsizei length, in GLchar* message, GLvoid* userParam)
{
    //string msg = format("glErrorCallback: source: %s, type: %s, id: %s, severity: %s, length: %s, message: %s, userParam: %s",
    //                     source, type, id, severity, length, message.to!string, userParam);

    //stderr.writeln(msg);
}
