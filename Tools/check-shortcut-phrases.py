#!/usr/bin/env python3
"""Every Siri phrase must be translated, or Siri only listens in English.

Build 16 shipped six App Shortcut phrases and no AppShortcuts.xcstrings. The
app compiled, the shortcuts appeared, and asking in German got "sorry, I
couldn't find anything" — Siri had never been taught the German wording and
handed the question to a web search instead. Nothing failed loudly enough to
notice: a missing translation is not a build error.

So the two are compared here. The phrases live in Swift as string
interpolations of `\\(.applicationName)`; the catalog spells the same
placeholder `${applicationName}`.
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SWIFT = ROOT / "DosiCrew/Features/Siri/DosiCrewShortcuts.swift"
CATALOG = ROOT / "DosiCrew/Resources/AppShortcuts.xcstrings"

# Languages the app ships in. A phrase present in only some of them is the
# same failure, one language at a time.
LANGUAGES = {"en", "de", "es"}


def phrases_in_swift() -> list[str]:
    source = SWIFT.read_text()
    # The phrases arrays, and only those: `shortTitle` and the rest are
    # ordinary strings that belong in Localizable.xcstrings.
    blocks = re.findall(r"phrases:\s*\[(.*?)\]", source, re.DOTALL)
    found = []
    for block in blocks:
        for literal in re.findall(r'"((?:[^"\\]|\\.)*)"', block):
            found.append(literal.replace("\\(.applicationName)", "${applicationName}"))
    return found


def main() -> int:
    if not CATALOG.exists():
        print(f"error: {CATALOG.relative_to(ROOT)} is missing entirely.")
        return 1

    catalog = json.loads(CATALOG.read_text())["strings"]
    problems = []

    for phrase in phrases_in_swift():
        entry = catalog.get(phrase)
        if entry is None:
            problems.append(f"not in the catalog at all: {phrase!r}")
            continue
        localizations = entry.get("localizations", {})
        for language in sorted(LANGUAGES - set(localizations)):
            problems.append(f"no {language} translation: {phrase!r}")
        for language, unit in localizations.items():
            value = unit.get("stringUnit", {}).get("value", "")
            # Siri needs the app named to know whose "record a dose" this is;
            # a translation that drops the placeholder never matches.
            if "${applicationName}" not in value:
                problems.append(
                    f"{language} translation does not name the app: {value!r}"
                )

    if problems:
        print("Siri phrases are not fully translated:\n")
        for problem in problems:
            print(f"  - {problem}")
        print(
            "\nAdd them to DosiCrew/Resources/AppShortcuts.xcstrings. "
            "Without a translation Siri only understands the English wording."
        )
        return 1

    print("All Siri phrases are translated into every language.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
