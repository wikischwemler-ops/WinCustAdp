"""Set Opera preferences that are not protected by Opera's signature.

Run only while Opera is closed, otherwise Opera overwrites the file on exit.
Called by Opera-PopupBlocker.cmd.
"""
import json
import os
import shutil
import sys

PREFS = os.path.join(os.environ["APPDATA"], "Opera Software", "Opera Stable",
                     "Default", "Preferences")

# path -> value
SETTINGS = {
    # Split screen (two tabs side by side in one window): off, and no
    # splitting when a tab is dragged onto the page.
    ("ui", "split_screen_enabled"): False,
    ("ui", "split_screen_by_drag_and_drop_enabled"): False,
}


def main() -> int:
    if not os.path.exists(PREFS):
        print(f"Opera-Profil nicht gefunden: {PREFS}")
        return 1
    with open(PREFS, encoding="utf-8") as f:
        prefs = json.load(f)
    for path, value in SETTINGS.items():
        node = prefs
        for key in path[:-1]:
            node = node.setdefault(key, {})
        node[path[-1]] = value
        print(f"{'.'.join(path)} = {json.dumps(value)}")
    shutil.copy2(PREFS, PREFS + ".wincustadp.bak")
    with open(PREFS, "w", encoding="utf-8") as f:
        json.dump(prefs, f, ensure_ascii=False, separators=(",", ":"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
