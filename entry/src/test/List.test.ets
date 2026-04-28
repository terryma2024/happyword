import localUnitTest from './LocalUnit.test';
import monsterCatalogTest from './MonsterCatalog.test';
import questionTest from './Question.test';
import fillLetterGeneratorTest from './FillLetterGenerator.test';

export default function testsuite() {
  localUnitTest();
  monsterCatalogTest();
  questionTest();
  fillLetterGeneratorTest();
}
