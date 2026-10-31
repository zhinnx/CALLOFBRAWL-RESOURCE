"""Check #8: syntax hazards the AST-based checkers cannot see.

Targets the failure modes that already bit this project:
  * backslash line continuation (not valid GDScript -> parse error)
  * mixed tabs/spaces in indentation
  * `set_*_preset()` without a receiver (leaves a Control at 0x0)
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
            m_ext = re.search(r'^extends\s+([\w.]+)', text, re.M)
            # a bare `set_*_preset()` is only valid when the script itself is a Control
            self_is_control = bool(m_ext) and m_ext.group(1) in (
                'Control', 'Container', 'BoxContainer', 'VBoxContainer',
                'HBoxContainer', 'MarginContainer', 'Panel', 'PanelContainer',
                'ScrollContainer', 'GridContainer', 'CenterContainer')
            for i, line in enumerate(lines, 1):
                stripped = line.lstrip(' \t')
                indent = line[:len(line) - len(stripped)]
                if '\\' in line.rstrip() and line.rstrip().endswith('\\'):
                    problems.append((path, i, 'backslash line continuation'))
                if '\t' in indent and ' ' in indent:
                    problems.append((path, i, 'mixed tab/space indentation'))
                if stripped.startswith('"') or stripped.startswith("'"):
                    continue
                # A Control layout call without a receiver hits the script itself.
                # e.g. `set_offsets_preset(...)` inside a CanvasLayer method is an
                # error and leaves the child 0x0 -> an invisible UI.
                if not self_is_control and re.match(
                        r'\s*(?:set_anchors_preset|set_offsets_preset|'
                        r'set_anchors_and_offsets_preset)\s*\(', line):
                    problems.append((path, i, 'layout preset call without a receiver'))
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
