#!/usr/bin/env python3
"""Sum rx+tx bytes for one uid out of `adb shell dumpsys netstats detail` output.

Usage: netstats-bytes.py <uid> <dump-file>
"""
import re
import sys

uid_target = sys.argv[1]
path = sys.argv[2]

ident_re = re.compile(r"^\s*ident=.*\buid=(-?\d+)\b")
st_re = re.compile(r"\brb=(\d+)\s+rp=(\d+)\s+tb=(\d+)\s+tp=(\d+)")

rx_total = 0
tx_total = 0
matching = False

with open(path) as f:
    for line in f:
        m = ident_re.match(line)
        if m:
            matching = m.group(1) == uid_target
            continue
        if matching:
            m2 = st_re.search(line)
            if m2:
                rx_total += int(m2.group(1))
                tx_total += int(m2.group(3))

print(f"uid={uid_target} rxBytes={rx_total} txBytes={tx_total} totalBytes={rx_total + tx_total}")
