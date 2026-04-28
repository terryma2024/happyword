import routingFlowUiTest from './RoutingFlow.ui.test';
import critSpectacleUiTest from './CritSpectacle.ui.test';
import speakerButtonUiTest from './SpeakerButton.ui.test';
import reviewModeUiTest from './ReviewMode.ui.test';
import magicAttackUiTest from './MagicAttack.ui.test';
import v03AdventureUiTest from './V03Adventure.ui.test';
import homeToolbarLockedUiTest from './HomeToolbarLocked.ui.test';
import fillLetterFlowUiTest from './FillLetterFlow.ui.test';
import monsterCodexFlowUiTest from './MonsterCodexFlow.ui.test';

export default function testsuite() {
  // HomeToolbarLocked must run before any suite that seeds wrong
  // answers into LearningRecorder (ReviewMode / MagicAttack / V03 etc.)
  // — its lockedReviewShowsToastAndStays case asserts the toast is
  // surfaced when recentWrongCount < 3, which would silently flip to
  // navigation once the recorder has accrued ≥3 wrongs.
  homeToolbarLockedUiTest();
  // MonsterCodexFlow is order-independent: the codex page reads only
  // a frozen static array (MONSTER_CODEX) and does not touch the
  // recorder. Runs second to surface failures fast — codex regressions
  // shouldn't be hidden behind 6+ minutes of unrelated suites.
  monsterCodexFlowUiTest();
  routingFlowUiTest();
  critSpectacleUiTest();
  speakerButtonUiTest();
  reviewModeUiTest();
  magicAttackUiTest();
  v03AdventureUiTest();
  // FillLetterFlow taps correct answers driven by a static catalog
  // map (see the file's header comment) so it stays deterministic
  // even after earlier suites populated the LearningRecorder. Runs
  // last so any monster-defeated stat seeded here does not pollute
  // the assumptions the other suites bake in.
  fillLetterFlowUiTest();
}
