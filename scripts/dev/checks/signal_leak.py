"""Check #11: connections into long-lived (autoload) signals must be disconnected.

`Audio`, `Game`, `Settings` and `Fx` are autoloads; they outlive every scene. A scene
node that connects to one of their signals without a matching `disconnect` leaves a
stale connection behind after a scene change: the callback fires into a freed node and
the *next* instance reacts twice. This check flags a connect with no disconnect for the
same handler anywhere in the file.
"""
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'


def autoloads(root):
    proj = os.path.join(root, 'project.godot')
    if not os.path.exists(proj):
        return set()
    text = open(proj, encoding='utf-8').read()
    block = re.search(r'\[autoload\](.*?)(?:\n\[|\Z)', text, re.S)
    if not block:
        return set()
    return set(re.findall(r'(\w+)="\*?res://', block.group(1)))


def main():
    al = autoloads(ROOT)
    problems = []
    for dirpath, _, names in os.walk(os.path.join(ROOT, 'scripts')):
        for name in names:
            if not name.endswith('.gd'):
                continue
            full = os.path.join(dirpath, name)
            src = open(full, encoding='utf-8').read()
            connects = re.findall(r'\b(\w+)\.(\w+)\.connect\((\w+)\)', src)
            for owner, sig, handler in connects:
                if owner not in al:
                    continue
                # the handler must be disconnected somewhere in the same file
                if re.search(r'\b%s\.%s\.disconnect\(%s\)' % (owner, sig, handler), src):
                    continue
                line = src[:src.index('%s.%s.connect(%s)' % (owner, sig, handler))].count('\n') + 1
                problems.append('%s:%d: %s.%s -> %s() is never disconnected'
                                % (os.path.relpath(full, ROOT), line, owner, sig, handler))
    for p in sorted(set(problems)):
        print(p)
    print('\nunreleased autoload connections:', len(set(problems)))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
