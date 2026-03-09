#!/usr/bin/env python3
"""
Fix common YAML issues in workflow files:
- Comment out <REDACTED_SECRET_REMOVED_BY_AUTOMATION> placeholders
- Unnest incorrectly nested '- name:' blocks when detected

Backs up original files with .bak extension.
"""
import re
from pathlib import Path
import sys

TARGETS = [
    '.github/workflows/gcp-gsm-breach-recovery.yml',
    '.github/workflows/gcp-gsm-rotation.yml',
    '.github/workflows/gcp-gsm-sync-secrets.yml',
    '.github/workflows/secrets-orchestrator-multi-layer.yml',
    '.github/workflows/store-leaked-to-gsm-and-remove.yml',
    '.github/workflows/store-slack-to-gsm.yml',
    '.github/workflows/terraform-phase2-final-plan-apply.yml',
    '.github/workflows/secrets-health-dashboard.yml',
    '.github/workflows/secrets-health.yml',
]

INDENT_RE = re.compile(r'^(?P<indent>\s*)- name:\s*(?P<name>.+)$')
REDACTED = '<REDACTED_SECRET_REMOVED_BY_AUTOMATION>'


def backup(path: Path):
    bak = path.with_suffix(path.suffix + '.bak')
    if not bak.exists():
        bak.write_bytes(path.read_bytes())


def comment_redacted(lines):
    return [line.replace(REDACTED, f"# {REDACTED}") if REDACTED in line else line for line in lines]


def fix_nested_names(lines):
    out = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        m = INDENT_RE.match(line)
        if m:
            parent_indent = len(m.group('indent'))
            # Lookahead for next non-empty line
            j = i + 1
            while j < n and lines[j].strip() == '':
                j += 1
            if j < n:
                m2 = INDENT_RE.match(lines[j])
                if m2:
                    child_indent = len(m2.group('indent'))
                    # If child is more indented (nested under parent) and parent appears to have no body (no uses/run before child), unnest child by removing parent line
                    # Check if between i and j there is any non-comment non-empty content besides whitespace; if not, it's a nesting artifact
                    between = False
                    for k in range(i+1, j):
                        if lines[k].strip() and not lines[k].strip().startswith('#'):
                            between = True
                            break
                    if not between and child_indent > parent_indent:
                        # Drop the parent line, and unindent the child block from j until block end (next line with indent <= parent_indent and starting with '- ')
                        # Determine end of child block: continue until next line that starts with same or less indent and starts with '- ' at that indent
                        # We'll unindent lines from j until before next sibling at indent <= parent_indent and line.lstrip().startswith('- ')
                        k = j
                        # compute delta
                        delta = child_indent - parent_indent
                        # collect until next sibling
                        child_block = []
                        while k < n:
                            # stop if we see a sibling step at indent <= parent_indent
                            stripped = lines[k].lstrip()
                            current_indent = len(lines[k]) - len(stripped)
                            if k != j and stripped.startswith('- ') and current_indent <= parent_indent:
                                break
                            # unindent this line by delta spaces (but not below 0)
                            if len(lines[k]) >= delta and lines[k][:delta].isspace():
                                child_block.append(lines[k][delta:])
                            else:
                                child_block.append(lines[k].lstrip('\n'))
                            k += 1
                        # append unindented child block to output
                        out.extend(child_block)
                        i = k
                        continue
        out.append(line)
        i += 1
    return out


def process_file(path: Path):
    print(f"Processing {path}")
    if not path.exists():
        print(f"  - Not found")
        return False
    text = path.read_text()
    lines = text.splitlines(keepends=True)
    backup(path)
    # 1) comment redacted placeholders
    lines = comment_redacted(lines)
    # 2) fix nested '- name:' artifacts
    lines = fix_nested_names(lines)
    # write back
    path.write_text(''.join(lines))
    print(f"  - Fixed and backed up to {path}.bak")
    return True


def main():
    any_changed = False
    for p in TARGETS:
        path = Path(p)
        changed = process_file(path)
        any_changed = any_changed or changed
    if not any_changed:
        print("No target files found/changed.")

if __name__ == '__main__':
    main()
