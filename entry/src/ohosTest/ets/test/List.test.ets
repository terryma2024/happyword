import routingFlowUiTest from './RoutingFlow.ui.test';
import critSpectacleUiTest from './CritSpectacle.ui.test';
import speakerButtonUiTest from './SpeakerButton.ui.test';
import reviewModeUiTest from './ReviewMode.ui.test';
import magicAttackUiTest from './MagicAttack.ui.test';
import v03AdventureUiTest from './V03Adventure.ui.test';

export default function testsuite() {
  routingFlowUiTest();
  critSpectacleUiTest();
  speakerButtonUiTest();
  reviewModeUiTest();
  magicAttackUiTest();
  v03AdventureUiTest();
}
