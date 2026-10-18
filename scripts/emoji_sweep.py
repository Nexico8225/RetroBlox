#!/usr/bin/env python3
"""Sweep every emoji-class character out of the RetroBlox web UI.

Users = people who use the web. Players = people who play games. Neither of
them wants emoji in a 2006-style site. Literal replacements below are applied
to every .ts/.tsx file under src/, then a codepoint scan proves nothing
emoji-presented is left (plain text glyphs like * -> keep their retro look).
"""
import os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src')

REPL = [
    # decorative emoji labels -> plain text
    ('\U0001F3AE ', ''),   # game controller
    ('\U0001F4C5 ', ''),   # calendar
    ('\U0001F6E0 ', ''),   # hammer and wrench
    ('\U0001F465 ', ''),   # people
    ('\U0001F525 ', ''),   # fire
    ('\U0001F4AC ', ''),   # speech balloon
    ('\U0001F3F3 ', ''),   # flag
    ('\U0001F579\uFE0F', ''),  # joystick with VS16
    ('\U0001F579', ''),        # joystick bare
    ('\U0001F48E', ''),    # gem
    ('\U0001F44D ', ''),   # thumbs up
    ('\U0001F44E ', ''),   # thumbs down
    ('\u2705', '[YES]'),   # check mark button
    ('\u274C', '[NO]'),    # cross mark button
    ('\u2B06 ', ''),       # up arrow button
    ('\u2B07 ', ''),       # down arrow button
    ('\u2B06', ''), ('\u2B07', ''),
    ('\u25B6 ', ''),       # play button
    ('\u25B6', ''),
    ('\u26A0 ', 'Note: '),  # warning
    ('\u26A0', 'Note: '),
    ('\U0001F6AB ', ''),   # prohibited
    ('\U0001F6AB', ''),
    ('\U0001F501 ', ''),   # repeat
    ('\U0001F501', ''),
    ('\U0001F44B ', ''),   # wave
    ('\U0001F44B', ''),
    ('\U0001F91D ', ''),   # handshake
    ('\U0001F91D', ''),
    ('\U0001F4B0 ', ''),   # money bag
    ('\U0001F4B0', ''),
    ('\U0001F389 ', ''),   # party popper
    ('\U0001F389', ''),
    ('\U0001F4E6 ', ''),   # package
    ('\U0001F4E6', ''),
    ('\U0001F514 ', ''),   # bell
    ('\U0001F514', ''),
    ('\u2699 ', ''),       # gear
    ('\u2699', ''),
    ('\u2B50 ', ''),       # star
    ('\u2B50', ''),
    ('\u26F6 ', ''),       # square four corners
    ('\u26F6', ''),
    ('\U0001F4A1 ', ''),   # light bulb
    ('\U0001F4A1', ''),
    ('\U0001F441 ', ''),   # eye
    ('\U0001F441\uFE0F', ''),
    ('\U0001F441', ''),
    ('\U0001F5BC ', ''),   # frame with picture
    ('\U0001F5BC\uFE0F', ''),
    ('\U0001F5BC', ''),
    ('\U0001F4AC', ''),    # speech balloon (bare too)
    ('\uFE0F', ''),        # stray variation selectors
]

SCAN_RANGES = [
    (0x1F000, 0x1FAFF), (0x2600, 0x27BF), (0x2B00, 0x2BFF),
    (0xFE00, 0xFE0F), (0x1F1E6, 0x1F1FF), (0x2705, 0x2705), (0x274C, 0x274C),
]
# text glyphs that stay (retro terminal look, monochrome everywhere):
KEEP = set('\u2605\u2606\u2713\u2715\u2717\u2726\u270E\u2190\u2191\u2192\u2193\u21C4')

def scan(line):
    hits = []
    for ch in line:
        cp = ord(ch)
        if ch in KEEP:
            continue
        for lo, hi in SCAN_RANGES:
            if lo <= cp <= hi:
                hits.append((ch, hex(cp)))
    return hits

changed = []
for dirpath, _, files in os.walk(ROOT):
    for fn in files:
        if not fn.endswith(('.ts', '.tsx')):
            continue
        p = os.path.join(dirpath, fn)
        src = open(p, encoding='utf-8').read()
        out = src
        for a, b in REPL:
            out = out.replace(a, b)
        if out != src:
            open(p, 'w', encoding='utf-8').write(out)
            changed.append(os.path.relpath(p, ROOT))

print('CHANGED FILES (%d):' % len(changed))
for f in sorted(changed):
    print('  ', f)

left = []
for dirpath, _, files in os.walk(ROOT):
    for fn in files:
        if not fn.endswith(('.ts', '.tsx')):
            continue
        p = os.path.join(dirpath, fn)
        for i, line in enumerate(open(p, encoding='utf-8'), 1):
            for ch, cp in scan(line):
                left.append('%s:%d %s %s' % (os.path.relpath(p, ROOT), i, ch, cp))

print('\nREMAINING EMOJI-CLASS CHARS (%d):' % len(left))
for l in left[:60]:
    print('  ', l)
sys.exit(1 if left else 0)
