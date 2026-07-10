#!/usr/bin/env python3
"""Remove SwiftUI #Preview-only string keys from String Catalogs (P10.11).

Compiler extraction (`l10n-extract.sh`) faithfully pulls every `Text("…")`
literal — including the demo text inside `#Preview { … }` blocks, which is
developer-only and must never reach translators. This script computes the set of
keys that appear **only** inside preview blocks (never in shipping code) and
deletes them from the given `.xcstrings` catalogs.

It is deliberately conservative — a key is deleted only when BOTH hold:
  1. it is produced by a `#Preview` block but NOT by any non-preview code
     (per `xcstringstool extract`'s lightweight parse), and
  2. its literal text does not appear anywhere in the preview-stripped source.
So any string used by real UI is always kept, even if it also appears in a
preview.

Usage:
  l10n-filter-previews.py --catalog <a.xcstrings> [--catalog <b.xcstrings> …] \
                          --source <dir> [--source <dir> …]
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

PREVIEW_RE = re.compile(r"#Preview\b")

# Developer-only files whose strings never ship — must match the denylist in
# l10n-extract.sh so they count as neither "real" nor "preview" code here.
DENY_FILE_RE = re.compile(
    r"(\+Previews|Gallery|PreviewSupport|DebugMenu|Diagnostics|Fixtures)[^/]*\.swift$"
)


def xcstrings_dump(obj, indent=0):
    """Serialize to Xcode's exact `.xcstrings` JSON style (byte-for-byte).

    Xcode uses 2-space indent, a ` : ` key/value separator, sorted keys, empty
    objects rendered as `{<newline><blank><indent>}`, and NO trailing newline.
    Matching it keeps `git diff`s to just the removed keys.
    """
    pad, pad2 = "  " * indent, "  " * (indent + 1)
    if isinstance(obj, dict):
        if not obj:
            return "{\n\n" + pad + "}"
        body = ",\n".join(
            f"{pad2}{json.dumps(k, ensure_ascii=False)} : {xcstrings_dump(obj[k], indent + 1)}"
            for k in sorted(obj)
        )
        return "{\n" + body + "\n" + pad + "}"
    if isinstance(obj, list):
        if not obj:
            return "[\n\n" + pad + "]"
        body = ",\n".join(pad2 + xcstrings_dump(v, indent + 1) for v in obj)
        return "[\n" + body + "\n" + pad + "]"
    if isinstance(obj, bool):
        return "true" if obj else "false"
    if isinstance(obj, (int, float)):
        return json.dumps(obj)
    return json.dumps(obj, ensure_ascii=False)


def split_previews(src: str) -> tuple[str, str]:
    """Return (preview_text, non_preview_text) by brace-matching #Preview blocks."""
    preview, non_preview = [], []
    i, n = 0, len(src)
    while i < n:
        m = PREVIEW_RE.search(src, i)
        if not m:
            non_preview.append(src[i:])
            break
        non_preview.append(src[i:m.start()])
        j = m.end()
        while j < n and src[j] != "{":
            j += 1
        if j >= n:
            break
        start, depth = j, 0
        while j < n:
            if src[j] == "{":
                depth += 1
            elif src[j] == "}":
                depth -= 1
                if depth == 0:
                    j += 1
                    break
            j += 1
        preview.append(src[start:j])
        i = j
    return "".join(preview), "".join(non_preview)


def extract_keys(swift_text: str) -> set[str]:
    """Run `xcstringstool extract` over a single synthetic Swift file → key set."""
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "input.swift"
        src.write_text("import SwiftUI\n" + swift_text)
        out = Path(tmp) / "out"
        out.mkdir()
        subprocess.run(
            ["xcrun", "xcstringstool", "extract", str(src),
             "--output-directory", str(out),
             "--SwiftUI", "--modern-localizable-strings",
             "--output-format", "xcstrings"],
            check=False, capture_output=True,
        )
        catalog = out / "Localizable.xcstrings"
        if not catalog.exists():
            return set()
        return set(json.loads(catalog.read_text()).get("strings", {}).keys())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", action="append", default=[], required=True)
    ap.add_argument("--source", action="append", default=[], required=True)
    ap.add_argument("--comments", default=None,
                    help="JSON sidecar mapping key → translator comment.")
    args = ap.parse_args()

    comments = {}
    if args.comments and Path(args.comments).exists():
        comments = json.loads(Path(args.comments).read_text())

    preview_text, nonpreview_text = [], []
    for root in args.source:
        for f in Path(root).rglob("*.swift"):
            if DENY_FILE_RE.search(f.name):
                continue  # denylisted dev-only file — ignore entirely
            a, b = split_previews(f.read_text(errors="ignore"))
            if a.strip():
                preview_text.append(a)
            nonpreview_text.append(b)

    preview_joined = "\n".join(preview_text)
    nonpreview_joined = "\n".join(nonpreview_text)

    preview_keys = extract_keys(preview_joined)
    real_keys = extract_keys(nonpreview_joined)

    # Preview-only = in previews, not in real code, and literal absent from
    # preview-stripped source (guards against the lightweight parser's gaps).
    preview_only = {
        k for k in (preview_keys - real_keys)
        if k not in nonpreview_joined
    }

    total_removed = 0
    total_commented = 0
    for catalog_path in args.catalog:
        path = Path(catalog_path)
        data = json.loads(path.read_text())
        strings = data.get("strings", {})

        removed = [k for k in list(strings) if k in preview_only]
        for k in removed:
            del strings[k]

        commented = 0
        for key, comment in comments.items():
            if key in strings and strings[key].get("comment") != comment:
                strings[key]["comment"] = comment
                commented += 1

        if removed or commented:
            path.write_text(xcstrings_dump(data))
            total_removed += len(removed)
            total_commented += commented
            msg = []
            if removed:
                msg.append(f"removed {len(removed)} preview key(s)")
            if commented:
                msg.append(f"added {commented} comment(s)")
            print(f"  {path.name}: {', '.join(msg)}")

    print(f"✓ preview filter: {total_removed} key(s) removed "
          f"({len(preview_only)} candidates); {total_commented} comment(s) applied")
    return 0


if __name__ == "__main__":
    sys.exit(main())
