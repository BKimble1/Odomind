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


def argument_order_problems(path, source, at) -> list[str]:
    """Calls to a function declared in this same file whose argument labels are
    out of declaration order.

    Swift requires arguments in the order the function declares them, and gets
    strikingly unhelpful about it: writing `option(drive:fuel:)` for a function
    declared `option(fuel:drive:)` produced "value of type 'option' has no
    member 'applied'" and "type 'Equatable' has no member 'rearWheelDrive'",
    none of which mention the real mistake. That cost a ten-minute round trip
    to a macOS runner, which is what this file exists to prevent.

    Deliberately narrow, to stay free of false positives: only functions
    declared in the same file, only calls whose labels are all known to that
    declaration, and only a strict out-of-order finding. Overloads are skipped
    entirely — two declarations of one name make "the declaration order"
    meaningless here.
    """
    problems: list[str] = []

    declarations: dict[str, list[str] | None] = {}
    for match in re.finditer(r"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^>]*>)?\s*\(", source):
        name = match.group(1)
        params = balanced_span(source, match.end() - 1)
        if params is None:
            declarations[name] = None
            continue
        labels = declared_labels(params)
        if name in declarations:
            # An overload. Which declaration a call means is not something
            # this checker can know, so it stops checking that name.
            declarations[name] = None
        else:
            declarations[name] = labels

    known = {name: labels for name, labels in declarations.items() if labels}

    for name, labels in known.items():
        position = {label: index for index, label in enumerate(labels)}
        for match in re.finditer(r"(?<![\w.])" + re.escape(name) + r"\s*\(", source):
            # The declaration itself, not a call.
            prefix = source[max(0, match.start() - 6):match.start()]
            if prefix.rstrip().endswith("func"):
                continue
            args = balanced_span(source, match.end() - 1)
            if args is None:
                continue
            used = call_labels(args)
            if len(used) < 2 or any(label not in position for label in used):
                continue
            indices = [position[label] for label in used]
            if indices != sorted(indices):
                problems.append(
                    f"{path}:{at(match.start())}: {name}(...) passes "
                    + ", ".join(used)
                    + " but is declared "
                    + ", ".join(labels)
                )
    return problems


def balanced_span(source: str, open_index: int) -> str | None:
    """The text inside the parentheses starting at `open_index`, or None.

    String literals are skipped rather than bailed on: a bracket or a comma
    inside a string is text, not structure. The first version of this returned
    None on the first quote, which meant it silently checked nothing at all —
    every call it was written for has a string in it.
    """
    depth = 0
    index = open_index
    while index < len(source):
        character = source[index]
        if character == '"':
            index = skip_string(source, index)
            continue
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth -= 1
            if depth == 0:
                return source[open_index + 1:index]
        index += 1
    return None


def skip_string(source: str, quote_index: int) -> int:
    """The index just past the string literal starting at `quote_index`.

    Interpolation is treated as part of the string, which is right for this
    purpose: `"\\(a), \\(b)"` is one argument, not two.
    """
    index = quote_index + 1
    while index < len(source):
        character = source[index]
        if character == "\\":
            index += 2
            continue
        if character == '"':
            return index + 1
        if character == "\n":
            # An unterminated literal. Stop rather than run to the end of the
            # file and mis-read everything after it.
            return index
        index += 1
    return index


def declared_labels(params: str) -> list[str] | None:
    """The external labels of a parameter list, or None where they cannot be
    read confidently."""
    labels: list[str] = []
    for part in split_top_level(params):
        part = part.strip()
        if not part:
            continue
        head = part.split(":", 1)[0].strip()
        words = head.split()
        if not words or len(words) > 2:
            return None
        label = words[0]
        if label == "_":
            return None
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", label):
            return None
        labels.append(label)
    return labels or None


def call_labels(args: str) -> list[str]:
    """The labels actually written at a call site. An unlabelled argument
    makes the call unreadable to this check, which returns nothing."""
    labels: list[str] = []
    for part in split_top_level(args):
        part = part.strip()
        if not part:
            continue
        match = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*:", part)
        if not match:
            return []
        labels.append(match.group(1))
    return labels


def split_top_level(text: str) -> list[str]:
    """Splits on commas that are not inside brackets, a string or a closure."""
    parts: list[str] = []
    depth = 0
    in_string = False
    start = 0
    index = 0
    while index < len(text):
        character = text[index]
        if in_string:
            if character == "\\":
                index += 2
                continue
            if character == '"':
                in_string = False
        elif character == '"':
            in_string = True
        elif character in "([{":
            depth += 1
        elif character in ")]}":
            depth -= 1
        elif character == "," and depth == 0:
            parts.append(text[start:index])
            start = index + 1
        index += 1
    parts.append(text[start:])
    return parts


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

    problems.extend(argument_order_problems(path, source, at))

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
