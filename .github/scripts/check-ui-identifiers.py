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
# Titles the app actually sets, as literals. A dynamic title —
# `.navigationTitle(step.title)` — cannot be read here, so a test naming one
# is reported rather than silently accepted; the fix is to anchor that test on
# an accessibility identifier, which is what it should have used anyway.
DECLARED_TITLE = re.compile(r'\.navigationTitle\(')
TAB_TITLE = re.compile(r'case \.\w+:\s*return\s*"([^"]+)"')


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

    declared_titles: set[str] = set()
    for path in (root / "Odomind").rglob("*.swift"):
        text = path.read_text()
        for call in DECLARED_TITLE.finditer(text):
            # Every literal in the call, so a conditional title —
            # `.navigationTitle(isEditing ? "Edit service" : "Log service")` —
            # declares both of its branches rather than neither.
            for literal in STRING_LITERAL.finditer(call_arguments(text, call.end() - 1)):
                if literal.group(1):
                    declared_titles.add(literal.group(1))
        if path.name == "NavigationRouter.swift":
            declared_titles.update(m.group(1) for m in TAB_TITLE.finditer(text))

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
        if identifier in exact:
            return True
        return any(identifier.startswith(prefix) for prefix in prefixes)

    missing = sorted(i for i in referenced if not known(i))

    # A navigation bar is addressed by its title rather than an identifier, so
    # these are checked against the titles the app sets.
    #
    # Build 4 hid Home's navigation bar — a bar saying "Home" above a tab bar
    # saying "Home" was the third repeat on one screen — and twelve tests were
    # still waiting on `navigationBars["Home"]`. Sixteen of them failed in the
    # deploy's UI suite, which is a forty-minute way to learn something a text
    # search answers instantly.
    missing_titles = sorted(t for t in titles if t not in declared_titles)

    print(f"{len(exact)} identifier(s) and {len(prefixes)} interpolated prefix(es) declared across the app")
    print(f"{len(declared_titles)} navigation title(s) set by the app")
    print(f"{len(referenced)} identifier(s) and {len(titles)} navigation title(s) referenced "
          f"across {len(test_files)} test file(s)")

    if not missing and not missing_titles:
        print("\nEvery identifier and navigation title a UI test looks for exists in the app.")
        return 0

    if missing:
        print("\nReferenced by a test but never set by the app:")
        for identifier in missing:
            where = ", ".join(sorted(referenced[identifier]))
            print(f"  {identifier}  (from {where})")

    if missing_titles:
        print("\nNavigation bars a test waits for that the app does not title:")
        for title in missing_titles:
            print(f"  navigationBars[\"{title}\"]")
        print("  (a screen whose title is dynamic should be anchored on an "
              "accessibility identifier instead)")

    print("\nEither add it to the view, or correct the test.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")))
