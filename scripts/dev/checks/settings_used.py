"""Check #12: every declared setting must actually be read somewhere.

A key in `Settings.DEFAULTS` that no other script ever queries is a feature the player
can change with no effect - `left_handed` and `show_fps` were both in that state.
"""
import glob
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'


def main():
    sm = os.path.join(ROOT, 'scripts/core/settings_manager.gd')
    src = open(sm, encoding='utf-8').read()
    block = src.split('const DEFAULTS := {')[1].split('}')[0]
    keys = re.findall(r'"(\w+)":', block)
    others = []
    for f in glob.glob(os.path.join(ROOT, 'scripts/**/*.gd'), recursive=True):
        if f.endswith('settings_manager.gd'):
            continue
        others.append(open(f, encoding='utf-8').read())
    # The settings PANEL is excluded because it offers every key and would therefore
    # mask a dead one. The manager itself counts: `apply_all()`/`apply_graphics()`
    # legitimately consume volumes, fps_limit and render_scale.
    readers = [src]
    for f in glob.glob(os.path.join(ROOT, 'scripts/**/*.gd'), recursive=True):
        if f.endswith('settings_manager.gd') or f.endswith('settings_panel.gd'):
            continue
        readers.append(open(f, encoding='utf-8').read())
    def without_defaults(text):
        """Remove the DEFAULTS literal so a key's own definition is not counted as a use."""
        marker = 'const DEFAULTS := {'
        if marker not in text:
            return text
        head, tail = text.split(marker, 1)
        return head + tail.split('}', 1)[1] if '}' in tail else text

    def reads(key, text):
        """True only for a real consumption of the key.

        A match on the bare string is NOT enough: the settings panel and the clamping
        table mention every key, which would make the check unfalsifiable (a dead key
        added on purpose has to be reported, and it was not at first).
        """
        body = without_defaults(text)
        quoted = re.escape(key)
        for pattern in (
                r'get_(?:int|float|bool|value)\(\s*["\']%s["\']' % quoted,
                r'_apply_one\(\s*["\']%s["\']' % quoted,
                r'case\s+["\']%s["\']' % quoted,
                r'=="%s"' % quoted,
                r'key\s*==\s*["\']%s["\']' % quoted,
                r'RANGES\.has\(\s*["\']%s["\']' % quoted,
        ):
            if re.search(pattern, body):
                return True
        return False

    dead = [k for k in keys if not any(reads(k, t) for t in readers)]
    # a key that only appears in the panel but nowhere in the engine is also dead
    for k in dead:
        print('DEAD SETTING: %s is declared but never read by the game' % k)
    print('\ndead settings:', len(dead))
    return 1 if dead else 0


if __name__ == '__main__':
    sys.exit(main())
