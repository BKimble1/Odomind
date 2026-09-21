#!/usr/bin/env python3
"""Catches the Swift mistakes that only a compiler on a Mac would otherwise find.

There is no Swift toolchain on the authoring host, so every compile error costs
a ten-minute round trip to a macOS runner. This catches the ones that have
actually happened in this repository rather than everything imaginable:

  1. `await` inside an autoclosure — XCTAssert*, `??`, `guard let x = y ??`.
     An autoclosure is synchronous and cannot carry one.
  2. `await` inside a synchronous closure — map, flatMap, compactMap, filter,
     forEach, Optional.map. Same reason, different shape.
  3. Unbalanced braces, parens and brackets.
  4. `Section("title") { } footer:` — not an initialiser that exists.
  5. A key path into a tuple element, `id: \\.0` — Swift has no such thing.

Run before pushing. Exits non-zero when it finds something.
"""

import pathlib
import re
import sys

AUTOCLOSURE_CALLS = (
    "XCTAssertTrue", "XCTAssertFalse", "XCTAssertNil", "XCTAssertNotNil",
    "XCTAssertEqual", "XCTAssertNotEqual", "XCTAssertGreaterThan",
    "XCTAssertLessThan", "XCTAssertGreaterThanOrEqual", "XCTAssertLessThanOrEqual",
    "XCTUnwrap", "assert", "precondition",
)
SYNC_CLOSURES = ("map", "flatMap", "compactMap", "filter", "forEach", "first", "contains")


def strip_for_balance(source: str) -> str:
    """Removes comments and string literals so counting means something."""
    parts = source.split('"""')
    text = "".join(parts[i] for i in range(0, len(parts), 2))
    out, i, n = [], 0, len(text)
    in_string = in_line = in_block = False
    while i < n:
        char = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_line:
            if char == "\n":
                in_line = False
        elif in_block:
            if char == "*" and nxt == "/":
                in_block = False
                i += 1
        elif in_string:
            if char == "\\":
                i += 1
            elif char == '"':
                in_string = False
        else:
            if char == "/" and nxt == "/":
                in_line = True
                i += 1
            elif char == "/" and nxt == "*":
                in_block = True
                i += 1
            elif char == '"':
                in_string = True
            else:
                out.append(char)
        i += 1
    return "".join(out)


def check(path: pathlib.Path) -> list[str]:
    source = path.read_text()
    problems: list[str] = []

    def at(offset: int) -> int:
        return source[:offset].count("\n") + 1

    for name in AUTOCLOSURE_CALLS:
        for match in re.finditer(rf"\b{name}\s*\(\s*await\b", source):
            problems.append(f"{path}:{at(match.start())}: await inside {name}'s autoclosure")

    for match in re.finditer(r"\?\?[^\n]*\bawait\b", source):
        problems.append(f"{path}:{at(match.start())}: await inside a ?? autoclosure")

    for name in SYNC_CLOSURES:
        for match in re.finditer(rf"\.{name}\s*\{{[^}}]{{0,240}}\bawait\b", source, re.S):
            problems.append(f"{path}:{at(match.start())}: await inside a synchronous .{name} closure")

    if re.search(r'Section\("[^"]*"\)\s*\{[^}]*\}\s*(header|footer):', source):
        problems.append(f"{path}: Section(title) with a trailing header/footer is not an initialiser")

    for match in re.finditer(r"id:\s*\\\.\d", source):
        problems.append(f"{path}:{at(match.start())}: key path into a tuple element")

    # An attribute separated from what it decorates. Inserting a function
    # above an existing one lands between `@ViewBuilder` and its `func` —
    # the attribute silently moves to the new function and the old one stops
    # being a view builder, which fails a long way from the edit.
    for match in re.finditer(r"@(ViewBuilder|MainActor|discardableResult|Sendable)\s*\n\s*///", source):
        problems.append(
            f"{path}:{at(match.start())}: @{match.group(1)} is separated from its declaration by a doc comment"
        )

    balanced = strip_for_balance(source)
    for opener, closer in (("{", "}"), ("(", ")"), ("[", "]")):
        delta = balanced.count(opener) - balanced.count(closer)
        if delta:
            problems.append(f"{path}: unbalanced {opener}{closer} ({delta:+d})")

    return problems


def main(argv: list[str]) -> int:
    roots = argv[1:] or ["Odomind", "OdomindCore", "OdomindTests", "OdomindUITests"]
    problems: list[str] = []
    checked = 0
    for root in roots:
        for path in sorted(pathlib.Path(root).rglob("*.swift")):
            checked += 1
            problems.extend(check(path))

    for problem in problems:
        print(problem)
    print(f"\n{checked} files checked, {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
