#!/usr/bin/env python3
"""Approximate static sanity check for Dart sources (no SDK in the sandbox).

Checks, per file:
  * balanced (), [], {} outside strings and comments
  * imports that resolve to a local file whose exported names are never
    referenced in the importing file (likely an unused import, which
    `flutter analyze` reports as a warning and CI treats as a failure)

Usage: python3 tool/check_dart_sanity.py [root]
"""

from __future__ import annotations

import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."

DECL_RE = re.compile(
    r"^\s*(?:abstract\s+|final\s+|base\s+|sealed\s+|mixin\s+)*"
    r"(?:class|enum|mixin|extension|typedef)\s+(\w+)"
)
FUNC_RE = re.compile(r"^(?:[A-Za-z_][\w<>,\s?]*\s+)?(\w+)\s*\([^;]*\)\s*(?:async\s*)?\{?\s*$")
VAR_RE = re.compile(r"^(?:const|final|var)\s+(?:[\w<>,\s?]+\s+)?(\w+)\s*=")
TOPFUNC_RE = re.compile(
    r"^(?:[A-Za-z_][\w<>,\s?]*[\s>])?([A-Za-z_]\w*)\s*(?:<[^>]*>)?\s*\("
)
TOPGETTER_RE = re.compile(r"^(?:[A-Za-z_][\w<>,\s?]*[\s>])?get\s+([A-Za-z_]\w*)\b")


def _interpolation(src: str, i: int) -> tuple[int, str]:
    """Copy a ${...} interpolation (code kept, strings blanked) from src."""
    n = len(src)
    j = i + 2
    depth = 1
    chunk = []
    while j < n and depth:
        ch = src[j]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                j += 1
                break
        chunk.append(ch)
        j += 1
    return j, " ".join(strip_code("".join(chunk)).split())


def strip_code(src: str) -> str:
    """Blank out string literals and comments, keeping offsets/lines intact."""
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                out.append(" ")
                i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            while i < n and not (src[i] == "*" and i + 1 < n and src[i + 1] == "/"):
                out.append("\n" if src[i] == "\n" else " ")
                i += 1
            out.append("  ")
            i += 2
            continue
        if c in "'\"":
            quote = c
            triple = src[i : i + 3] == quote * 3
            if triple:
                i += 3
                out.append("   ")
                while i < n and src[i : i + 3] != quote * 3:
                    if src[i : i + 2] == "${":
                        out.append(" ")
                        i, chunk = _interpolation(src, i)
                        out.append(chunk)
                        continue
                    out.append("\n" if src[i] == "\n" else " ")
                    i += 1
                i += 3
                out.append("   ")
                continue
            i += 1
            out.append(" ")
            while i < n and src[i] != quote:
                if src[i : i + 2] == "${":
                    out.append(" ")
                    i, chunk = _interpolation(src, i)
                    out.append(chunk)
                    continue
                if src[i] == "\\":
                    out.append(" ")
                    i += 1
                    if i < n:
                        out.append("\n" if src[i] == "\n" else " ")
                        i += 1
                    continue
                out.append("\n" if src[i] == "\n" else " ")
                i += 1
            i += 1
            out.append(" ")
            continue
        if c == "$" and i + 1 < n and src[i + 1] == "{":
            depth = 0
            while i < n:
                if src[i] == "{":
                    depth += 1
                elif src[i] == "}":
                    depth -= 1
                    if depth == 0:
                        i += 1
                        break
                out.append("\n" if src[i] == "\n" else " ")
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def check_balance(path: str, code: str) -> list[str]:
    problems = []
    stack = []
    pairs = {")": "(", "]": "[", "}": "{"}
    line = 1
    for ch in code:
        if ch == "\n":
            line += 1
        elif ch in "([{":
            stack.append((ch, line))
        elif ch in ")]}":
            if not stack:
                problems.append(f"{path}:{line}: stray '{ch}'")
            else:
                opener, oline = stack.pop()
                if opener != pairs[ch]:
                    problems.append(
                        f"{path}:{line}: '{ch}' closes '{opener}' opened at line {oline}"
                    )
    for opener, oline in stack:
        problems.append(f"{path}:{oline}: unclosed '{opener}'")
    return problems


EXT_MEMBER_RE = re.compile(r"^\s+(?:[A-Za-z_][\w<>,\s?]*[\s>])?([A-Za-z_]\w*)\s*\(")
EXT_GETTER_RE = re.compile(r"^\s+[\w<>,\s?]*\bget\s+([A-Za-z_]\w*)")


def declared_names(path: str) -> tuple[set[str], set[str]]:
    """(type names, extension member names) declared by a Dart file."""
    types: set[str] = set()
    members: set[str] = set()
    try:
        src = open(path, encoding="utf-8").read()
    except OSError:
        return types, members
    code = strip_code(src)
    lines = code.splitlines()

    in_extension = False
    depth = 0
    for raw in lines:
        if not in_extension:
            m = DECL_RE.match(raw)
            if m:
                types.add(m.group(1))
                if raw.lstrip().startswith("extension "):
                    in_extension = True
                    depth = raw.count("{") - raw.count("}")
                continue
            if raw.startswith(("class ", "enum ", "mixin ", "extension ", "typedef ")):
                continue
            m = VAR_RE.match(raw)
            if m and not raw.startswith(" "):
                types.add(m.group(1))
                continue
            # Top-level function: "Type name(" or "name(" at column 0.
            m = TOPFUNC_RE.match(raw)
            if m and not raw.startswith(" "):
                types.add(m.group(1))
                continue
            # Top-level getter.
            m = TOPGETTER_RE.match(raw)
            if m and not raw.startswith(" "):
                types.add(m.group(1))
            continue

        # Inside an extension body: collect its members.
        m = EXT_MEMBER_RE.match(raw) or EXT_GETTER_RE.match(raw)
        if m:
            members.add(m.group(1))
        depth += raw.count("{") - raw.count("}")
        if depth <= 0:
            in_extension = False
    return types, members


IMPORT_RE = re.compile(r"""^\s*(?:import|export)\s+'([^']+)'""", re.MULTILINE)


def imports_of(src: str) -> list[str]:
    """Import targets, read from the raw source (quotes are still intact)."""
    return [m.group(1) for m in IMPORT_RE.finditer(src)]


def resolve(importer: str, target: str) -> str | None:
    if target.startswith("dart:") or target.startswith("package:flutter"):
        return None
    if target.startswith("package:poolland/"):
        base = os.path.join(ROOT, "lib", target[len("package:poolland/") :])
    elif target.startswith("package:"):
        return None
    else:
        base = os.path.normpath(os.path.join(os.path.dirname(importer), target))
    if os.path.isfile(base):
        return base
    if os.path.isfile(base + ".dart"):
        return base + ".dart"
    return None


def main() -> int:
    problems: list[str] = []
    checked = 0
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in {".git", "build", ".dart_tool"}]
        for name in filenames:
            if not name.endswith(".dart"):
                continue
            path = os.path.join(dirpath, name)
            src = open(path, encoding="utf-8").read()
            code = strip_code(src)
            problems.extend(check_balance(path, code))
            checked += 1

            # The body without the import lines: identifiers are searched in
            # the stripped code (no comments, no strings) so a mention in a
            # doc comment cannot make an unused import look used.
            body = "\n".join(
                stripped
                for raw, stripped in zip(src.splitlines(), code.splitlines())
                if not IMPORT_RE.match(raw)
            )
            for target in imports_of(src):
                resolved = resolve(path, target)
                if resolved is None:
                    continue
                types, members = declared_names(resolved)
                if not types and not members:
                    continue
                used = any(
                    re.search(rf"(?<![\w.]){re.escape(n)}\b", body) for n in types
                ) or any(
                    re.search(rf"\.{re.escape(n)}\b", body) for n in members
                )
                if not used:
                    problems.append(
                        f"{path}: possibly unused import '{target}'"
                        f" (none of: {', '.join(sorted(types | members)[:6])})"
                    )
    print(f"checked {checked} dart files")
    for p in problems:
        print("  " + p)
    print(f"{len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
