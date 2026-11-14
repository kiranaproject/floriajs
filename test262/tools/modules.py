"""Minimal ES-module bundler for the diagnostic Test262 adapter.

Test262 module tests use static ``import``/``export`` declarations. FloriaJS has
no module loader, so the runner lowers the module graph into one ordinary script
whose module bodies are functions over a small ``__require`` registry. This is a
deliberate diagnostic subset: bindings are snapshots rather than true live
bindings, and only static relative imports are supported.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import json
from pathlib import Path
import re
from typing import Iterable

IMPORT_RE = re.compile(
    r"^\s*import\s+(?:(?P<default>[A-Za-z_$][\w$]*)\s*,?\s*)?"
    r"(?:(?P<namespace>\*\s+as\s+(?P<nsname>[A-Za-z_$][\w$]*))\s*|"
    r"\{(?P<named>[^}]*)\}\s*)?"
    r"(?:from\s+)?[\"'](?P<spec>[^\"']+)[\"']\s*;?\s*$"
)
IMPORT_BARE_RE = re.compile(r"^\s*import\s+[\"'](?P<spec>[^\"']+)[\"']\s*;?\s*$")
EXPORT_DEFAULT_RE = re.compile(r"^\s*export\s+default\s+(?P<rest>.*)$")
EXPORT_DECL_RE = re.compile(
    r"^\s*export\s+(?P<kind>const|let|var|function|class)\s+(?P<rest>.*)$"
)
EXPORT_LIST_RE = re.compile(
    r"^\s*export\s*\{(?P<names>[^}]*)\}\s*(?:from\s+[\"'](?P<spec>[^\"']+)[\"'])?\s*;?\s*$"
)
EXPORT_STAR_RE = re.compile(
    r"^\s*export\s*\*\s*from\s+[\"'](?P<spec>[^\"']+)[\"']\s*;?\s*$"
)
DYNAMIC_IMPORT_RE = re.compile(r"import\s*\(\s*[\"']([^\"']+)[\"']\s*\)")
ATTRIBUTE_RE = re.compile(r"\s+(?:with|assert)\s*\{[^}]*\}\s*;?\s*$")


def _strip_attributes(line: str) -> str:
    return ATTRIBUTE_RE.sub("", line)


class ModuleError(ValueError):
    """A module graph cannot be resolved or lowered."""


@dataclass
class ModuleUnit:
    path: Path
    source: str
    imports: list[tuple[str, Path]] = field(default_factory=list)


def _resolve_specifier(base: Path, spec: str, root: Path,
                       allow_extensionless: bool = False) -> Path:
    if not spec.startswith(("./", "../")):
        raise ModuleError(f"unsupported non-relative module specifier: {spec!r}")
    candidate = (base / spec)
    if (candidate.suffix == "") and not allow_extensionless:
        candidate = candidate.with_suffix(".js")
    try:
        resolved = candidate.resolve(strict=True)
    except OSError as error:
        raise ModuleError(f"cannot resolve module {spec!r}: {error}") from error
    try:
        resolved.relative_to(root.resolve())
    except ValueError as error:
        raise ModuleError(f"module escapes its root: {spec!r}") from error
    if not resolved.is_file():
        raise ModuleError(f"module is not a file: {resolved}")
    return resolved


def _parse_imports(source: str, base: Path, root: Path) -> list[tuple[str, Path]]:
    found: list[tuple[str, Path]] = []
    for line in source.splitlines():
        is_text = bool(re.search(r"type\s*:\s*[\"']text[\"']", line))
        line = _strip_attributes(line)
        match = IMPORT_RE.match(line) or IMPORT_BARE_RE.match(line)
        if match:
            found.append((match.group("spec"), _resolve_specifier(
                base, match.group("spec"), root, allow_extensionless=is_text)))
            continue
        listing = EXPORT_LIST_RE.match(line)
        if listing and listing.group("spec"):
            spec = listing.group("spec")
            found.append((spec, _resolve_specifier(base, spec, root)))
            continue
        star = EXPORT_STAR_RE.match(line)
        if star:
            spec = star.group("spec")
            found.append((spec, _resolve_specifier(base, spec, root)))
            continue
        for dynamic in DYNAMIC_IMPORT_RE.finditer(line):
            spec = dynamic.group(1)
            found.append((spec, _resolve_specifier(base, spec, root)))
    return found


def collect_graph(entry: Path, root: Path) -> list[ModuleUnit]:
    """Return modules in depth-first dependency order."""
    root = root.resolve()
    seen: dict[Path, ModuleUnit] = {}
    visiting: set[Path] = set()

    def visit(path: Path) -> None:
        if path in seen:
            return
        if path in visiting:
            # A cycle is allowed: the __require cache returns the partially
            # initialized exports object, so the graph can be lowered.
            return
        visiting.add(path)
        try:
            source = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            raise ModuleError(f"cannot read module {path}: {error}") from error
        unit = ModuleUnit(path=path, source=source)
        for spec, dependency in _parse_imports(source, path.parent, root):
            unit.imports.append((spec, dependency))
            visit(dependency)
        visiting.remove(path)
        seen[path] = unit

    visit(entry.resolve())
    return list(seen.values())


def _parse_named_list(value: str) -> list[tuple[str, str]]:
    """Return (imported/local, local/exported) pairs for `a as b` lists."""
    pairs: list[tuple[str, str]] = []
    for item in value.split(","):
        item = item.strip()
        if not item:
            continue
        parts = re.split(r"\s+as\s+", item, maxsplit=1)
        first = parts[0].strip()
        second = parts[1].strip() if len(parts) > 1 else first
        if not re.fullmatch(r"[A-Za-z_$][\w$]*", first) or not re.fullmatch(
            r"[A-Za-z_$][\w$]*", second
        ):
            raise ModuleError(f"unsupported import/export name: {item!r}")
        pairs.append((first, second))
    return pairs


def _declared_names(kind: str, rest: str) -> list[str]:
    names: list[str] = []
    if kind in {"function", "class"}:
        match = re.match(r"([A-Za-z_$][\w$]*)", rest)
        if match:
            names.append(match.group(1))
        return names
    for declaration in rest.split(","):
        match = re.match(r"\s*([A-Za-z_$][\w$]*)", declaration)
        if match:
            names.append(match.group(1))
    return names


def _rewrite_source(text: str, import_map: dict[str, tuple[str, str]]) -> str:
    """Rewrite imported identifiers to live property reads.

    This is a diagnostic token rewriter, not a full parser. It skips strings,
    comments, property names, and declaration positions.
    """
    out: list[str] = []
    i = 0
    prev = ""
    n = len(text)
    while i < n:
        c = text[i]
        if c == "\x00":
            j = text.find("\x00", i + 1)
            j = n if j < 0 else j + 1
            out.append(text[i:j])
            i = j
            continue
        if c in "'\"":
            quote = c
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == quote:
                    j += 1
                    break
                j += 1
            out.append(text[i:j])
            i = j
            prev = "string"
            continue
        if c == "`":
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == "`":
                    j += 1
                    break
                j += 1
            out.append(text[i:j])
            i = j
            prev = "string"
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            if j < 0:
                j = n
            out.append(text[i:j])
            i = j
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(text[i:j])
            i = j
            continue
        if c.isalpha() or c in "_$":
            j = i + 1
            while j < n and (text[j].isalnum() or text[j] in "_$"):
                j += 1
            ident = text[i:j]
            k = j
            while k < n and text[k] in " \t\r\n":
                k += 1
            nxt = text[k] if k < n else ""
            if (
                ident in import_map
                and prev not in (".", "?.")
                and prev
                not in (
                    "var",
                    "let",
                    "const",
                    "function",
                    "class",
                    "catch",
                    "import",
                    "export",
                )
                and nxt != ":"
            ):
                temp, name = import_map[ident]
                if prev in ("{", ",") and nxt in (",", "}"):
                    out.append(f"{ident}: {temp}.{name}")
                else:
                    out.append(f"{temp}.{name}")
                prev = "identifier"
                i = j
                continue
            out.append(ident)
            prev = ident
            i = j
            continue
        if not c.isspace():
            prev = c
        out.append(c)
        i += 1
    return "".join(out)


def _js_literal(value: object) -> str:
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list):
        return "[" + ", ".join(_js_literal(item) for item in value) + "]"
    if isinstance(value, dict):
        return "{" + ", ".join(
            f"{json.dumps(str(key))}: {_js_literal(item)}" for key, item in value.items()
        ) + "}"
    raise ModuleError(f"unsupported JSON value: {value!r}")


def lower_module(unit: ModuleUnit, root: Path) -> tuple[str, list[str]]:
    """Lower one module body into a function over (exports, __require)."""
    if unit.path.suffix == ".json":
        try:
            data = json.loads(unit.source)
        except json.JSONDecodeError as error:
            raise ModuleError(f"invalid JSON module {unit.path}: {error}") from error
        return (
            f'var __json = {_js_literal(data)};\n'
            'Object.defineProperty(exports, "default", { get: function () { return __json; }, enumerable: true });',
            [],
        )

    if unit.path.suffix not in (".js", ".mjs", ".cjs"):
        return (
            f'Object.defineProperty(exports, "default", {{ get: function () {{ return {json.dumps(unit.source)}; }}, enumerable: true }});',
            [],
        )

    lines = unit.source.splitlines()
    prelude: list[str] = []
    body: list[str] = []
    reexports: list[tuple[str, Path, list[tuple[str, str]]]] = []
    stars: list[tuple[str, Path]] = []
    import_map: dict[str, tuple[str, str]] = {}

    def add(text: str, generated: bool = False) -> None:
        (prelude if generated else body).append(text)

    for index, line in enumerate(lines):
        is_text = bool(re.search(r"type\s*:\s*[\"']text[\"']", line))
        line = _strip_attributes(line)
        bare = IMPORT_BARE_RE.match(line)
        if bare:
            spec = bare.group("spec")
            resolved = _resolve_specifier(unit.path.parent, spec, root,
                                          allow_extensionless=is_text)
            add(f'__require("{resolved}");', True)
            continue

        match = IMPORT_RE.match(line)
        if match:
            spec = match.group("spec")
            resolved = _resolve_specifier(unit.path.parent, spec, root,
                                          allow_extensionless=is_text)
            temp = f"__mod{index}"
            if match.group("default"):
                add(f'var {temp} = __require("{resolved}");', True)
                import_map[match.group("default")] = (temp, "default")
            if match.group("nsname"):
                add(f'var {match.group("nsname")} = __require("{resolved}");', True)
            if match.group("named"):
                add(f'var {temp} = __require("{resolved}");', True)
                for imported, local in _parse_named_list(match.group("named")):
                    import_map[local] = (temp, imported)
            continue

        star = EXPORT_STAR_RE.match(line)
        if star:
            stars.append((star.group("spec"), _resolve_specifier(
                unit.path.parent, star.group("spec"), root)))
            continue

        listing = EXPORT_LIST_RE.match(line)
        if listing:
            pairs = _parse_named_list(listing.group("names"))
            if listing.group("spec"):
                resolved = _resolve_specifier(
                    unit.path.parent, listing.group("spec"), root)
                reexports.append((listing.group("spec"), resolved, pairs))
            else:
                for local, exported in pairs:
                    if local in import_map:
                        temp, name = import_map[local]
                        expr = f"{temp}.{name}"
                    else:
                        expr = local
                    add(
                        f'Object.defineProperty(exports, "{exported}", {{ get: function () {{ return {expr}; }}, enumerable: true }});',
                        True,
                    )
            continue

        default = EXPORT_DEFAULT_RE.match(line)
        if default:
            rest = default.group("rest")
            named = re.match(r"(function|class)\s+([A-Za-z_$][\w$]*)", rest)
            if named:
                add(f"{named.group(1)} {named.group(2)}{rest[len(named.group(0)):]}", False)
                add(
                    f'Object.defineProperty(exports, "default", {{ get: function () {{ return {named.group(2)}; }}, enumerable: true }});',
                    True,
                )
            else:
                add(f"var __default = {rest}", False)
                add(
                    'Object.defineProperty(exports, "default", { get: function () { return __default; }, enumerable: true });',
                    True,
                )
            continue

        declaration = EXPORT_DECL_RE.match(line)
        if declaration:
            kind = declaration.group("kind")
            rest = declaration.group("rest")
            add(f"{kind} {rest}", False)
            for name in _declared_names(kind, rest):
                add(
                    f'Object.defineProperty(exports, "{name}", {{ get: function () {{ return {name}; }}, enumerable: true }});',
                    True,
                )
            continue

        add(line, False)

    for spec, resolved, pairs in reexports:
        for local, exported in pairs:
            add(
                f'Object.defineProperty(exports, "{exported}", {{ get: function () {{ return __require("{resolved}").{local}; }}, enumerable: true }});',
                True,
            )
    body_text = _rewrite_source("\n".join(body), import_map)
    body_text = body_text.replace("import.meta", "__importMeta")

    def dynamic_import(match: re.Match[str]) -> str:
        spec = match.group(1)
        try:
            resolved = _resolve_specifier(unit.path.parent, spec, root)
        except ModuleError:
            return match.group(0)
        return f'Promise.resolve(__require("{resolved}"))'

    body_text = re.sub(
        r"import\s*\(\s*[\"']([^\"']+)[\"']\s*(?:,\s*\{.*?\}\s*)?\)",
        dynamic_import,
        body_text,
    )
    prelude.insert(0, f'var __importMeta = {{ url: "{unit.path.as_uri()}" }};')
    return "\n".join(prelude) + "\n" + body_text, [str(resolved) for _, resolved in stars]


def build_bundle(entry: Path, root: Path) -> tuple[str, list[Path]]:
    """Build one script that evaluates the entry module and its dependencies."""
    units = collect_graph(entry, root)
    parts = [
        "(function () {",
        "var __modules = {};",
        "var __cache = {};",
        "var __starSpecs = {};",
        "var __starVisiting = {};",
        "function __require(id) {",
        "  if (__cache[id]) return __cache[id];",
        "  var exports = {};",
        "  if (__starSpecs[id]) {",
        "    var proxy = new Proxy(exports, {",
        "      get: function (t, k) {",
        "        if (k in t) return t[k];",
        "        if (k === 'default') return undefined;",
        "        var visitKey = id + \":\" + k;",
        "        if (__starVisiting[visitKey]) return undefined;",
        "        __starVisiting[visitKey] = true;",
        "        try {",
        "          var specs = __starSpecs[id];",
        "          for (var i = 0; i < specs.length; i++) {",
        "            var dep = __require(specs[i]);",
        "            if (k in dep) { var v = dep[k]; if (v !== undefined) return v; }",
        "          }",
        "          return undefined;",
        "        } finally {",
        "          __starVisiting[visitKey] = false;",
        "        }",
        "      },",
        "      has: function (t, k) {",
        "        if (k in t) return true;",
        "        var specs = __starSpecs[id];",
        "        for (var i = 0; i < specs.length; i++) {",
        "          if (k in __require(specs[i])) return true;",
        "        }",
        "        return false;",
        "      },",
        "      ownKeys: function (t) {",
        "        var keys = Object.keys(t);",
        "        var specs = __starSpecs[id];",
        "        for (var i = 0; i < specs.length; i++) {",
        "          var ks = Object.keys(__require(specs[i]));",
        "          for (var j = 0; j < ks.length; j++) {",
        "            if (ks[j] !== 'default' && keys.indexOf(ks[j]) < 0) keys.push(ks[j]);",
        "          }",
        "        }",
        "        return keys;",
        "      }",
        "    });",
        "    __cache[id] = proxy;",
        "  } else {",
        "    __cache[id] = exports;",
        "  }",
        "  __modules[id](exports, __require);",
        "  return __cache[id];",
        "}",
    ]
    for unit in units:
        body, star_specs = lower_module(unit, root)
        if star_specs:
            specs = ", ".join(f'"{spec}"' for spec in star_specs)
            parts.append(f'__starSpecs["{unit.path}"] = [{specs}];')
        parts.append(f'__modules["{unit.path}"] = function (exports, __require) {{')
        parts.append(body)
        parts.append("};")
    parts.append(f'__require("{entry.resolve()}");')
    parts.append("})();")
    return "\n".join(parts), [unit.path for unit in units]
