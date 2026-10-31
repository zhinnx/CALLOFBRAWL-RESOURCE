"""Check #7: string-based calls (call / call_deferred / callv / rpc) against real arity.

Godot resolves these at runtime, so a wrong argument count is a deferred-method error
in the console rather than a parse error. This catches them statically.
"""
import os
import re
import sys

sys.path.insert(0, '/tmp/gdcheck')
import gdcheck as G


def top_level_count(body):
    """Number of comma-separated arguments in a call tail (handles nested brackets)."""
    body = body.strip()
    if body.startswith(','):
        body = body[1:]
    if not body.strip():
        return 0
    n, depth = 1, 0
    for ch in body:
        if ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
        elif ch == ',' and depth == 0:
            n += 1
    return n


def run(root):
    p = G.Project(root)
    problems = []
    for rel, ci in p.scripts.items():
        src = open(os.path.join(root, rel)).read()
        for m in re.finditer(r'\b(call_deferred|call|callv|call_group)\s*\(\s*"(\w+)"((?:\s*,(?:[^(),]|\([^()]*\))*)*)', src):
            kind, target, rest = m.group(1), m.group(2), m.group(3)
            line = src[:m.start()].count('\n') + 1
            if kind == 'callv':
                continue
            wanted = None
            for _rel, other in p.scripts.items():
                if target in other.funcs:
                    wanted = other.funcs[target]
                    break
            if wanted is None:
                problems.append((rel, line, 'unknown method "%s"' % target))
                continue
            argc = top_level_count(rest)
            if kind == 'call_group':
                argc -= 1  # the group name is the first argument
            mn, mx = wanted
            if not (mn <= argc <= mx):
                problems.append((rel, line, '%s("%s") got %d args, expects %d-%d'
                                 % (kind, target, argc, mn, mx)))
    return problems


if __name__ == '__main__':
    root = sys.argv[1] if len(sys.argv) > 1 else '.'
    probs = run(root)
    for rel, line, msg in probs:
        print('STRCALL %s:%s  %s' % (rel, line, msg))
    print('\nstring-call problems: %d' % len(probs))
    sys.exit(0 if not probs else 1)
