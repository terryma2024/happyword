from __future__ import annotations

from .models import Evidence, Gap, Platform


def find_stable_id_gaps(
    harmony_ids: set[str],
    harmony_test_refs: set[str],
    platform_ids: dict[Platform, set[str]],
    doc_clues: dict[str, str] | None = None,
) -> list[Gap]:
    gaps: list[Gap] = []
    doc_clues = doc_clues or {}
    ids_to_check = harmony_ids if not harmony_test_refs else harmony_ids & harmony_test_refs
    for platform, ids in platform_ids.items():
        for identifier in sorted(ids_to_check - ids):
            tested = identifier in harmony_test_refs
            clue_source, clue_detail = _split_doc_clue(doc_clues.get(identifier))
            gaps.append(
                Gap(
                    platform=platform,
                    kind="stable_id",
                    severity="P0" if tested else "P3",
                    title=f"{platform} is missing HarmonyOS stable ID {identifier}",
                    harmony_evidence=Evidence(
                        identifier=identifier,
                        source=clue_source or "HarmonyOS baseline",
                        detail=clue_detail or ("ID is referenced by HarmonyOS UI tests" if tested else "ID exists in HarmonyOS UI"),
                    ),
                    platform_evidence=Evidence(
                        identifier=identifier,
                        source=f"{platform} source",
                        detail="No matching automation identifier found",
                    ),
                    suggested_fix_entry=_stable_id_fix_entry(platform, identifier, has_doc_clue=identifier in doc_clues),
                ),
            )
    return gaps


def find_test_coverage_gaps(
    harmony_test_refs: set[str],
    platform_refs: dict[Platform, set[str]],
) -> list[Gap]:
    interesting_refs = {ref for ref in harmony_test_refs if ref.endswith(("Button", "Screen", "Page", "Flow"))}
    gaps: list[Gap] = []
    for platform, refs in platform_refs.items():
        missing = sorted(interesting_refs - refs)
        for identifier in missing:
            gaps.append(
                Gap(
                    platform=platform,
                    kind="test_coverage",
                    severity="P1",
                    title=f"{platform} tests do not reference HarmonyOS-tested surface {identifier}",
                    harmony_evidence=Evidence(identifier, "HarmonyOS tests", "Referenced by HarmonyOS test source"),
                    platform_evidence=Evidence(identifier, f"{platform} tests", "No matching test reference found"),
                    suggested_fix_entry=_test_fix_entry(platform),
                ),
            )
    return gaps


def find_behavior_gaps(
    harmony_ids: set[str],
    harmony_test_refs: set[str],
    platform_ids: dict[Platform, set[str]],
    platform_refs: dict[Platform, set[str]],
    doc_clues,
) -> list[Gap]:
    gaps: list[Gap] = []
    expected_behavior_ids = {
        identifier
        for identifier, clues in doc_clues.items()
        if any(clue.kind == "behavior" for clue in clues)
        and (identifier in harmony_ids or identifier in harmony_test_refs)
    }
    for platform, ids in platform_ids.items():
        refs = platform_refs.get(platform, set())
        for identifier in sorted(expected_behavior_ids):
            clue = _first_behavior_clue(doc_clues[identifier])
            source = f"{clue.path}:{clue.line}" if clue else "docs/superpowers"
            detail = clue.snippet if clue else "Expected behavior is documented"
            if identifier not in ids:
                gaps.append(
                    Gap(
                        platform=platform,
                        kind="behavior",
                        severity="P0",
                        title=f"{platform} has no counterpart for documented HarmonyOS behavior {identifier}",
                        harmony_evidence=Evidence(identifier, source, detail),
                        platform_evidence=Evidence(identifier, f"{platform} source", "No matching stable ID or behavior anchor found"),
                        suggested_fix_entry=_behavior_fix_entry(platform, identifier, missing_counterpart=True),
                    ),
                )
            elif identifier in harmony_test_refs and identifier not in refs:
                gaps.append(
                    Gap(
                        platform=platform,
                        kind="behavior",
                        severity="P1",
                        title=f"{platform} counterpart for {identifier} lacks behavior test coverage",
                        harmony_evidence=Evidence(identifier, source, detail),
                        platform_evidence=Evidence(identifier, f"{platform} tests", "Stable ID exists but no matching test reference was found"),
                        suggested_fix_entry=_behavior_fix_entry(platform, identifier, missing_counterpart=False),
                    ),
                )
    return gaps


def _stable_id_fix_entry(platform: Platform, identifier: str, has_doc_clue: bool = False) -> str:
    doc_hint = " Re-read the cited docs/superpowers spec/plan line first to preserve intended behavior." if has_doc_clue else ""
    if platform == "ios":
        return f"Search ios/WordMagicGame for the matching view and add .accessibilityIdentifier(\"{identifier}\").{doc_hint}"
    return f"Search android/app/src/main/java for the matching Compose node and add Modifier.testTag(\"{identifier}\").{doc_hint}"


def _test_fix_entry(platform: Platform) -> str:
    if platform == "ios":
        return "Add or update an XCUITest under ios/WordMagicGameUITests/."
    return "Add or update a Compose UI test under android/app/src/androidTest/."


def _behavior_fix_entry(platform: Platform, identifier: str, missing_counterpart: bool) -> str:
    if platform == "ios":
        target = "ios/WordMagicGame and ios/WordMagicGameUITests"
    else:
        target = "android/app/src/main/java and android/app/src/androidTest"
    action = "Add the missing platform surface and test the documented semantics" if missing_counterpart else "Add a platform test for the documented semantics"
    return f"{action} for {identifier}. Start in {target}, then re-read the cited spec/plan line before editing."


def _first_behavior_clue(clues):
    behavior_clues = [clue for clue in clues if clue.kind == "behavior"]
    if not behavior_clues:
        return None
    return sorted(behavior_clues, key=lambda clue: (clue.path, clue.line))[0]


def _split_doc_clue(clue: str | None) -> tuple[str | None, str | None]:
    if not clue:
        return None, None
    if ": " not in clue:
        return None, clue
    source, detail = clue.split(": ", 1)
    return source, detail
