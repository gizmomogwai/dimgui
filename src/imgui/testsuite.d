module imgui.testsuite;

import unit_threaded : runTestsMain;

// dfmt off
mixin runTestsMain!(
    "imgui.api",
    "imgui.colorscheme",
);
// dfmt on
