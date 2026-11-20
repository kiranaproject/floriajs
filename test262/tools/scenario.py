"""Pure Test262 metadata scenario planning; no JavaScript is executed here."""

from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
from typing import Any

from frontmatter import FrontmatterError, Metadata, read_source_metadata


class PlanningError(ValueError):
    """Scenario configuration or source/harness paths are invalid."""


def safe_relative(value: str) -> PurePosixPath:
    if not isinstance(value, str) or not value:
        raise PlanningError("source path must be a nonempty relative POSIX path")
    if "\x00" in value or "\\" in value:
        raise PlanningError(f"unsafe source path: {value!r}")
    if value.startswith("/") or (len(value) > 1 and value[1] == ":"):
        raise PlanningError(f"absolute or drive-qualified path is not allowed: {value!r}")
    parts = value.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise PlanningError(f"path traversal or empty component: {value!r}")
    return PurePosixPath(value)


def contained_file(root: Path, relative: PurePosixPath, label: str) -> Path:
    canonical_root = root.resolve()
    try:
        candidate = (canonical_root / relative).resolve(strict=True)
    except OSError as error:
        raise PlanningError(f"cannot resolve {label} {relative}: {error}") from error
    try:
        candidate.relative_to(canonical_root)
    except ValueError as error:
        raise PlanningError(f"{label} escapes its root: {relative}") from error
    if not candidate.is_file():
        raise PlanningError(f"{label} is not a regular file: {candidate}")
    if candidate.suffix != ".js":
        raise PlanningError(f"{label} must have a .js suffix: {candidate}")
    return candidate


def validate_checkout(root: Path, expected_revision: str, allow_unpinned: bool) -> dict[str, Any]:
    """Verify the root without any clone/fetch/reset/config operation."""
    root = root.resolve()
    if not root.is_dir():
        raise PlanningError(f"Test262 root is not a directory: {root}")
    if not (root / "test").is_dir() or not (root / "harness").is_dir():
        raise PlanningError(f"root must contain test/ and harness/: {root}")
    if allow_unpinned:
        return {
            "root": str(root),
            "expectedRevision": expected_revision,
            "actualRevision": None,
            "packageVersion": None,
            "revisionVerified": False,
        }

    env = dict(os.environ)
    env["GIT_OPTIONAL_LOCKS"] = "0"

    def git(*arguments: str) -> subprocess.CompletedProcess[str]:
        try:
            return subprocess.run(
                ["git", "--no-optional-locks", "-C", str(root), *arguments],
                capture_output=True,
                text=True,
                encoding="utf-8",
                timeout=5,
                check=False,
                env=env,
            )
        except (OSError, subprocess.SubprocessError) as error:
            raise PlanningError(f"cannot inspect Test262 revision: {error}") from error

    commit = git("rev-parse", "--verify", "HEAD^{commit}")
    actual = commit.stdout.strip()
    if commit.returncode != 0 or actual != expected_revision:
        raise PlanningError(
            "Test262 revision mismatch: expected "
            f"{expected_revision}, got {actual or commit.stderr.strip() or 'unavailable'}. "
            "Use --allow-unpinned only for authored fixture roots, not official results."
        )

    top = git("rev-parse", "--show-toplevel")
    if top.returncode != 0 or Path(top.stdout.strip()).resolve() != root:
        raise PlanningError("Test262 root is not the repository's top-level directory")

    dirty = git("diff", "--no-ext-diff", "--quiet", "--", "test", "harness", "package.json")
    if dirty.returncode != 0:
        raise PlanningError("Test262 test/harness/package.json content differs from the pinned commit")

    try:
        package = json.loads((root / "package.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PlanningError(f"cannot read Test262 package.json: {error}") from error
    version = package.get("version")
    if version != "5.0.0":
        raise PlanningError(f"unexpected Test262 package version: {version!r}")

    return {
        "root": str(root),
        "expectedRevision": expected_revision,
        "actualRevision": actual,
        "packageVersion": version,
        "revisionVerified": True,
    }


@dataclass(frozen=True)
class ScenarioPlanner:
    upstream: dict[str, Any]
    policy: dict[str, Any]
    host: Path

    @property
    def root(self) -> Path:
        return Path(self.upstream["root"])

    def base(self, relative: str, variant: str, metadata: Metadata | None = None) -> dict[str, Any]:
        metadata = metadata or Metadata()
        return {
            "schemaVersion": 1,
            "preparationOnly": True,
            "policyName": self.policy["policyName"],
            "upstream": self.upstream,
            "testPath": relative,
            "variant": variant,
            "scenarioId": f"{relative}::{variant}" if variant else relative,
            "outcome": "planned",
            "reason": "",
            "source": {"name": "", "bytes": 0, "sha256": ""},
            "metadata": {
                "flags": list(metadata.flags),
                "includes": list(metadata.includes),
                "negative": dict(metadata.negative) if metadata.negative else None,
                "features": list(metadata.features),
                "locale": list(metadata.locale),
                "nonDeterministic": metadata.non_deterministic,
                "hasFrontmatter": metadata.has_frontmatter,
            },
            "harness": [],
            "hostCommand": [],
        }

    def excluded(self, relative: str, variant: str, outcome: str, reason: str,
                 metadata: Metadata | None = None, content: bytes = b"",
                 source_name: str = "") -> dict[str, Any]:
        result = self.base(relative, variant, metadata)
        result["outcome"] = outcome
        result["reason"] = reason
        if content or source_name:
            result["source"] = {
                "name": source_name,
                "bytes": len(content),
                "sha256": sha256(content).hexdigest(),
            }
        return result

    def error(self, relative: str, error: Exception) -> dict[str, Any]:
        return self.excluded(relative, "", "harness-error", str(error))

    def variants(self, metadata: Metadata) -> list[str]:
        flags = set(metadata.flags)
        if "raw" in flags:
            return ["raw"]
        if "module" in flags:
            return ["module"]
        if "onlyStrict" in flags:
            return ["strict"]
        if "noStrict" in flags:
            return ["non-strict"]
        return ["non-strict", "strict"]

    def harness_names(self, metadata: Metadata) -> list[str]:
        if "async" in metadata.flags:
            return list(self.policy["scenarios"]["async"]["harness"])
        return list(self.policy["scenarios"]["default"]["harness"])

    def validate_flags(self, metadata: Metadata) -> None:
        flags = set(metadata.flags)
        conflicts = (
            ("onlyStrict", "noStrict"),
            ("raw", "onlyStrict"),
            ("raw", "noStrict"),
            ("raw", "module"),
            ("module", "onlyStrict"),
            ("module", "noStrict"),
            ("CanBlockIsFalse", "CanBlockIsTrue"),
        )
        for left, right in conflicts:
            if left in flags and right in flags:
                raise PlanningError(f"incompatible metadata flags: {left} + {right}")

    def prepare(self, relative: str) -> list[dict[str, Any]]:
        try:
            relative_path = safe_relative(relative)
            relative_posix = relative_path.as_posix()
            if "_FIXTURE" in relative_path.name:
                return [self.excluded(
                    relative_posix, "", "skipped",
                    "fixture files are module inputs, not standalone tests"
                )]
            return self.prepare_valid_path(relative_posix)
        except (FrontmatterError, PlanningError, OSError) as error:
            return [self.error(relative, error)]

    def prepare_valid_path(self, relative: str) -> list[dict[str, Any]]:
        test_file = contained_file(self.root / "test", PurePosixPath(relative), "test source")
        source = read_source_metadata(test_file)
        metadata = source.metadata
        self.validate_flags(metadata)
        variants = self.variants(metadata)

        # A strict skip is an explicit scenario even when a non-strict variant
        # has an independent unsupported capability.
        unsupported_reason = ""
        unsupported_outcome = "unsupported"
        if relative.startswith(("intl402/", "staging/intl402/")):
            unsupported_reason = "ECMA-402 internationalization is not implemented"
            unsupported_outcome = "skipped"
        elif "raw" in metadata.flags and "async" in metadata.flags:
            unsupported_reason = "raw scenarios cannot provide the async completion contract"
        elif {"CanBlockIsFalse", "CanBlockIsTrue"} & set(metadata.flags):
            unsupported_reason = "agent/CanBlock execution is not supported"
            unsupported_outcome = "skipped"
        elif metadata.negative and metadata.negative["phase"] == "resolution":
            unsupported_reason = self.policy.get("negativeVerdicts", {}).get(
                "resolutionReason",
                "negative resolution expectations require module support",
            )

        if not unsupported_reason:
            policy_tags = set(self.policy["skipRules"]["unsupportedFeatureTags"])
            unsupported_features = sorted(policy_tags & set(metadata.features))
            if unsupported_features:
                unsupported_reason = f"unsupported feature: {unsupported_features[0]}"

        if not unsupported_reason:
            source_text = source.content.decode("utf-8")
            for member in self.policy["skipRules"].get("unsupportedHostMembers", []):
                if member in source_text:
                    unsupported_reason = f"unsupported host member: {member}"
                    break

        raw = "raw" in metadata.flags
        if not unsupported_reason and not raw:
            includes = self.harness_names(metadata) + list(metadata.includes)
            unsupported_includes = set(self.policy["harness"]["unsupportedIncludes"])
            for include in includes:
                if include in unsupported_includes:
                    unsupported_reason = f"unsupported harness include: {include}"
                    break

        results: list[dict[str, Any]] = []
        for variant in variants:
            if unsupported_reason:
                results.append(self.excluded(
                    relative, variant, unsupported_outcome, unsupported_reason,
                    metadata, source.content, str(test_file)
                ))
            else:
                results.append(self.executable_plan(
                    relative, variant, metadata, source.content, test_file
                ))
        return results

    def executable_plan(self, relative: str, variant: str, metadata: Metadata,
                        content: bytes, test_file: Path) -> dict[str, Any]:
        result = self.base(relative, variant, metadata)
        result["source"] = {
            "name": str(test_file),
            "bytes": len(content),
            "sha256": sha256(content).hexdigest(),
        }
        harness: list[Path] = []
        if variant != "raw":
            ordered = self.harness_names(metadata) + list(metadata.includes)
            for include in ordered:
                harness.append(contained_file(
                    self.root / "harness", safe_relative(include), "harness include"
                ))

        command = [
            str(self.host),
            "--scenario-id", result["scenarioId"],
            "--variant", "strict" if variant == "module" else variant,
        ]
        if variant in ("strict", "module"):
            command.append("--strict")
        if "async" in metadata.flags:
            command.append("--async")
        for include in harness:
            command.extend(("--harness", str(include)))
        command.extend(("--test", str(test_file)))
        if variant == "module":
            command.extend(("--module", "--module-root", str(self.root / "test")))
        result["harness"] = [str(item) for item in harness]
        result["hostCommand"] = command
        return result
