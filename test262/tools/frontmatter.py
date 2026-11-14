"""Strict, read-only parsing of Test262 YAML frontmatter.

Source files are read as bytes. Only the metadata inspection copy is decoded;
no source is normalized, concatenated, or rewritten.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml


START = "/*---"
CLOSE = "---*/"


class FrontmatterError(ValueError):
    """A test's metadata cannot be interpreted deterministically."""


@dataclass(frozen=True)
class Metadata:
    flags: tuple[str, ...] = ()
    includes: tuple[str, ...] = ()
    negative: dict[str, str] | None = None
    features: tuple[str, ...] = ()
    locale: tuple[str, ...] = ()
    has_frontmatter: bool = False
    non_deterministic: bool = False


@dataclass(frozen=True)
class SourceMetadata:
    metadata: Metadata
    content: bytes


def extract_frontmatter(source: bytes) -> tuple[str, bool]:
    """Return one metadata block without altering the original source bytes."""
    try:
        text = source.decode("utf-8", errors="strict")
    except UnicodeDecodeError as error:
        raise FrontmatterError(f"test source is not valid UTF-8: {error}") from error

    start = text.find(START)
    if start < 0:
        return "", False

    metadata_start = start + len(START)
    end = text.find(CLOSE, metadata_start)
    if end < 0:
        raise FrontmatterError("unterminated frontmatter block")
    if text.find(START, end + len(CLOSE)) >= 0:
        raise FrontmatterError("multiple frontmatter blocks")
    return text[metadata_start:end], True


def reject_duplicate_yaml_keys(document: Any) -> None:
    """SafeLoader otherwise silently lets the last duplicate key win."""
    if isinstance(document, yaml.MappingNode):
        seen: set[str] = set()
        for key_node, value_node in document.value:
            if key_node.tag != "tag:yaml.org,2002:str":
                raise FrontmatterError("metadata keys must be strings")
            if key_node.value in seen:
                raise FrontmatterError(f"duplicate metadata key: {key_node.value}")
            seen.add(key_node.value)
            reject_duplicate_yaml_keys(value_node)
    elif isinstance(document, yaml.SequenceNode):
        for value_node in document.value:
            reject_duplicate_yaml_keys(value_node)


def parse_yaml_block(block: str) -> dict[str, Any]:
    if not block.strip():
        return {}
    try:
        document = yaml.compose(block, Loader=yaml.SafeLoader)
        reject_duplicate_yaml_keys(document)
        value = yaml.safe_load(block)
    except yaml.YAMLError as error:
        raise FrontmatterError(f"invalid YAML frontmatter: {error}") from error
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise FrontmatterError("frontmatter must contain a YAML mapping")
    return value


def string_list(
    data: dict[str, Any],
    name: str,
    *,
    allow_empty_list: bool = True,
    reject_duplicates: bool = True,
) -> tuple[str, ...]:
    if name not in data:
        return ()
    value = data[name]
    if not isinstance(value, list):
        raise FrontmatterError(f"{name} must be a list of strings")
    if not allow_empty_list and not value:
        raise FrontmatterError(f"{name} must not be an empty list")
    if any(not isinstance(item, str) or not item for item in value):
        raise FrontmatterError(f"{name} must contain only nonempty strings")
    if reject_duplicates and len(set(value)) != len(value):
        raise FrontmatterError(f"{name} contains duplicate entries")
    return tuple(value)


def parse_negative(value: Any) -> dict[str, str] | None:
    if value is None:
        return None
    if not isinstance(value, dict):
        raise FrontmatterError("negative must be a mapping with phase and type")
    if set(value) != {"phase", "type"}:
        raise FrontmatterError("negative must contain exactly phase and type")
    phase, error_type = value["phase"], value["type"]
    if phase not in {"parse", "resolution", "runtime"}:
        raise FrontmatterError(f"invalid negative phase: {phase!r}")
    if not isinstance(error_type, str) or not error_type:
        raise FrontmatterError("negative type must be a nonempty error constructor name")
    return {"phase": phase, "type": error_type}


def parse_metadata(data: dict[str, Any], has_frontmatter: bool) -> Metadata:
    flags = string_list(data, "flags")
    known_flags = {
        "onlyStrict",
        "noStrict",
        "module",
        "raw",
        "async",
        "generated",
        "CanBlockIsFalse",
        "CanBlockIsTrue",
        "non-deterministic",
    }
    unknown = set(flags) - known_flags
    if unknown:
        raise FrontmatterError(f"unknown metadata flag: {sorted(unknown)[0]}")
    return Metadata(
        flags=flags,
        includes=string_list(data, "includes"),
        negative=parse_negative(data.get("negative")),
        features=string_list(data, "features"),
        locale=string_list(data, "locale", allow_empty_list=False),
        has_frontmatter=has_frontmatter,
        non_deterministic="non-deterministic" in flags,
    )


def read_source_metadata(path: Path) -> SourceMetadata:
    """Parse a file once, while preserving a separate copy of its original bytes."""
    try:
        content = path.read_bytes()
    except OSError as error:
        raise FrontmatterError(f"cannot read {path}: {error}") from error
    block, present = extract_frontmatter(content)
    try:
        parsed = parse_yaml_block(block) if present else {}
        return SourceMetadata(parse_metadata(parsed, present), content)
    except FrontmatterError:
        raise
    except (TypeError, ValueError) as error:
        raise FrontmatterError(f"invalid metadata in {path}: {error}") from error
