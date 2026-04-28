import localUnitTest from './LocalUnit.test';
import monsterCatalogTest from './MonsterCatalog.test';
import questionTest from './Question.test';
import fillLetterGeneratorTest from './FillLetterGenerator.test';
import memorySchedulerTest from './MemoryScheduler.test';
import adventureCatalogTest from './AdventureCatalog.test';
import todayAdventureBuilderTest from './TodayAdventureBuilder.test';

export default function testsuite() {
  localUnitTest();
  monsterCatalogTest();
  questionTest();
  fillLetterGeneratorTest();
  memorySchedulerTest();
  adventureCatalogTest();
  todayAdventureBuilderTest();
}
