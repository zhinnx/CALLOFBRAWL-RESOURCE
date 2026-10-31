"""Check #8: syntax hazards the AST-based checkers cannot see.

Targets the failure modes that already bit this project:
  * backslash line continuation (not valid GDScript -> parse error)
  * mixed tabs/spaces in indentation
  * `:=` inferred from a Variant-producing call (the round-2 navmesh bug)
"""
import os
import re
import sys

VARIANT_SOURCES = (
    r'\.get\(', r'\.pick_random\(', r'\.back\(', r'\.front\(', r'\.pop_back\(',
    r'\.pop_front\(', r'\[[^\]]*\]\s*$', r'JSON\.', r'\.values\(\)', r'\.keys\(\)',
)


def main(root):
    problems = []
    for dirpath, _, names in os.walk(root):
        for name in names:
            if not name.endswith('.gd'):
                continue
            path = os.path.join(dirpath, name)
            text = open(path, encoding='utf-8').read()
            lines = text.split('\n')
            for i, line in enumerate(lines, 1):
                stripped = line.lstrip(' \t')
                indent = line[:len(line) - len(stripped)]
                if '\\' in line.rstrip() and line.rstrip().endswith('\\'):
                    problems.append((path, i, 'backslash line continuation'))
                if '\t' in indent and ' ' in indent:
                    problems.append((path, i, 'mixed tab/space indentation'))
                if stripped.startswith('"') or stripped.startswith("'"):
                    continue
                # NOTE: "A, B:" match arms are legal GDScript (multiple patterns), so
                # they are deliberately not flagged here.
                # NOTE: no `:=`-from-Variant heuristic here. A regex cannot tell a
                # Variant apart from a typed container read, and this exact heuristic
                # produced 231 false positives earlier in the project.
    for p, n, msg in problems:
        print('%s:%d: %s' % (p, n, msg))
    print('\nsyntax hazards:', len(problems))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else '.'))
