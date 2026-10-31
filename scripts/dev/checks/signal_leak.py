"""Check #11: connections into long-lived (autoload) signals must be released on teardown.

`Audio`, `Game`, `Settings` and `Fx` are autoloads; they outlive every scene. A scene node
that connects to one of their signals without releasing it leaves a stale connection after
a scene change: the callback fires into a freed node, and the *next* instance reacts twice.

A `disconnect` is not enough on its own - it has to sit on a path that runs when the node
leaves the tree. `CBMatchManager.stop()` contained a correct disconnect that nothing ever
called, so this check requires the disconnect to be reachable from `_exit_tree`,
`_on_tree_exiting`, `_notification` or a handler connected to `tree_exiting`.
"""
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'
TEARDOWN_HOOKS = ('_exit_tree', '_on_tree_exiting', '_notification')


def autoloads(root):
    proj = os.path.join(root, 'project.godot')
    if not os.path.exists(proj):
        return set()
    text = open(proj, encoding='utf-8').read()
    block = re.search(r'\[autoload\](.*?)(?:\n\[|\Z)', text, re.S)
    if not block:
        return set()
    return set(re.findall(r'(\w+)="\*?res://', block.group(1)))


def teardown_regions(src):
    """Text of every function that is guaranteed to run on teardown."""
    names = list(TEARDOWN_HOOKS)
    m = re.search(r'tree_exiting\.connect\(\s*(\w+)\s*\)', src)
    if m:
        names.append(m.group(1))
    regions = []
    for name in names:
        for fm in re.finditer(r'^func\s+%s\s*\(' % re.escape(name), src, re.M):
            nxt = re.search(r'^func\s+\w+\s*\(', src[fm.end():], re.M)
            end = fm.end() + nxt.start() if nxt else len(src)
            regions.append(src[fm.start():end])
    return regions


def main():
    al = autoloads(ROOT)
    problems = []
    for dirpath, _, names in os.walk(os.path.join(ROOT, 'scripts')):
        for name in names:
            if not name.endswith('.gd'):
                continue
            full = os.path.join(dirpath, name)
            src = open(full, encoding='utf-8').read()
            rel = os.path.relpath(full, ROOT)
            for owner, sig, handler in re.findall(r'\b(\w+)\.(\w+)\.connect\((\w+)\)', src):
                if owner not in al:
                    continue
                needle = '%s.%s.connect(%s)' % (owner, sig, handler)
                line = src[:src.index(needle)].count('\n') + 1
                disc = re.compile(r'\b%s\.%s\.disconnect\(\s*%s\s*\)'
                                  % (re.escape(owner), re.escape(sig), re.escape(handler)))
                if not disc.search(src):
                    problems.append('%s:%d: %s.%s -> %s() is never disconnected'
                                    % (rel, line, owner, sig, handler))
                elif not any(disc.search(region) for region in teardown_regions(src)):
                    problems.append('%s:%d: %s.%s -> %s() is only disconnected outside a '
                                    'teardown hook' % (rel, line, owner, sig, handler))
    for p in sorted(set(problems)):
        print(p)
    print('\nunreleased autoload connections:', len(set(problems)))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
