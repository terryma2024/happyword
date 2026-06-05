package cool.happyword.wordmagic.data

import cool.happyword.wordmagic.core.BuiltinPacks
import cool.happyword.wordmagic.core.BattleQuestionTypePolicy
import cool.happyword.wordmagic.core.CoinAccount
import cool.happyword.wordmagic.core.CoinTransaction
import cool.happyword.wordmagic.core.GameConfig
import cool.happyword.wordmagic.core.MonsterProgressRecord
import cool.happyword.wordmagic.core.MonsterProgressSnapshot
import cool.happyword.wordmagic.core.PackLibrary
import cool.happyword.wordmagic.core.PackSelectionStore
import cool.happyword.wordmagic.core.SpellbookRewardSnapshot
import org.junit.Assert.assertEquals
import org.junit.Test

class AndroidLocalProgressRepositoriesTest {
    private val library = PackLibrary.merge(BuiltinPacks.all, emptyList(), emptyList())

    @Test
    fun selectedPackIdPersistsAcrossRepositoryInstances() {
        val prefs = FakeSharedPreferences()
        val repository = AndroidLocalProgressRepositories(prefs)

        repository.saveSelectedPackId("school-castle")

        assertEquals("school-castle", AndroidLocalProgressRepositories(prefs).loadSelectedPackId())
    }

    @Test
    fun resolveSelectedPackIdKeepsPersistedActivePack() {
        val prefs = FakeSharedPreferences()
        val repository = AndroidLocalProgressRepositories(prefs)
        val selection = PackSelectionStore.initial(listOf("fruit-forest", "school-castle"))
        repository.saveSelectedPackId("school-castle")

        val resolved = repository.resolveSelectedPackId(selection, library)

        assertEquals("school-castle", resolved)
        assertEquals("school-castle", repository.loadSelectedPackId())
    }

    @Test
    fun resolveSelectedPackIdFallsBackToFirstActivePackAndSavesWhenPersistedPackIsInactive() {
        val prefs = FakeSharedPreferences()
        val repository = AndroidLocalProgressRepositories(prefs)
        val selection = PackSelectionStore.initial(listOf("fruit-forest", "school-castle"))
        repository.saveSelectedPackId("animal-safari")

        val resolved = repository.resolveSelectedPackId(selection, library)

        assertEquals("fruit-forest", resolved)
        assertEquals("fruit-forest", repository.loadSelectedPackId())
    }

    @Test
    fun spellbookRewardClaimsPersistAcrossRepositoryInstances() {
        val prefs = FakeSharedPreferences()
        val repository = AndroidLocalProgressRepositories(prefs)

        repository.saveSpellbookRewards(SpellbookRewardSnapshot(claimedPackIds = listOf("school-castle", "fruit-forest")))

        assertEquals(
            listOf("fruit-forest", "school-castle"),
            AndroidLocalProgressRepositories(prefs).loadSpellbookRewards().claimedPackIds,
        )
    }

    @Test
    fun monsterProgressPersistsAsSignedSnapshotKeyJson() {
        val prefs = FakeSharedPreferences()
        val repository = AndroidLocalProgressRepositories(prefs)
        val snapshot = MonsterProgressSnapshot(
            records = listOf(
                MonsterProgressRecord(
                    catalogIndex = 1,
                    encountered = true,
                    defeatCount = 100,
                    claimedMilestones = listOf(50),
                ),
            ),
        )

        repository.saveMonsterProgress(snapshot)

        val raw = prefs.getString("monster_progress/snapshot_v1", "")
        assertEquals(
            MonsterProgressSnapshot(
                records = listOf(
                    MonsterProgressRecord(
                        catalogIndex = 1,
                        encountered = true,
                        defeatCount = 100,
                        claimedMilestones = listOf(50),
                    ),
                ),
            ),
            AndroidLocalProgressRepositories(prefs).loadMonsterProgress(),
        )
        assertEquals(true, raw?.contains("\"version\":1"))
    }

    @Test
    fun coinAccountPersistsTransactionHistory() {
        val prefs = FakeSharedPreferences()
        val repository = AndroidLocalProgressRepositories(prefs)

        repository.saveCoinAccount(
            CoinAccount(
                balance = 50,
                earnedByDay = mapOf("2026-06-05" to 20),
                transactions = listOf(CoinTransaction("monster-codex:50:1", 50, 50)),
            ),
        )

        assertEquals(
            CoinAccount(
                balance = 50,
                earnedByDay = mapOf("2026-06-05" to 20),
                transactions = listOf(CoinTransaction("monster-codex:50:1", 50, 50)),
            ),
            AndroidLocalProgressRepositories(prefs).loadCoinAccount(),
        )
    }

    @Test
    fun gameConfigPersistsPcmAudioSwitchesAndQuestionTypeSelection() {
        val prefs = FakeSharedPreferences()
        val repository = AndroidLocalProgressRepositories(prefs)

        repository.saveGameConfig(
            GameConfig(
                autoPronunciation = false,
                playBgm = true,
                actionSfx = false,
                enabledQuestionTypes = listOf(BattleQuestionTypePolicy.SPELL),
            ),
        )

        val loaded = AndroidLocalProgressRepositories(prefs).loadGameConfig()
        assertEquals(false, loaded.autoPronunciation)
        assertEquals(true, loaded.playBgm)
        assertEquals(false, loaded.actionSfx)
        assertEquals(listOf(BattleQuestionTypePolicy.SPELL), loaded.enabledQuestionTypes)
    }
}
