#!/usr/bin/env python3
"""
Apply Aider-style SEARCH/REPLACE blocks to files.

Input format (from stdin):
    <relative/path/to/file.py>
    <<<<<<< SEARCH
    <existing code to find>
    =======
    <replacement code>
    >>>>>>> REPLACE

Multiple blocks per invocation. Blocks may target different files.

Match strategy per block (in order):
  1. Exact substring match
  2. Whitespace-insensitive (collapse runs of whitespace)
  3. Indentation-preserving (strip leading whitespace from each line, then
     re-prepend the indent of the first matched line)
  4. difflib.SequenceMatcher fuzzy match (>= 0.9 ratio)

Outputs JSON to stdout:
    {"applied": N, "failed": M, "results": [{"file": "...", "ok": true|false, "strategy": "exact|...|fail", "reason": "..."}]}
Exit 0 if any blocks applied; non-zero if all failed.
"""
from __future__ import annotations

import difflib
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Block:
    file: str
    search: str
    replace: str


@dataclass
class Result:
    file: str
    ok: bool
    strategy: str
    reason: str = ""


SR_RE = re.compile(
    r"^([^\n]+?)\s*\n"               # file path on its own line
    r"<{5,}\s*SEARCH\s*\n"           # <<<<<<< SEARCH (>=5 chars to be lenient)
    r"(.*?)"                         # search content
    r"^={5,}\s*\n"                   # =======
    r"(.*?)"                         # replace content
    r"^>{5,}\s*REPLACE\s*$",         # >>>>>>> REPLACE
    re.MULTILINE | re.DOTALL,
)


def parse_blocks(text: str) -> list[Block]:
    blocks: list[Block] = []
    for m in SR_RE.finditer(text):
        path = m.group(1).strip().strip("`")
        search = m.group(2)
        replace = m.group(3)
        # Strip a single trailing newline if present (the marker line eats one)
        if search.endswith("\n"):
            search = search[:-1]
        if replace.endswith("\n"):
            replace = replace[:-1]
        blocks.append(Block(file=path, search=search, replace=replace))
    return blocks


def _collapse_ws(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def _try_exact(content: str, search: str, replace: str) -> tuple[str, bool]:
    if search in content:
        return content.replace(search, replace, 1), True
    return content, False


def _try_ws_insensitive(content: str, search: str, replace: str) -> tuple[str, bool]:
    needle = _collapse_ws(search)
    if not needle:
        return content, False
    # Slide a window through content, comparing collapsed forms
    haystack = content
    n_lines = len(search.splitlines())
    lines = haystack.splitlines(keepends=True)
    for i in range(len(lines) - n_lines + 1):
        chunk = "".join(lines[i : i + n_lines])
        if _collapse_ws(chunk) == needle:
            return haystack.replace(chunk, replace, 1), True
    return content, False


def _try_indent_preserving(content: str, search: str, replace: str) -> tuple[str, bool]:
    # Dedent both sides; find the dedented search; re-indent the replace
    def common_indent(s: str) -> str:
        lines = [line for line in s.splitlines() if line.strip()]
        if not lines:
            return ""
        return "".join(c for c in __import__("os").path.commonprefix(lines) if c in " \t")

    s_ind = common_indent(search)
    if not s_ind:
        return content, False
    dedented_search = "\n".join(
        (line[len(s_ind):] if line.startswith(s_ind) else line) for line in search.splitlines()
    )
    if dedented_search not in _collapse_ws_lines(content):
        # Try every contiguous slice of content with the same line count
        return content, False
    # Find actual indent in target
    lines = content.splitlines(keepends=True)
    n = len(search.splitlines())
    for i in range(len(lines) - n + 1):
        chunk = "".join(lines[i : i + n])
        chunk_ind = common_indent(chunk)
        if chunk_ind:
            dedented_chunk = "\n".join(
                (ln[len(chunk_ind):] if ln.startswith(chunk_ind) else ln)
                for ln in chunk.splitlines()
            )
            if dedented_chunk == dedented_search:
                # Re-indent replace using chunk_ind
                indented_replace = "\n".join(
                    (chunk_ind + ln if ln else ln) for ln in replace.splitlines()
                )
                return content.replace(chunk.rstrip("\n"), indented_replace, 1), True
    return content, False


def _collapse_ws_lines(s: str) -> str:
    return "\n".join(line.rstrip() for line in s.splitlines())


def _try_fuzzy(content: str, search: str, replace: str, threshold: float = 0.9) -> tuple[str, bool]:
    n_lines = len(search.splitlines())
    if n_lines == 0:
        return content, False
    lines = content.splitlines(keepends=True)
    best_ratio = 0.0
    best_idx = -1
    for i in range(len(lines) - n_lines + 1):
        chunk = "".join(lines[i : i + n_lines])
        ratio = difflib.SequenceMatcher(None, chunk, search).ratio()
        if ratio > best_ratio:
            best_ratio = ratio
            best_idx = i
    if best_ratio >= threshold and best_idx >= 0:
        chunk = "".join(lines[best_idx : best_idx + n_lines])
        return content.replace(chunk, replace + ("\n" if not replace.endswith("\n") else ""), 1), True
    return content, False


def apply_block(filepath: Path, block: Block) -> Result:
    if not filepath.exists():
        return Result(block.file, False, "fail", f"file not found: {filepath}")

    original = filepath.read_text()
    strategies = [
        ("exact", _try_exact),
        ("whitespace", _try_ws_insensitive),
        ("indent", _try_indent_preserving),
        ("fuzzy", _try_fuzzy),
    ]
    for name, fn in strategies:
        new_content, ok = fn(original, block.search, block.replace)
        if ok:
            filepath.write_text(new_content)
            return Result(block.file, True, name, "")
    return Result(block.file, False, "fail", "no strategy matched search snippet")


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: merge_sr.py <workdir> [< blocks.txt]", file=sys.stderr)
        return 2
    workdir = Path(sys.argv[1]).resolve()
    text = sys.stdin.read()
    blocks = parse_blocks(text)
    if not blocks:
        print(json.dumps({"applied": 0, "failed": 0, "results": [], "error": "no blocks parsed"}))
        return 1

    results: list[Result] = []
    for b in blocks:
        target = (workdir / b.file).resolve()
        # If exact path doesn't exist, try stripping leading dir components
        # (handles the case where the model emits "backend/app/foo.py" but
        # workdir is already "backend/")
        if not target.exists():
            parts = b.file.split("/")
            for i in range(1, len(parts)):
                candidate = (workdir / "/".join(parts[i:])).resolve()
                if candidate.exists():
                    target = candidate
                    break
        # Disallow escaping the workdir
        try:
            target.relative_to(workdir)
        except ValueError:
            results.append(Result(b.file, False, "fail", "path escapes workdir"))
            continue
        results.append(apply_block(target, b))

    applied = sum(1 for r in results if r.ok)
    failed = sum(1 for r in results if not r.ok)
    print(json.dumps({
        "applied": applied,
        "failed": failed,
        "results": [r.__dict__ for r in results],
    }))
    return 0 if applied > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
