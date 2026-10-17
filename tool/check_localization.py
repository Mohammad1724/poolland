#!/usr/bin/env python3
"""Port of test/localization_guard_test.dart, so the guard can be run
without a Dart toolchain.

Usage: python3 tool/check_localization.py [root]
"""

from __future__ import annotations

import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."

KEY_RE = re.compile(r"'((?:[^'\\]|\\.)*)'\s*:")
TR_RE = re.compile(r"\.tr(?:Args)?\b")
TERNARY_RE = re.compile(
    r"\?\s*'((?:[^'\\]|\\.)*)'\s*:\s*'((?:[^'\\]|\\.)*)'\s*\)?\s*\.tr\b"
)
PARAM_RE = re.compile(
    r"\b(message|title|subtitle|label|hint|okLabel|cancelLabel|"
    r"extraActionLabel|action):\s*'((?:[^'\\]|\\.)*)'"
)
SNACK_RE = re.compile(
    r"\bshow(?:Messenger)?Snack\(\s*(?:context|messenger)\s*,\s*"
    r"'((?:[^'\\]|\\.)*)'"
)

ALLOW = {"lib/data/ledger.dart:Week"}


def dart_files(directory: str) -> list[str]:
    out = []
    for dirpath, dirnames, filenames in os.walk(directory):
        dirnames[:] = [d for d in dirnames if d not in {".git", "build"}]
        for name in sorted(filenames):
            if name.endswith(".dart"):
                out.append(os.path.join(dirpath, name))
    return sorted(out)


def closing_quote(src: str, start: int) -> int:
    """Index of the closing quote of the literal starting at `start`."""
    i = start + 1
    while i < len(src):
        if src[i] == "\\":
            i += 2
            continue
        if src[i] == "'":
            return i
        i += 1
    return -1


def translated_literals(source: str) -> list[str]:
    """Every literal handed to .tr / .trArgs (multi-line joins included)."""
    out: list[str] = []
    for m in TR_RE.finditer(source):
        cursor = m.start()
        parts: list[str] = []
        interpolated = False
        while True:
            j = cursor - 1
            while j >= 0 and source[j] in " \t\n\r":
                j -= 1
            if j < 0 or source[j] != "'":
                break
            close = j
            open_ = close - 1
            while open_ >= 0 and not (
                source[open_] == "'" and (open_ == 0 or source[open_ - 1] != "\\")
            ):
                open_ -= 1
            if open_ < 0:
                break
            if not parts and open_ > 0:
                before = source[open_ - 1]
                if before in "})" or re.match(r"[A-Za-z0-9_$]", before):
                    interpolated = True
            parts.append(source[open_ + 1 : close])
            cursor = open_
            before = cursor - 1
            while before >= 0 and source[before] in " \t\n\r":
                before -= 1
            if before >= 0 and source[before] == "+":
                cursor = before
                continue
            if before >= 0 and source[before] == "'":
                continue
            break
        if interpolated:
            continue
        if parts:
            out.append("".join(reversed(parts)))
    for m in TERNARY_RE.finditer(source):
        out.append(m.group(1))
        out.append(m.group(2))
    return out


def joined_literals(source: str, regex: re.Pattern) -> list[str]:
    """Literals for the self-translating-parameter scanners."""
    out = []
    for m in regex.finditer(source):
        text = m.group(m.lastindex or 1)
        if "$" in text:
            continue
        end = m.end()
        while True:
            j = end
            while j < len(source) and source[j] in " \t\n\r":
                j += 1
            if j >= len(source) or source[j] != "'":
                break
            close = closing_quote(source, j)
            if close < 0:
                break
            part = source[j + 1 : close]
            if "$" in part:
                break
            text += part
            end = close + 1
        out.append(text)
    return out


def main() -> int:
    loc_path = os.path.join(ROOT, "lib", "core", "localization.dart")
    loc_src = open(loc_path, encoding="utf-8").read()
    keys = set(KEY_RE.findall(loc_src))

    missing: list[str] = []
    for path in dart_files(os.path.join(ROOT, "lib")):
        rel = os.path.relpath(path, ROOT)
        if rel.endswith("core/localization.dart"):
            continue
        source = open(path, encoding="utf-8").read()
        for text in translated_literals(source):
            if "$" in text:
                continue
            if text not in keys:
                line = source[: source.find(text)].count("\n") + 1
                missing.append(f"{rel}:{line}  {text}")
        for regex in (PARAM_RE, SNACK_RE):
            for text in joined_literals(source, regex):
                if f"{rel}:{text}" in ALLOW:
                    continue
                if text not in keys:
                    missing.append(f"{rel}  {text}  (self-translating param)")

    if missing:
        print(f"{len(missing)} missing Persian key(s):")
        for m in missing:
            print("  " + m)
        return 1
    print("every translated string has a Persian entry")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
