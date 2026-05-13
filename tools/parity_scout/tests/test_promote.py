import datetime as dt

import pytest

from parity_scout.promote import PromoteError, promote_curated_findings


def test_promote_appends_to_existing_followups(tmp_path, fixtures_dir):
    feature_dir = tmp_path / "docs" / "features" / "2026-04-29-wishlist"
    feature_dir.mkdir(parents=True)
    followups = feature_dir / "60-followups.md"
    followups.write_text("# Followups\n\nPrior section.\n", encoding="utf-8")

    findings = fixtures_dir / "findings_curated_one_feature.md"
    promote_curated_findings(
        findings=findings,
        feature_dir=feature_dir,
        run_id="r1",
        baseline_line="harmonyos main @ deadbee (clean)",
        scope_line="spec:wishlist-design.md",
        leaves_line="wishlist, gift-box-modal",
        today=dt.date(2026, 5, 13),
    )
    text = followups.read_text(encoding="utf-8")
    assert "## Parity scout — 2026-05-13 (run r1)" in text
    assert "wishlist (iOS)" in text
    assert "gift-box-modal (Android)" in text
    assert text.startswith("# Followups")


def test_promote_refuses_when_feature_folder_missing(tmp_path, fixtures_dir):
    findings = fixtures_dir / "findings_curated_one_feature.md"
    with pytest.raises(PromoteError, match="missing"):
        promote_curated_findings(
            findings=findings,
            feature_dir=tmp_path / "does-not-exist",
            run_id="r1",
            baseline_line="x",
            scope_line="x",
            leaves_line="x",
            today=dt.date(2026, 5, 13),
        )


def test_promote_creates_followups_when_absent(tmp_path, fixtures_dir):
    feature_dir = tmp_path / "docs" / "features" / "2026-04-29-wishlist"
    feature_dir.mkdir(parents=True)
    findings = fixtures_dir / "findings_curated_one_feature.md"
    out = promote_curated_findings(
        findings=findings,
        feature_dir=feature_dir,
        run_id="r1",
        baseline_line="harmonyos main @ deadbee (clean)",
        scope_line="overall:-",
        leaves_line="wishlist",
        today=dt.date(2026, 5, 13),
    )
    text = out.read_text(encoding="utf-8")
    assert text.startswith("# Followups")
    assert "Parity scout — 2026-05-13" in text
