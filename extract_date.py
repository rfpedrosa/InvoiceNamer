#!/usr/bin/env python3
"""
Invoice Date Extractor

Reads OCR text on stdin, prints the most plausible invoice date as YYYY-MM-DD.
Prints nothing (exit 1) when no plausible date is found.

Receipts normally print the same date twice — once as the terminal timestamp
(YY-MM-DD hh:mm) and once as the emission date (DD-MM-YYYY). OCR rarely
mangles both the same way, so every candidate is collected and the one with
the most agreement wins.
"""

import re
import sys
from collections import Counter
from datetime import date

# Receipts older than this are almost certainly a misread, not a real date.
MIN_YEAR = 2015

# Characters Vision commonly substitutes for digits on thermal receipt print.
LOOKALIKE = str.maketrans(
    {
        "o": "0", "O": "0", "Q": "0", "D": "0",
        "l": "1", "I": "1", "i": "1", "|": "1", "!": "1", "[": "1", "]": "1",
        "z": "2", "Z": "2",
        "S": "5", "s": "5",
        "b": "6", "G": "6",
        "B": "8",
        "g": "9", "q": "9",
    }
)

SEP = r"[-/.,]{1,3}"

# YYYY-MM-DD (separators may be misread, e.g. "2026-07.20")
RE_YMD = re.compile(rf"(?<!\d)(\d{{4}}){SEP}(\d{{1,2}}){SEP}(\d{{1,2}})(?!\d)")
# DD-MM-YYYY (e.g. "15.-07-2026")
RE_DMY = re.compile(rf"(?<!\d)(\d{{1,2}}){SEP}(\d{{1,2}}){SEP}(\d{{4}})(?!\d)")
# YY-MM-DD — the format Portuguese payment terminals print
RE_YYMD = re.compile(rf"(?<!\d)(\d{{2}}){SEP}(\d{{2}}){SEP}(\d{{2}})(?!\d)")
# 20XX where one character of the year was misread entirely (e.g. "20?6-07-26")
RE_FUZZY_YEAR = re.compile(rf"(?<!\d)(2[0oOQ]\S{{2}}){SEP}(\d{{1,2}}){SEP}(\d{{1,2}})(?!\d)")


def _valid(year: int, month: int, day: int, today: date):
    """Return the date if it is a real, plausible invoice date, else None."""
    if not MIN_YEAR <= year <= today.year:
        return None
    try:
        candidate = date(year, month, day)
    except ValueError:
        return None
    # An invoice cannot be dated in the future.
    return candidate if candidate <= today else None


def _resolve_fuzzy_year(raw: str, today: date):
    """Rebuild a 4-character year in which some characters are not digits.

    Returns the most recent plausible year, or None if too little survived.
    """
    known = [(i, c) for i, c in enumerate(raw) if c.isdigit()]
    if len(known) < 3:
        return None
    for year in range(today.year, MIN_YEAR - 1, -1):
        text = str(year)
        if all(text[i] == c for i, c in known):
            return year
    return None


def _scan(text: str, today: date) -> Counter:
    """Collect every plausible date in one rendering of the OCR text."""
    found = Counter()

    for year, month, day in RE_YMD.findall(text):
        hit = _valid(int(year), int(month), int(day), today)
        if hit:
            found[hit] += 1

    for day, month, year in RE_DMY.findall(text):
        hit = _valid(int(year), int(month), int(day), today)
        if hit:
            found[hit] += 1

    for year, month, day in RE_YYMD.findall(text):
        hit = _valid(2000 + int(year), int(month), int(day), today)
        if hit:
            found[hit] += 1

    for year, month, day in RE_FUZZY_YEAR.findall(text):
        resolved = _resolve_fuzzy_year(year, today)
        if resolved:
            hit = _valid(resolved, int(month), int(day), today)
            if hit:
                found[hit] += 1

    return found


def _strip_dots(text: str) -> str:
    """Drop stray dots OCR inserts between digits (e.g. "2.026-0.4-12")."""
    previous = None
    while previous != text:
        previous = text
        text = re.sub(r"(\d)\.(\d)", r"\1\2", text)
    return text


def extract_date(text: str, today: date = None):
    """Pick the best-supported date from OCR text, or None."""
    today = today or date.today()

    # Each rendering repairs a different class of OCR damage. Take the highest
    # count a date reaches in any one of them rather than the sum, so a date
    # that survives every repair is not credited several times over.
    renderings = (
        text,
        _strip_dots(text),
        text.translate(LOOKALIKE),
        _strip_dots(text).translate(LOOKALIKE),
    )

    votes = Counter()
    for rendering in renderings:
        for hit, count in _scan(rendering, today).items():
            votes[hit] = max(votes[hit], count)

    if not votes:
        return None

    # Most corroborated wins; ties go to the most recent date, since a misread
    # digit in a receipt photographed days ago usually lands further in the past.
    return max(votes, key=lambda d: (votes[d], d))


if __name__ == "__main__":
    result = extract_date(sys.stdin.read())
    if result is None:
        sys.exit(1)
    print(result.isoformat())
