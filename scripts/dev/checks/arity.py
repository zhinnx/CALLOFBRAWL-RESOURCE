"""Check #9: argument-count mismatches on project classes.

Builds `class_name -> {method: (required, total, has_varargs)}` from the tree and
then checks every `expr.method(...)` call whose static type can be resolved from a
typed declaration (`var x: CBType`, `x: CBType` parameters, `-> CBType` returns)
or a `CBType.new()` initialiser. Catches the class of bug that produced the
`call_deferred("_build_music", null)` crash and the `reset()` additions.
"""
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'


def strip_comments_strings(src):
    out, i, n, in_str = [], 0, len(src), None
    while i < n:
        c = src[i]
        if in_str:
            if c == '\\':
                out.append(' ')
                out.append(' ')
                i += 2
                continue
            if c == in_str:
                in_str = None
            out.append('\n' if c == '\n' else ' ')
        elif c in '"\'':
            in_str = c
            out.append(' ')
        elif c == '#':
            while i < n and src[i] != '\n':
                i += 1
            continue
        else:
            out.append(c)
        i += 1
    return ''.join(out)


def split_args(text):
    """Split a call's argument text on top-level commas."""
    if not text.strip():
        return []
    depth, cur, out = 0, [], []
    for ch in text:
        if ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(''.join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    out.append(''.join(cur).strip())
    return [a for a in out if a]


def collect_classes(root):
    classes, files = {}, {}
    for dirpath, _, names in os.walk(root):
        for name in names:
            if not name.endswith('.gd'):
                continue
            path = os.path.join(dirpath, name)
            raw = open(path, encoding='utf-8').read()
            clean = strip_comments_strings(raw)
            files[path] = clean
            m = re.search(r'^class_name\s+(\w+)', clean, re.M)
            if not m:
                continue
            cls = m.group(1)
            methods, sig = {}, None
            for line in clean.split('\n'):
                fm = re.match(r'^(?:static\s+)?func\s+(\w+)\s*\((.*?)\)', line)
                if fm:
                    args = split_args(fm.group(2))
                    total = len(args)
                    required = 0
                    varargs = False
                    for a in args:
                        if a.startswith('...'):
                            varargs = True
                            continue
                        if '=' in a:
                            continue
                        required += 1
                    methods[fm.group(1)] = (required, total, varargs)
            classes[cls] = methods
    return classes, files


def main():
    classes, files = collect_classes(ROOT)
    problems = []
    for path, src in files.items():
        # static types visible in this file
        types = {}
        for m in re.finditer(r'\bvar\s+(\w+)\s*:\s*(CB\w+)', src):
            types[m.group(1)] = m.group(2)
        for m in re.finditer(r'\bvar\s+(\w+)\s*(?::\s*CB\w+)?\s*=\s*(CB\w+)\.new\(\)', src):
            types[m.group(1)] = m.group(2)
        for m in re.finditer(r'\bfunc\s+\w+\s*\((.*?)\)\s*(?:->\s*(\w+))?', src, re.S):
            for a in split_args(m.group(1)):
                am = re.match(r'(\w+)\s*:\s*(CB\w+)', a.strip())
                if am:
                    types[am.group(1)] = am.group(2)
        for name, cls in types.items():
            if cls not in classes:
                continue
            for m in re.finditer(r'\b%s\.(\w+)\s*\(' % re.escape(name), src):
                meth = m.group(1)
                sig = classes[cls].get(meth)
                if sig is None:
                    continue
                # count arguments with a bracket-aware scan from the open paren
                i = m.end() - 1
                depth, j = 0, i
                while j < len(src):
                    if src[j] in '([{':
                        depth += 1
                    elif src[j] in ')]}':
                        depth -= 1
                        if depth == 0:
                            break
                    j += 1
                n_args = len(split_args(src[i + 1:j]))
                required, total, varargs = sig
                line = src.count('\n', 0, m.start()) + 1
                if n_args < required or (not varargs and n_args > total):
                    problems.append('%s:%d: %s.%s() called with %d arg(s), expects %d-%d'
                                    % (os.path.relpath(path, ROOT), line, name, meth,
                                       n_args, required, total))
    for p in sorted(set(problems)):
        print(p)
    print('\narity problems:', len(set(problems)))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
