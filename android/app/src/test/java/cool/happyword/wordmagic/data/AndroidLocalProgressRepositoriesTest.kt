package cool.happyword.wordmagic.data

import cool.happyword.wordmagic.core.BuiltinPacks
import cool.happyword.wordmagic.core.BattleQuestionTypePolicy
import cool.happyword.wordmagic.core.GameConfig
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
