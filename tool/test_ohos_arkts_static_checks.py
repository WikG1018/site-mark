"""Lightweight ArkTS (.ets) static pre-checks for host gates.

The HarmonyOS SDK (and therefore the real ArkTS compiler) is unavailable on CI
runners, so syntax-level breakage only surfaces on a developer machine. This
module adds conservative tripwire checks that run everywhere: unbalanced
brackets, dangling else, duplicated struct/class fields, and references to
project-exported symbols that are neither imported nor locally declared.

Precision beats recall: every check works on comment/string-masked sources and
only reports shapes that are illegal by construction. Missing-import detection
indexes project-wide `export` declarations and flags only those symbols, so
ambient ArkUI globals (Text, Math, ...) can never produce a false positive.
"""

import re
import sys
import tempfile
import unittest
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ETS_ROOT = ROOT / "ohos-native" / "entry" / "src"

BRACKETS = {"(": ")", "[": "]", "{": "}"}
CLOSERS = ")]}"

REGEX_PRECEDERS = set('(=,:[!&|?{};+-*%~^<>') | {""}

REGEX_KEYWORDS = frozenset((
    "return", "typeof", "instanceof", "in", "of", "new", "delete",
    "void", "throw", "case", "do", "else", "yield", "await",
))

TYPE_HEADER = re.compile(r"\b(?:abstract\s+)?(?:class|struct|interface)\s+([A-Za-z_$][\w$]*)")

FIELD_DECLARATION = re.compile(
    r"^\s*(?:@\w+\s+)*(?:public|private|protected|internal)\s+"
    r"(?:(?:readonly|static|final)\s+)*"
    r"([A-Za-z_$][\w$]*)\s*[:=]"
)

LOCAL_DECLARATION = re.compile(
    r"^\s*(?:export\s+)?(?:default\s+)?(?:declare\s+)?(?:abstract\s+)?(?:async\s+)?"
    r"(?:class|struct|enum|interface|type|function|const|let)\s+([A-Za-z_$][\w$]*)",
    re.M,
)

EXPORT_DECLARATION = re.compile(
    r"^\s*export\s+(?:default\s+)?(?:declare\s+)?(?:abstract\s+)?(?:async\s+)?"
    r"(?:class|struct|enum|interface|type|function|const|let)\s+([A-Za-z_$][\w$]*)",
    re.M,
)

EXPORT_LIST_FROM = re.compile(r"export\s*\{([^}]*)\}\s*from\s*['\"]([^'\"]+)['\"]")

IMPORT_BRACES = re.compile(r"\bimport\s*(?:type\s+)?\{([^{}]*)\}\s*from", re.S)

IMPORT_DEFAULT = re.compile(r"^\s*import\s+([A-Za-z_$][\w$]*)\s+from\b", re.M)

IMPORT_NAMESPACE = re.compile(r"\bimport\s*\*\s*as\s+([A-Za-z_$][\w$]*)\s+from")

IDENTIFIER = re.compile(r"[A-Za-z_$][\w$]*")

TRAILING_DECL_KEYWORD = re.compile(r"(?:class|struct|enum|interface|type|function|const|let|var)$")

DANGLING_ELSE_INLINE_BODY = re.compile(
    r"^[ \t]*if[ \t]*\((?:[^()]|\([^()]*\))*\)[ \t]*[^{\s][^\n]*;[ \t]*\r?\n"
    r"(?:[ \t]*(?!else\b)[^{}\s][^\n]*;[ \t]*\r?\n)+"
    r"[ \t]*else\b",
    re.M,
)

DANGLING_ELSE_BARE_HEADER = re.compile(
    r"^[ \t]*if[ \t]*\((?:[^()]|\([^()]*\))*\)[ \t]*\r?\n"
    r"(?:[ \t]*(?!else\b)[^{}\s][^\n]*;[ \t]*\r?\n){2,}"
    r"[ \t]*else\b",
    re.M,
)


@dataclass(frozen=True)
class Finding:
    path: Path
    line: int
    message: str


def mask_source(source: str) -> str:
    """Blank out comments and literal text; keep code, including ${...} parts."""
    out = list(source)
    n = len(source)
    i = 0
    frames: list[list] = []
    prev = ""
    word = ""
    contiguous = False

    def blank(position: int) -> None:
        if source[position] != "\n":
            out[position] = " "

    while i < n:
        ch = source[i]
        pair = source[i:i + 2]
        top = frames[-1] if frames else None
        if top is not None and top[0] == "tpl":
            if ch == "`":
                frames.pop()
                prev = "`"
                word = ""
                contiguous = False
                i += 1
            elif ch == "\\":
                blank(i)
                if i + 1 < n:
                    blank(i + 1)
                i += 2
            elif pair == "${":
                frames.append(["interp", 0])
                prev = "{"
                word = ""
                contiguous = False
                i += 2
            else:
                blank(i)
                i += 1
            continue
        if pair == "//":
            end = source.find("\n", i)
            end = n if end == -1 else end
            for k in range(i, end):
                blank(k)
            i = end
        elif pair == "/*":
            end = source.find("*/", i + 2)
            end = n if end == -1 else end + 2
            for k in range(i, end):
                blank(k)
            i = end
        elif ch in "'\"":
            quote = ch
            i += 1
            while i < n:
                c = source[i]
                if c == "\\":
                    blank(i)
                    if i + 1 < n:
                        blank(i + 1)
                    i += 2
                    continue
                if c == quote or c == "\n":
                    break
                blank(i)
                i += 1
            i += 1
            prev = quote
            word = ""
            contiguous = False
        elif ch == "`":
            frames.append(["tpl"])
            prev = "`"
            word = ""
            contiguous = False
            i += 1
        elif ch == "/" and (prev in REGEX_PRECEDERS or word in REGEX_KEYWORDS):
            blank(i)
            i += 1
            in_class = False
            while i < n:
                c = source[i]
                if c == "\\":
                    blank(i)
                    if i + 1 < n:
                        blank(i + 1)
                    i += 2
                    continue
                if c == "\n":
                    break
                if c == "[":
                    in_class = True
                elif c == "]":
                    in_class = False
                elif c == "/" and not in_class:
                    blank(i)
                    i += 1
                    while i < n and (source[i].isalnum() or source[i] in "_$"):
                        blank(i)
                        i += 1
                    break
                blank(i)
                i += 1
            prev = "/"
            word = ""
            contiguous = False
        elif ch == "{" and top is not None and top[0] == "interp":
            top[1] += 1
            prev = "{"
            word = ""
            contiguous = False
            i += 1
        elif ch == "}" and top is not None and top[0] == "interp":
            if top[1] == 0:
                frames.pop()
            else:
                top[1] -= 1
            prev = "}"
            word = ""
            contiguous = False
            i += 1
        elif ch.isspace():
            i += 1
        else:
            if ch.isalnum() or ch in "_$":
                word = (word + ch)[-12:] if contiguous else ch
                contiguous = True
            else:
                word = ""
                contiguous = False
            prev = ch
            i += 1
    return "".join(out)


def line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def check_balance(path: Path, masked: str) -> list[Finding]:
    findings: list[Finding] = []
    stack: list[tuple[str, int]] = []
    for offset, ch in enumerate(masked):
        if ch == "\n":
            continue
        if ch in BRACKETS:
            stack.append((ch, line_of(masked, offset)))
        elif ch in CLOSERS:
            expected = BRACKETS[stack[-1][0]] if stack else None
            opener_line = stack.pop()[1] if stack else None
            if expected != ch:
                where = f" opened at line {opener_line}" if opener_line else ""
                findings.append(Finding(path, line_of(masked, offset), f"unbalanced '{ch}'{where}"))
    for opener, opener_line in stack:
        findings.append(Finding(path, opener_line, f"unclosed '{opener}'"))
    return findings


def check_dangling_else(path: Path, masked: str) -> list[Finding]:
    findings: list[Finding] = []
    for pattern in (DANGLING_ELSE_INLINE_BODY, DANGLING_ELSE_BARE_HEADER):
        for match in pattern.finditer(masked):
            findings.append(
                Finding(path, line_of(masked, match.start()), "dangling else binds outside the if body")
            )
    return findings


def check_duplicate_fields(path: Path, masked: str) -> list[Finding]:
    findings: list[Finding] = []
    seen: dict[tuple[str, str], int] = {}
    scopes: list[tuple[str, int]] = []
    pending_type: str | None = None
    depth = 0
    for line_number, line in enumerate(masked.splitlines(), start=1):
        header = TYPE_HEADER.search(line)
        if header is not None:
            pending_type = header.group(1)
        for _ in range(line.count("{")):
            depth += 1
            if pending_type is not None:
                scopes.append((pending_type, depth))
                pending_type = None
        for _ in range(line.count("}")):
            if scopes and scopes[-1][1] == depth:
                scopes.pop()
            depth -= 1
            pending_type = None
        field_match = FIELD_DECLARATION.match(line)
        if field_match is None or not scopes:
            continue
        key = (scopes[-1][0], field_match.group(1))
        if key in seen:
            findings.append(
                Finding(
                    path,
                    line_number,
                    f"duplicate field '{key[1]}' in '{key[0]}' (first at line {seen[key]})",
                )
            )
        else:
            seen[key] = line_number
    return findings


def _collect_import_bindings(masked: str) -> tuple[set[str], list[tuple[int, int]]]:
    bindings: set[str] = set()
    spans: list[tuple[int, int]] = []
    for match in IMPORT_BRACES.finditer(masked):
        spans.append(match.span())
        for item in match.group(1).split(","):
            item = re.sub(r"^type\s+", "", item.strip())
            parts = item.split()
            if parts:
                bindings.add(parts[-1])
    for match in IMPORT_DEFAULT.finditer(masked):
        spans.append(match.span())
        bindings.add(match.group(1))
    for match in IMPORT_NAMESPACE.finditer(masked):
        spans.append(match.span())
        bindings.add(match.group(1))
    return bindings, spans


def check_missing_imports(
    path: Path,
    masked: str,
    export_index: dict[str, set[str]],
) -> list[Finding]:
    bindings, import_spans = _collect_import_bindings(masked)
    known = bindings | set(LOCAL_DECLARATION.findall(masked))
    findings: list[Finding] = []
    for match in IDENTIFIER.finditer(masked):
        name = match.group(0)
        if not name[0].isupper():
            continue
        if any(start <= match.start() < end for start, end in import_spans):
            continue
        before = masked[:match.start()].rstrip()
        if before.endswith(".") or before.endswith("@"):
            continue
        trailing = re.search(r"([A-Za-z_$][\w$]*)$", before)
        if trailing is not None and TRAILING_DECL_KEYWORD.fullmatch(trailing.group(1)):
            continue
        after = masked[match.end():].lstrip()
        if after.startswith(":") and (before.endswith("{") or before.endswith(",")):
            continue
        if name in known or name not in export_index:
            continue
        known.add(name)
        hints = ", ".join(sorted(export_index[name])[:2])
        findings.append(Finding(path, line_of(masked, match.start()), f"missing import '{name}' (defined in {hints})"))
    return findings


def _display_path(path: Path, anchor: Path) -> str:
    try:
        return path.resolve().relative_to(anchor.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def build_export_index(sources: dict[Path, str], anchor: Path = ROOT) -> dict[str, set[str]]:
    index: dict[str, set[str]] = {}
    for path, source in sources.items():
        display = _display_path(path, anchor)
        for name in EXPORT_DECLARATION.findall(source):
            index.setdefault(name, set()).add(display)
        for match in EXPORT_LIST_FROM.finditer(source):
            specifier = match.group(2)
            if not specifier.startswith("."):
                continue
            target = _display_path((path.parent / specifier).with_suffix(".ets"), anchor)
            for item in match.group(1).split(","):
                item = re.sub(r"^type\s+", "", item.strip())
                parts = item.split()
                if parts:
                    index.setdefault(parts[-1], set()).add(target)
    return index


def load_sources(root: Path = ETS_ROOT) -> dict[Path, str]:
    return {
        path: path.read_text(encoding="utf-8")
        for path in sorted(root.rglob("*.ets"))
        if path.is_file()
    }


def analyze_sources(sources: dict[Path, str], anchor: Path = ROOT) -> list[Finding]:
    export_index = build_export_index(sources, anchor)
    findings: list[Finding] = []
    for path, source in sources.items():
        masked = mask_source(source)
        findings.extend(check_balance(path, masked))
        findings.extend(check_dangling_else(path, masked))
        findings.extend(check_duplicate_fields(path, masked))
        findings.extend(check_missing_imports(path, masked, export_index))
    return findings


def format_findings(findings: list[Finding], anchor: Path = ROOT) -> str:
    return "\n".join(f"{_display_path(f.path, anchor)}:{f.line}: {f.message}" for f in findings)


def main() -> int:
    sources = load_sources()
    findings = analyze_sources(sources)
    if findings:
        print(format_findings(findings))
        print(f"ArkTS static checks failed: {len(findings)} finding(s)")
        return 1
    print(f"ArkTS static checks passed ({len(sources)} files)")
    return 0


class ArktsStaticChecksTest(unittest.TestCase):
    def analyze_tree(self, files: dict[str, str]) -> list[Finding]:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            paths = {}
            for name, content in files.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")
                paths[path] = content
            return analyze_sources(paths, anchor=root)

    def test_mask_hides_comments_strings_and_template_text(self) -> None:
        source = (
            "// comment with ) and {\n"
            "/* block ) ] } */\n"
            'const a = "string ) ]";\n'
            "const b = 'string }';\n"
            "const c = `template ) { text`;\n"
            "keep(1);\n"
        )
        masked = mask_source(source)
        self.assertEqual(len(masked), len(source))
        for hidden in ("comment", "block", "string", "template"):
            self.assertNotIn(hidden, masked)
        self.assertIn("keep(1);", masked)
        self.assertEqual([], check_balance(Path("x.ets"), masked))

    def test_mask_keeps_template_interpolations_braced(self) -> None:
        source = "const s = `a${fn({k: 1})}b ${ `nested${x}` }c`;\nend();\n"
        masked = mask_source(source)
        flat = masked.replace(" ", "")
        self.assertIn("fn({k: 1})", masked)
        self.assertIn("${x}", flat)
        self.assertNotIn("nested", masked)
        self.assertIn("end();", masked)
        self.assertEqual([], check_balance(Path("x.ets"), masked))

    def test_balance_reports_unclosed_and_extra_closers(self) -> None:
        self.assertEqual(1, len(check_balance(Path("x.ets"), mask_source("const x = (1 + 2;\n"))))
        self.assertEqual(1, len(check_balance(Path("x.ets"), mask_source("done();\n}\n"))))

    def test_regex_literals_are_masked_even_with_quotes_inside(self) -> None:
        source = (
            "const safe = name.replace(/[\\s~ \\/\\\\:*?\"<>|]+/g, '_');\n"
            "const avg = total / count;\n"
            "keep(1);\n"
        )
        masked = mask_source(source)
        self.assertNotIn('"<>|', masked)
        self.assertIn("total / count;", masked)
        self.assertIn("keep(1);", masked)
        self.assertEqual([], check_balance(Path("x.ets"), masked))

    def test_else_if_chain_with_inline_bodies_is_not_flagged(self) -> None:
        source = (
            "onAction: (id: string): void => {\n"
            "  if (id === 'export') this.batchExport();\n"
            "  else if (id === 'save') this.batchRepublish();\n"
            "  else if (id === 'clear') this.batchClearOriginals();\n"
            "  else this.batchDelete();\n"
            "}\n"
        )
        self.assertEqual([], check_dangling_else(Path("x.ets"), mask_source(source)))

    def test_dangling_else_illegal_shapes_are_flagged(self) -> None:
        inline_body = (
            "if (cond) first();\n"
            "second();\n"
            "else {\n"
            "  third();\n"
            "}\n"
        )
        self.assertEqual(1, len(self.analyze_tree({"a.ets": inline_body})))
        bare_header = (
            "if (cond)\n"
            "  first();\n"
            "  second();\n"
            "else\n"
            "  third();\n"
        )
        self.assertEqual(1, len(self.analyze_tree({"b.ets": bare_header})))

    def test_legal_else_shapes_are_not_flagged(self) -> None:
        legal_cases = [
            "if (cond) {\n  first();\n} else {\n  second();\n}\n",
            "if (cond)\n  first();\nelse\n  second();\n",
            "if (cond) first();\nelse second();\n",
            "if (longCondition ||\n    otherCondition) {\n  work();\n} else {\n  stop();\n}\n",
            "if (a) {\n  b();\n} else if (c) {\n  d();\n}\n",
            "if (cond) { done(); }\nlog(other);\n",
        ]
        for index, source in enumerate(legal_cases):
            findings = self.analyze_tree({f"legal-{index}.ets": source})
            self.assertEqual([], [f.message for f in findings if "dangling" in f.message], source)

    def test_duplicate_fields_in_same_struct_are_flagged(self) -> None:
        source = (
            "@Component\n"
            "struct Screen {\n"
            "  @State private message: string = '';\n"
            "  private timer: number = -1;\n"
            "  @State private message: string = '';\n"
            "  private setMessage(text: string): void {\n"
            "    this.message = text;\n"
            "  }\n"
            "}\n"
        )
        findings = self.analyze_tree({"dup.ets": source})
        self.assertEqual(1, len(findings))
        self.assertIn("duplicate field 'message'", findings[0].message)

    def test_same_field_name_across_siblings_is_clean(self) -> None:
        source = (
            "struct First {\n"
            "  private message: string = '';\n"
            "}\n\n"
            "struct Second {\n"
            "  private message: string = '';\n"
            "}\n"
        )
        self.assertEqual([], self.analyze_tree({"ok.ets": source}))

    def test_missing_import_is_reported_with_definition_hint(self) -> None:
        tree = {
            "shared/Feedback.ets": "export class ScreenMessageClock {}\n",
            "feature/Screen.ets": (
                "import { tr } from '../shared/AppText';\n\n"
                "struct Demo {\n"
                "  private clock = new ScreenMessageClock();\n"
                "}\n"
            ),
        }
        findings = self.analyze_tree(tree)
        self.assertEqual(1, len(findings))
        self.assertIn("'ScreenMessageClock'", findings[0].message)
        self.assertIn("shared/Feedback.ets", findings[0].message)

    def test_imported_symbol_is_clean(self) -> None:
        tree = {
            "shared/Feedback.ets": "export class ScreenMessageClock {}\n",
            "feature/Screen.ets": (
                "import { ScreenMessageClock } from '../shared/Feedback';\n\n"
                "struct Demo {\n"
                "  private clock = new ScreenMessageClock();\n"
                "}\n"
            ),
        }
        self.assertEqual([], self.analyze_tree(tree))

    def test_ambient_globals_never_flagged(self) -> None:
        source = (
            "struct Demo {\n"
            "  build() {\n"
            "    Text(Math.max(1, 2).toString())\n"
            "      .fontColor(Color.White)\n"
            "      .fontSize(JSON.parse('12'))\n"
            "  }\n"
            "}\n"
        )
        self.assertEqual([], self.analyze_tree({"amb.ets": source}))

    def test_real_ohos_tree_passes_all_checks(self) -> None:
        sources = load_sources()
        self.assertTrue(sources)
        findings = analyze_sources(sources)
        self.assertEqual([], findings, format_findings(findings))


if __name__ == "__main__":
    sys.exit(main())
