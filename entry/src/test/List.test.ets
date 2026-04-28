import localUnitTest from './LocalUnit.test';
import monsterCatalogTest from './MonsterCatalog.test';
import questionTest from './Question.test';
import fillLetterGeneratorTest from './FillLetterGenerator.test';
import memorySchedulerTest from './MemoryScheduler.test';
import adventureCatalogTest from './AdventureCatalog.test';
import todayAdventureBuilderTest from './TodayAdventureBuilder.test';
import planQuestionSourceTest from './PlanQuestionSource.test';
import coinAccountTest from './CoinAccount.test';
import wishlistStoreTest from './WishlistStore.test';
import todayPreferencesTest from './TodayPreferences.test';
import characterAssetsTests from './CharacterAssets.test';
import monsterCodexTests from './MonsterCodex.test';

export default function testsuite() {
  localUnitTest();
  monsterCatalogTest();
  questionTest();
  fillLetterGeneratorTest();
  memorySchedulerTest();
  adventureCatalogTest();
  todayAdventureBuilderTest();
  planQuestionSourceTest();
  coinAccountTest();
  wishlistStoreTest();
  todayPreferencesTest();
  characterAssetsTests();
  monsterCodexTests();
}
