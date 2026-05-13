from parity_audit.extractors import (
    extract_android_test_tags,
    extract_harmony_ids,
    extract_ios_accessibility_ids,
    extract_string_references,
)


def test_extracts_stable_ids_from_three_platforms() -> None:
    harmony = """
    Button('Start')
      .id('HomeStartButton')
    Text('Battle')
      .id("BattleTitle")
    """
    ios = """
    Button("开始冒险") {}
      .accessibilityIdentifier("HomeStartButton")
    Text("Battle")
      .accessibilityIdentifier("BattleTitle")
    """
    android = """
    Button(
      modifier = Modifier.testTag("HomeStartButton"),
      onClick = {}
    ) { Text("开始今日冒险") }
    Text("Battle", modifier = Modifier.testTag("BattleTitle"))
    """

    assert extract_harmony_ids(harmony) == {"HomeStartButton", "BattleTitle"}
    assert extract_ios_accessibility_ids(ios) == {"HomeStartButton", "BattleTitle"}
    assert extract_android_test_tags(android) == {"HomeStartButton", "BattleTitle"}


def test_extracts_test_references_from_string_literals() -> None:
    test_source = """
    await findComponent('HomeStartButton').click()
    XCTAssertTrue(app.buttons["BattleCorrectOption"].exists)
    composeRule.onNodeWithTag("BattleScreen").assertIsDisplayed()
    """

    references = extract_string_references(test_source)

    assert "HomeStartButton" in references
    assert "BattleCorrectOption" in references
    assert "BattleScreen" in references
