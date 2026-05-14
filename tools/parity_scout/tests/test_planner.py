import json

from parity_scout.planner import PlanResult, build_plan, render_tree
from parity_scout.registry import load_registry


def test_build_plan_marks_each_platform_status(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    plan = build_plan(
        reg,
        page_ids=["home", "battle"],
        run_id="r1",
        scope_kind="pages",
        scope_value="home,battle",
    )
    assert isinstance(plan, PlanResult)
    home = next(leaf for leaf in plan.leaves if leaf.page_id == "home")
    assert home.harmony["status"] == "ok"
    assert home.android["status"] == "feature_absent"
    battle = next(leaf for leaf in plan.leaves if leaf.page_id == "battle")
    assert battle.android["status"] == "ok"


def test_plan_serializes_to_json(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    plan = build_plan(
        reg,
        page_ids=["home"],
        run_id="r2",
        scope_kind="overall",
        scope_value=None,
    )
    blob = json.loads(plan.to_json())
    assert blob["run_id"] == "r2"
    assert blob["leaves"][0]["page_id"] == "home"


def test_render_tree_marks_blocked_and_feature_absent(fixtures_dir):
    reg = load_registry(fixtures_dir / "registry_minimal.yml")
    plan = build_plan(
        reg,
        page_ids=["home", "battle"],
        run_id="r3",
        scope_kind="overall",
        scope_value=None,
    )
    out = render_tree(plan)
    assert "home" in out
    assert "feature_absent" in out
    assert "battle" in out
    assert "ok" in out
