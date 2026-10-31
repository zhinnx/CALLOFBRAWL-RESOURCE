"""Check #10: autoload member audit.

Autoloads are the one place where a typo only shows up at runtime (the script still
compiles because `Settings`/`Game`/`Audio`/`Fx` resolve through the project). This
resolves every `Autoload.member` access against the declared `var`/`const`/`signal`/
`func` of the backing script plus a whitelist of inherited Node/Object members.
"""
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else '.'

INHERITED = set('''ready process physics_process draw input unhandled_input notification
get_tree get_viewport get_node get_parent add_child remove_child queue_free free
connect disconnect emit emit_signal call call_deferred callv set get has_method
is_connected name owner scene_file_path get_children find_children is_inside_tree
set_process set_physics_process set_process_input set_process_unhandled_input
process_mode visible is_visible_in_tree pause_mode get_index get_child_count
to_string duplicate is_node_ready get_class get_script get_path print_tree
tr print_rich printraw'''.split())


def main():
    proj = os.path.join(ROOT, 'project.godot')
    text = open(proj, encoding='utf-8').read()
    block = re.search(r'\[autoload\](.*?)(?:\n\[|\Z)', text, re.S)
    if not block:
        print('no autoload section')
        return 0
    autoloads = dict(re.findall(r'(\w+)="\*?res://([\w./-]+)"', block.group(1)))
    members = {}
    for name, path in autoloads.items():
        full = os.path.join(ROOT, path)
        if not os.path.exists(full):
            print('MISSING autoload script: %s -> %s' % (name, path))
            continue
        src = open(full, encoding='utf-8').read()
        members[name] = (
            set(re.findall(r'^var\s+(\w+)', src, re.M))
            | set(re.findall(r'^const\s+(\w+)', src, re.M))
            | set(re.findall(r'^signal\s+(\w+)', src, re.M))
            | set(re.findall(r'^(?:static\s+)?func\s+(\w+)', src, re.M))
        )
    problems = []
    for dirpath, _, names in os.walk(os.path.join(ROOT, 'scripts')):
        for name in names:
            if not name.endswith('.gd'):
                continue
            full = os.path.join(dirpath, name)
            src = open(full, encoding='utf-8').read()
            for al, known in members.items():
                for m in re.finditer(r'\b%s\.(\w+)' % re.escape(al), src):
                    attr = m.group(1)
                    if attr in known or attr in INHERITED:
                        continue
                    line = src.count('\n', 0, m.start()) + 1
                    problems.append('%s:%d: %s.%s does not exist'
                                    % (os.path.relpath(full, ROOT), line, al, attr))
    for p in sorted(set(problems)):
        print(p)
    print('\nautoload member problems:', len(set(problems)))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
