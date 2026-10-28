import sys
from pathlib import Path

ROOT = Path("public/godot/RetroBloxPlayer/scripts")
problems = []

for p in sorted(ROOT.rglob("*.gd")):
    text = p.read_text(encoding="utf-8")
    lines = text.split("\n")
    # 1. indentation must be tabs, not leading spaces
    for i, l in enumerate(lines, 1):
        if l.startswith(" ") and l.strip():
            problems.append((p, i, "space indentation"))
    # 2. bracket balance outside strings / comments
    depth = {"(": 0, "[": 0, "{": 0}
    pairs = {")": "(", "]": "[", "}": "{"}
    for ln, l in enumerate(lines, 1):
        quote = None
        esc = False
        for ch in l:
            if esc:
                esc = False
                continue
            if ch == "\\":
                esc = True
                continue
            if quote:
                if ch == quote:
                    quote = None
                continue
            if ch in ("'", '"'):
                quote = ch
                continue
            if ch == "#":
                break
            if ch in depth:
                depth[ch] += 1
            elif ch in pairs:
                depth[pairs[ch]] -= 1
                if depth[pairs[ch]] < 0:
                    problems.append((p, ln, "unbalanced " + ch))
    for k, v in depth.items():
        if v != 0:
            problems.append((p, 0, "unclosed " + k + " x%d" % v))
    # 3. elif after else at the same indent (invalid GDScript)
    stack = {}
    for i, l in enumerate(lines, 1):
        s = l.strip()
        if not s or s.startswith("#"):
            continue
        indent = len(l) - len(l.lstrip("\t"))
        if s == "else:":
            stack[indent] = i
        elif s.startswith("elif "):
            if indent in stack:
                problems.append((p, i, "elif after else (else at line %d)" % stack[indent]))
                del stack[indent]
        elif indent in stack and not s.startswith(("else:", "elif ")):
            # a non-else statement at the else's indent closes that chain
            if indent == len(l) - len(l.lstrip()):
                del stack[indent]

for pr in problems:
    print("%s:%d  %s" % (pr[0], pr[1], pr[2]))
print("total problems:", len(problems))
