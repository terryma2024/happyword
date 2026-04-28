import routingFlowUiTest from './RoutingFlow.ui.test';
import critSpectacleUiTest from './CritSpectacle.ui.test';
import speakerButtonUiTest from './SpeakerButton.ui.test';
import reviewModeUiTest from './ReviewMode.ui.test';
import magicAttackUiTest from './MagicAttack.ui.test';
import v03AdventureUiTest from './V03Adventure.ui.test';
import homeToolbarLockedUiTest from './HomeToolbarLocked.ui.test';

export default function testsuite() {
  // HomeToolbarLocked must run before any suite that seeds wrong
  // answers into LearningRecorder (ReviewMode / MagicAttack / V03 etc.)
  // — its lockedReviewShowsToastAndStays case asserts the toast is
  // surfaced when recentWrongCount < 3, which would silently flip to
  // navigation once the recorder has accrued ≥3 wrongs.
  homeToolbarLockedUiTest();
  routingFlowUiTest();
  critSpectacleUiTest();
  speakerButtonUiTest();
  reviewModeUiTest();
  magicAttackUiTest();
  v03AdventureUiTest();
}
