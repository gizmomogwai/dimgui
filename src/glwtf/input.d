module glwtf.input;

private
{
    import glwtf.glfw;
    import glwtf.signals;

    import std.conv : to;
}

AEventHandler cast_userptr(GLFWwindow* window)
out (result)
{
    assert(result !is null, "glfwGetWindowUserPointer returned null");
}
do
{
    void* user_ptr = glfwGetWindowUserPointer(window);
    return cast(AEventHandler) user_ptr;
}

private void function(int, string) glfw_error_callback;

void register_glfw_error_callback(void function(int, string) cb)
{
    glfw_error_callback = cb;

    glfwSetErrorCallback(&error_callback);
}

extern (C)
{
    // window events //
    void window_resize_callback(GLFWwindow* window, int width, int height) nothrow
    {
        try
        {

            AEventHandler ae = cast_userptr(window);

            ae.on_resize.emit(width, height);
        }
        catch (Exception e)
        {
            assert(0, "window close callback");
        }
    }

    void window_close_callback(GLFWwindow* window) nothrow
    {
        try
        {
            AEventHandler ae = cast_userptr(window);

            bool close = cast(int) ae._on_close();
            if (close)
            {
                ae.on_closing.emit();
            }
            else
            {
                glfwSetWindowShouldClose(window, 0);
            }
        }
        catch (Exception e)
        {
            assert(0, "window close callback");
        }
    }

    void window_refresh_callback(GLFWwindow* window) nothrow
    {
        try
        {
            AEventHandler ae = cast_userptr(window);

            ae.on_refresh.emit();
        }
        catch (Exception e)
        {
            assert(0, "window close callback");
        }
    }

    void window_focus_callback(GLFWwindow* window, int focused) nothrow
    {
        try
        {
            AEventHandler ae = cast_userptr(window);

            ae.on_focus.emit(focused == 1);
        }
        catch (Exception e)
        {
            assert(0, "window close callback");
        }

    }

    void window_iconify_callback(GLFWwindow* window, int iconified) nothrow
    {
        try
        {
            AEventHandler ae = cast_userptr(window);

            ae.on_iconify.emit(iconified == 1);
        }
        catch (Exception e)
        {
            assert(0, "window close callback");
        }

    }

    // user input //
    void key_callback(GLFWwindow* window, int key, int scancode, int state, int modifier) nothrow
    {
        try
        {
            AEventHandler ae = cast_userptr(window);

            if (state == GLFW_PRESS)
            {
                ae.on_key_down.emit(key, scancode, modifier);
            }
            else if (state == GLFW_REPEAT)
            {
                ae.on_key_repeat.emit(key, scancode, modifier);
            }
            else
            {
                ae.on_key_up.emit(key, scancode, modifier);
            }
        }
        catch (Exception e)
        {
            assert(0, "window close callback");
        }

    }

    void char_callback(GLFWwindow* window, uint c) nothrow
    {
        try
        {
            AEventHandler ae = cast_userptr(window);

            ae.on_char.emit(cast(dchar) c);
        }
        catch (Exception e)
        {
            assert(0, "window close callback");
        }

    }

    void mouse_button_callback(GLFWwindow* window, int button, int state, int modifier) nothrow
    {
        try
        {
            AEventHandler ae = cast_userptr(window);

            if (state == GLFW_PRESS)
            {
                ae.on_mouse_button_down.emit(button, modifier);
            }
            else
            {
                ae.on_mouse_button_up.emit(button, modifier);
            }
        }
        catch (Exception e)
        {
            assert(0, "window close callback");
        }

    }

    void cursor_pos_callback(GLFWwindow* window, double x, double y) nothrow
    {
        try
        {
            AEventHandler ae = cast_userptr(window);

            ae.on_mouse_pos.emit(x, y);
        }
        catch (Exception e)
        {
            assert(0, "window close callback");
        }

    }

    void scroll_callback(GLFWwindow* window, double xoffset, double yoffset) nothrow
    {
        try
        {
            AEventHandler ae = cast_userptr(window);

            ae.on_scroll.emit(xoffset, yoffset);
        }
        catch (Exception e)
        {
            assert(0, "window close callback");
        }

    }

    // misc //
    void error_callback(int errno, const(char)* errorMsg) nothrow
    {
        try
        {
            glfw_error_callback(errno, to!string(errorMsg));
        }
        catch (Exception e)
        {
            assert(0, "window close callback");
        }

    }
}

abstract class AEventHandler
{
    // window
    Signal!(int, int) on_resize;
    Signal!() on_closing;
    Signal!() on_refresh;
    Signal!(bool) on_focus;
    Signal!(bool) on_iconify;

    bool _on_close()
    {
        return true;
    }

    // input
    Signal!(int, int, int) on_key_down;
    Signal!(int, int, int) on_key_repeat;
    Signal!(int, int, int) on_key_up;
    Signal!(dchar) on_char;
    Signal!(int, int) on_mouse_button_down;
    Signal!(int, int) on_mouse_button_up;
    Signal!(double, double) on_mouse_pos;
    Signal!(double, double) on_scroll;
}

class BaseGLFWEventHandler : AEventHandler
{
    Signal!()[GLFW_KEY_LAST] single_key_down;
    Signal!()[GLFW_KEY_LAST] single_key_up;

    protected bool[GLFW_KEY_LAST] keymap;
    protected bool[GLFW_MOUSE_BUTTON_LAST] mousemap;

    this()
    {
        on_key_down.connect!"_on_key_down"(this);
        on_key_up.connect!"_on_key_up"(this);
        on_mouse_button_down.connect!"_on_mouse_button_down"(this);
        on_mouse_button_up.connect!"_on_mouse_button_up"(this);
    }

    package void register_callbacks(GLFWwindow* window)
    {
        glfwSetWindowUserPointer(window, cast(void*) this);

        glfwSetWindowSizeCallback(window, &window_resize_callback);
        glfwSetWindowCloseCallback(window, &window_close_callback);
        glfwSetWindowRefreshCallback(window, &window_refresh_callback);
        glfwSetWindowFocusCallback(window, &window_focus_callback);
        glfwSetWindowIconifyCallback(window, &window_iconify_callback);

        glfwSetKeyCallback(window, &key_callback);
        glfwSetCharCallback(window, &char_callback);
        glfwSetMouseButtonCallback(window, &mouse_button_callback);
        glfwSetCursorPosCallback(window, &cursor_pos_callback);
        glfwSetScrollCallback(window, &scroll_callback);
    }

    public void _on_key_down(int key, int scancode, int modifier)
    {
        keymap[key] = true;
        single_key_down[key].emit();
    }

    public void _on_key_up(int key, int scancode, int modifier)
    {
        keymap[key] = false;
        single_key_up[key].emit();
    }

    public void _on_mouse_button_down(int button, int modifier)
    {
        mousemap[button] = true;
    }

    public void _on_mouse_button_up(int button, int modifier)
    {
        mousemap[button] = false;
    }

    bool is_key_down(int key)
    {
        return keymap[key];
    }

    bool is_mouse_down(int button)
    {
        return mousemap[button];
    }
}
