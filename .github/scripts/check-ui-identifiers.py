#!/usr/bin/env python3
"""Check that every accessibility identifier a UI test looks for exists.

A UI test that waits on an identifier the app never sets does not fail fast —
it fails after its timeout, on a macOS runner, at the end of a build. Twice
during this project that cost a full run to learn something a text search
answers in a second, so the search runs in CI instead.

This is deliberately conservative: it only reports identifiers a test names as
string literals that no source file in the app declares, and it accepts a
prefix match so interpolated identifiers like "maintenance.task.\\(id)" cover
"maintenance.task.engine-oil-and-filter".
"""

import pathlib
import re
import sys

# The whole argument to the call, so a conditional identifier declares both
# of its branches. A control that reads
# `.accessibilityIdentifier(isPrimary ? "a.b" : "a.c")` sets one of two real
# identifiers; matching only a literal that follows the paren saw neither, and
# reported a test looking for one of them as referencing something the app
# never sets.
DECLARED_CALL = re.compile(r'accessibilityIdentifier\(')
STRING_LITERAL = re.compile(r'"([^"]*)"')


def call_arguments(text: str, start: int) -> str:
    """The text between an opening paren and its match.

    Counting parens rather than stopping at the first `)`: an interpolated
    identifier such as `"jobs.task.\(result.definitionID)"` closes a paren
    inside its own string literal, and a non-greedy match ended there and
    truncated the identifier it was meant to read.
    """
    depth = 0
    index = start
    while index < len(text):
        character = text[index]
        if character == '"':
            index += 1
            while index < len(text) and text[index] != '"':
                index += 2 if text[index] == "\\" else 1
        elif character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
            if depth == 0:
                return text[start + 1:index]
        index += 1
    return ""
REFERENCED = (
    re.compile(r'element\(withIdentifier:\s*"([^"]+)"'),
    re.compile(
        r'app\.(?:buttons|textFields|secureTextFields|switches|otherElements'
        r'|staticTexts|cells|images|menuItems)\["([^"]+)"\]'
    ),
    # Helpers that take an identifier rather than returning an element. Without
    # these the check silently stops covering an identifier the moment a test
    # is refactored to go through one.
    re.compile(r'setSwitch\(\s*"([^"]+)"'),
)
NAV_TITLE = re.compile(r'navigationBars\["([^"]+)"\]')


def main(root: pathlib.Path) -> int:
    # Exact identifiers and interpolated prefixes are kept apart on purpose.
    # Treating every declared identifier as a prefix would accept
    # "garage.vehicleThatDoesNotExist" because "garage.vehicle" exists, which
    # is the mistake this script is here to catch.
    exact: set[str] = set()
    prefixes: set[str] = set()
    for path in (root / "Odomind").rglob("*.swift"):
        text = path.read_text()
        for call in DECLARED_CALL.finditer(text):
            for match in STRING_LITERAL.finditer(call_arguments(text, call.end() - 1)):
                value = match.group(1)
                if not value:
                    continue
                if "\\(" in value:
                    prefix = value.split("\\(")[0]
                    if prefix:
                        prefixes.add(prefix)
                else:
                    exact.add(value)
    declared = exact | prefixes

    referenced: dict[str, set[str]] = {}
    titles: set[str] = set()
    test_files = sorted(root.glob("Odomind*Tests/*.swift"))
    for path in test_files:
        text = path.read_text()
        titles.update(match.group(1) for match in NAV_TITLE.finditer(text))
        for pattern in REFERENCED:
            for match in pattern.finditer(text):
                referenced.setdefault(match.group(1), set()).add(path.name)

    def known(identifier: str) -> bool:
        # A navigation bar is addressed by its title, not an identifier.
        if identifier in exact or identifier in titles:
            return True
        return any(identifier.startswith(prefix) for prefix in prefixes)

    missing = sorted(i for i in referenced if not known(i))

    print(f"{len(exact)} identifier(s) and {len(prefixes)} interpolated prefix(es) declared across the app")
    print(f"{len(referenced)} identifier(s) referenced across {len(test_files)} test file(s)")

    if not missing:
        print("\nEvery identifier a UI test looks for exists in the app.")
        return 0

    print("\nReferenced by a test but never set by the app:")
    for identifier in missing:
        where = ", ".join(sorted(referenced[identifier]))
        print(f"  {identifier}  (from {where})")
    print("\nEither add the identifier to the view, or correct the test.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")))
