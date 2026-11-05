"""Check the plugin's lookup against the installed compositor's real exports.

Hyprland's findFunctionsByName matches mangled names, not demangled names.
This catches a build that succeeds but cannot find its drag hook at load time.
"""
from pathlib import Path
import re
import subprocess


def main():
    source = Path(__file__).with_name("fullscreen-lock.cpp").read_text()
    queries = re.findall(r'findFunctionsByName\(handle, "([^"]+)"\)', source)
    assert queries, "No compositor hook lookup found"
    symbols = subprocess.check_output(["nm", "-D", "-j", "/usr/bin/Hyprland"], text=True).splitlines()
    for query in queries:
        matches = [symbol for symbol in symbols if query in symbol]
        assert matches, f"Hook lookup {query!r} matches no installed compositor symbols"
        decoded = subprocess.check_output(["c++filt", *matches], text=True).splitlines()
        prefixes = {
            'dragBegin': 'Layout::Supplementary::CDragStateController::dragBegin(',
            'setCursorIconOnBorder': 'CInputManager::setCursorIconOnBorder(',
            'setOverride': 'Pointer::Cursor::CShapeOverrideController::setOverride(',
            'requestClientFullscreen': 'Desktop::View::CWindow::requestClientFullscreen(',
        }
        expected = [name for name in decoded if name.startswith(prefixes[query])
                    and (query != 'dragBegin' or 'std::optional<Layout::eRectCorner>' in name)]
        assert len(expected) == 1, f"Expected one compatible {query} hook, found {expected}"
    print("Installed Hyprland drag and cursor hook symbols: passed")


if __name__ == "__main__":
    main()
