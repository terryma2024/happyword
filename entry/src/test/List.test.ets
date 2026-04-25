import localUnitTest from './LocalUnit.test';
import monsterCatalogTest from './MonsterCatalog.test';

export default function testsuite() {
  localUnitTest();
  monsterCatalogTest();
}