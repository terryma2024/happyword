# Android Replica Phase 2 Local Growth And Pack Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect the current Android Phase 1 Home, Battle, and Result flow to an offline pack, coin, wishlist, redemption, monster codex, today plan, and pack-keyed learning report loop.

**Architecture:** Keep the Android client native Kotlin and Jetpack Compose. Move game rules and local persistence out of `MainActivity.kt` into pure `core` services and small Android `data` repositories, then wire screens through one app state holder so Home, Battle, Result, TodayPlan, and LearningReport all share the same active pack identity and local progress snapshot.

**Tech Stack:** Kotlin, Jetpack Compose Material3, Android `SharedPreferences` plus app-private JSON files, JUnit4 JVM tests, Compose UI tests, Android Studio emulator screenshots.

---

## Scope Boundary

Phase 2 is an offline-first Android phase. It does not add authenticated parent cloud binding, real remote pack sync, payments, release signing, or Cocos battle rendering. Fixture-backed global/family packs are acceptable because Phase 3 owns cloud binding and authenticated sync.

The source design is `docs/superpowers/specs/2026-05-11-android-replica-phase2-local-growth-pack-design.md`. The current Android code is a Phase 1 Compose prototype with most UI and route state in `android/app/src/main/java/cool/happyword/wordmagic/MainActivity.kt`. This plan intentionally extracts the data loop before adding more screens.

## Verification Commands

Use these commands throughout the plan:

```bash
cd android && ./gradlew testDebugUnitTest
cd android && ./gradlew assembleDebug
cd android && ./gradlew connectedDebugAndroidTest
cd android && ./gradlew installDebug
```

For UI-visible tasks, capture emulator screenshots after install:

```bash
adb exec-out screencap -p > ../assets/screenshots/android/phase2-<screen>.png
```

Compare each Android screenshot with the HarmonyOS reference named in the Phase 2 spec before considering the task complete.

## File Structure

Create and modify these files:

| File | Action | Responsibility |
| --- | --- | --- |
| `android/app/src/main/java/cool/happyword/wordmagic/core/PackModels.kt` | Create | Pack source, scene metadata, pack identity, builtin pack fixtures |
| `android/app/src/main/java/cool/happyword/wordmagic/core/PackLibrary.kt` | Create | Three-layer merge, scene fallback, source priority, active lookups |
| `android/app/src/main/java/cool/happyword/wordmagic/core/PackSelectionStore.kt` | Create | Active max-five rule, pin subset, perfect-run auto rotation |
| `android/app/src/main/java/cool/happyword/wordmagic/core/LearningRecorder.kt` | Create | Local answer/session events keyed by pack id and word id |
| `android/app/src/main/java/cool/happyword/wordmagic/core/LearningReportBuilder.kt` | Create | Pack-keyed report rows and deduped totals |
| `android/app/src/main/java/cool/happyword/wordmagic/core/TodayPlanService.kt` | Create | Read-only review/learning/new buckets from active packs and stats |
| `android/app/src/main/java/cool/happyword/wordmagic/core/GrowthModels.kt` | Create | Coin account, wishlist, redemption history, monster catalog rules |
| `android/app/src/main/java/cool/happyword/wordmagic/data/LocalJsonStore.kt` | Create | Tiny JSON file store wrapper for app-private persistence |
| `android/app/src/main/java/cool/happyword/wordmagic/data/AndroidPhase2Repositories.kt` | Create | SharedPreferences/JSON-backed repositories for selection, stats, coins, wishlist, history |
| `android/app/src/main/java/cool/happyword/wordmagic/ui/Phase2Screens.kt` | Create | PackManager, Wishlist, RedemptionHistory, MonsterCodex, TodayPlan, LearningReport composables |
| `android/app/src/main/java/cool/happyword/wordmagic/MainActivity.kt` | Modify | Route new screens, initialize local repositories, start battle with selected pack words, persist results |
| `android/app/src/test/java/cool/happyword/wordmagic/core/PackLibraryTest.kt` | Create | Merge priority and scene fallback tests |
| `android/app/src/test/java/cool/happyword/wordmagic/core/PackSelectionStoreTest.kt` | Create | Active/pin/rotation tests |
| `android/app/src/test/java/cool/happyword/wordmagic/core/LearningRecorderTest.kt` | Create | Session and answer recording tests |
| `android/app/src/test/java/cool/happyword/wordmagic/core/LearningReportBuilderTest.kt` | Create | Pack-keyed rows and deduped totals tests |
| `android/app/src/test/java/cool/happyword/wordmagic/core/TodayPlanServiceTest.kt` | Create | Deterministic bucket tests |
| `android/app/src/test/java/cool/happyword/wordmagic/core/GrowthStoresTest.kt` | Create | Coin, wishlist, redemption, monster catalog tests |
| `android/app/src/androidTest/java/cool/happyword/wordmagic/Phase2FlowTest.kt` | Create | Compose navigation and local mutation smoke tests |
| `android/app/src/androidTest/java/cool/happyword/wordmagic/SmokeTest.kt` | Modify | Keep Phase 1 coverage stable after route changes |
| `.cursor/android-dev-commands.md` | Modify | Add Phase 2 screenshot/test commands if missing |
| `docs/android-replica/00-index.md` | Modify | Link this Phase 2 plan |

## Task 1: Pack Domain Models And Builtin Catalog

**Files:**
- Create: `android/app/src/main/java/cool/happyword/wordmagic/core/PackModels.kt`
- Test: `android/app/src/test/java/cool/happyword/wordmagic/core/PackModelsTest.kt`

- [ ] **Step 1: Write the failing test**

```kotlin
package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PackModelsTest {
    @Test
    fun builtinCatalogContainsFiveHarmonyAlignedPacks() {
        val packs = BuiltinPacks.all

        assertEquals(
            listOf("fruit-forest", "school-castle", "home-cottage", "animal-safari", "ocean-realm"),
            packs.map { it.id },
        )
        assertEquals(PackSource.Builtin, packs.first().source)
        assertEquals("Fruit Forest", packs.first().nameEn)
        assertEquals("水果森林", packs.first().nameZh)
        assertTrue(packs.first().words.any { it.word == "apple" && it.meaning == "苹果" })
        assertTrue(packs.all { it.scene.monsterPlan.isNotEmpty() })
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd android && ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.core.PackModelsTest
```

Expected: fail because `BuiltinPacks`, `WordPack`, `PackSource`, and `SceneMetadata` do not exist.

- [ ] **Step 3: Add the pack models and builtin catalog**

Create `android/app/src/main/java/cool/happyword/wordmagic/core/PackModels.kt`:

```kotlin
package cool.happyword.wordmagic.core

enum class PackSource {
    Builtin,
    Global,
    Family,
}

data class SceneMetadata(
    val bgPrimary: String,
    val bgAccent: String,
    val bossName: String,
    val monsterPlan: List<String>,
    val bossCandidates: List<String>,
    val storyZh: String,
)

data class WordPack(
    val id: String,
    val nameEn: String,
    val nameZh: String,
    val source: PackSource,
    val version: Int,
    val publishedAtMs: Long?,
    val scene: SceneMetadata,
    val words: List<WordEntry>,
) {
    init {
        require(id.isNotBlank()) { "pack id is required" }
        require(nameEn.isNotBlank()) { "English pack name is required" }
        require(nameZh.isNotBlank()) { "Chinese pack name is required" }
        require(version >= 1) { "pack version must be positive" }
        require(words.isNotEmpty()) { "pack must include words" }
    }
}

object BuiltinPacks {
    val all: List<WordPack> = listOf(
        pack(
            id = "fruit-forest",
            nameEn = "Fruit Forest",
            nameZh = "水果森林",
            storyZh = "藤蔓和果香里的第一场魔法单词冒险。",
            monsterPlan = listOf("slime", "slime", "zombie", "dragon", "boss-fruit"),
            words = listOf(
                WordEntry("fruit-apple", "apple", "苹果"),
                WordEntry("fruit-banana", "banana", "香蕉"),
                WordEntry("fruit-pear", "pear", "梨"),
                WordEntry("fruit-orange", "orange", "橙子"),
                WordEntry("fruit-grape", "grape", "葡萄"),
            ),
        ),
        pack(
            id = "school-castle",
            nameEn = "School Castle",
            nameZh = "校园城堡",
            storyZh = "在书本城堡里挑战会拼写的怪物。",
            monsterPlan = listOf("zombie", "slime", "zombie", "dragon", "boss-school"),
            words = listOf(
                WordEntry("school-book", "book", "书"),
                WordEntry("school-pencil", "pencil", "铅笔"),
                WordEntry("school-desk", "desk", "课桌"),
                WordEntry("school-teacher", "teacher", "老师"),
                WordEntry("school-bag", "bag", "书包"),
            ),
        ),
        pack(
            id = "home-cottage",
            nameEn = "Home Cottage",
            nameZh = "家庭小屋",
            storyZh = "把熟悉的家庭物品变成轻松复习。",
            monsterPlan = listOf("dragon", "slime", "zombie", "dragon", "boss-home"),
            words = listOf(
                WordEntry("home-chair", "chair", "椅子"),
                WordEntry("home-table", "table", "桌子"),
                WordEntry("home-door", "door", "门"),
                WordEntry("home-bed", "bed", "床"),
                WordEntry("home-lamp", "lamp", "台灯"),
            ),
        ),
        pack(
            id = "animal-safari",
            nameEn = "Animal Safari",
            nameZh = "动物远征",
            storyZh = "跟动物朋友一起找回单词记忆。",
            monsterPlan = listOf("slime", "dragon", "zombie", "dragon", "boss-animal"),
            words = listOf(
                WordEntry("animal-cat", "cat", "猫"),
                WordEntry("animal-dog", "dog", "狗"),
                WordEntry("animal-bird", "bird", "鸟"),
                WordEntry("animal-fish", "fish", "鱼"),
                WordEntry("animal-lion", "lion", "狮子"),
            ),
        ),
        pack(
            id = "ocean-realm",
            nameEn = "Ocean Realm",
            nameZh = "海洋王国",
            storyZh = "在蓝色海底完成今日练习。",
            monsterPlan = listOf("slime", "zombie", "dragon", "slime", "boss-ocean"),
            words = listOf(
                WordEntry("ocean-sea", "sea", "海洋"),
                WordEntry("ocean-ship", "ship", "船"),
                WordEntry("ocean-shell", "shell", "贝壳"),
                WordEntry("ocean-wave", "wave", "海浪"),
                WordEntry("ocean-star", "star", "海星"),
            ),
        ),
    )

    val defaultActiveOrder: List<String> = listOf(
        "school-castle",
        "ocean-realm",
        "home-cottage",
        "fruit-forest",
        "animal-safari",
    )

    private fun pack(
        id: String,
        nameEn: String,
        nameZh: String,
        storyZh: String,
        monsterPlan: List<String>,
        words: List<WordEntry>,
    ): WordPack {
        return WordPack(
            id = id,
            nameEn = nameEn,
            nameZh = nameZh,
            source = PackSource.Builtin,
            version = 1,
            publishedAtMs = null,
            scene = SceneMetadata(
                bgPrimary = "#FFF7E6",
                bgAccent = "#FFD2A6",
                bossName = "$nameEn Boss",
                monsterPlan = monsterPlan,
                bossCandidates = monsterPlan.takeLast(1),
                storyZh = storyZh,
            ),
            words = words,
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
cd android && ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.core.PackModelsTest
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/cool/happyword/wordmagic/core/PackModels.kt android/app/src/test/java/cool/happyword/wordmagic/core/PackModelsTest.kt
git commit -m "feat(android): add phase2 pack domain fixtures"
```

## Task 2: Pack Library Merge Rules

**Files:**
- Create: `android/app/src/main/java/cool/happyword/wordmagic/core/PackLibrary.kt`
- Test: `android/app/src/test/java/cool/happyword/wordmagic/core/PackLibraryTest.kt`

- [ ] **Step 1: Write the failing test**

```kotlin
package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PackLibraryTest {
    @Test
    fun mergePriorityUsesFamilyThenGlobalThenBuiltinAndKeepsBuiltinSceneFallback() {
        val builtin = BuiltinPacks.all.first { it.id == "fruit-forest" }
        val global = builtin.copy(
            nameEn = "Global Fruit",
            source = PackSource.Global,
            version = 2,
            publishedAtMs = 2_000L,
            words = listOf(WordEntry("global-apple", "apple", "苹果")),
        )
        val family = builtin.copy(
            nameEn = "Family Fruit",
            source = PackSource.Family,
            version = 3,
            publishedAtMs = 3_000L,
            words = listOf(WordEntry("family-mango", "mango", "芒果")),
        )

        val library = PackLibrary.merge(
            builtin = listOf(builtin),
            global = listOf(global),
            family = listOf(family),
        )

        val merged = library.requirePack("fruit-forest")
        assertEquals("Family Fruit", merged.nameEn)
        assertEquals(PackSource.Family, merged.source)
        assertEquals(builtin.scene.storyZh, merged.scene.storyZh)
        assertEquals(listOf("mango"), merged.words.map { it.word })
    }

    @Test
    fun missingActiveIdsArePrunedInOrder() {
        val library = PackLibrary.merge(BuiltinPacks.all, emptyList(), emptyList())

        assertEquals(
            listOf("school-castle", "fruit-forest"),
            library.existingIdsInOrder(listOf("missing", "school-castle", "fruit-forest", "missing")),
        )
        assertTrue(library.allPacks().size >= 5)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd android && ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.core.PackLibraryTest
```

Expected: fail because `PackLibrary` does not exist.

- [ ] **Step 3: Add the library implementation**

Create `android/app/src/main/java/cool/happyword/wordmagic/core/PackLibrary.kt`:

```kotlin
package cool.happyword.wordmagic.core

class PackLibrary private constructor(
    private val packsById: Map<String, WordPack>,
) {
    fun allPacks(): List<WordPack> = packsById.values.sortedWith(compareBy<WordPack> { it.source.ordinal }.thenBy { it.id })

    fun requirePack(id: String): WordPack = packsById[id] ?: error("Unknown pack id: $id")

    fun findPack(id: String): WordPack? = packsById[id]

    fun existingIdsInOrder(ids: List<String>): List<String> {
        val seen = linkedSetOf<String>()
        ids.forEach { id ->
            if (packsById.containsKey(id)) {
                seen += id
            }
        }
        return seen.toList()
    }

    fun activePacks(activeIds: List<String>): List<WordPack> = existingIdsInOrder(activeIds).map(::requirePack)

    fun inactivePacks(activeIds: List<String>): List<WordPack> {
        val active = activeIds.toSet()
        return allPacks().filterNot { it.id in active }
    }

    companion object {
        fun merge(
            builtin: List<WordPack>,
            global: List<WordPack>,
            family: List<WordPack>,
        ): PackLibrary {
            val builtinScenes = builtin.associate { it.id to it.scene }
            val merged = linkedMapOf<String, WordPack>()
            builtin.forEach { merged[it.id] = it }
            global.forEach { pack ->
                merged[pack.id] = pack.copy(scene = builtinScenes[pack.id] ?: pack.scene)
            }
            family.forEach { pack ->
                merged[pack.id] = pack.copy(scene = builtinScenes[pack.id] ?: pack.scene)
            }
            return PackLibrary(merged)
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd android && ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.core.PackLibraryTest
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/cool/happyword/wordmagic/core/PackLibrary.kt android/app/src/test/java/cool/happyword/wordmagic/core/PackLibraryTest.kt
git commit -m "feat(android): add pack library merge rules"
```

## Task 3: Pack Selection, Pinning, And Perfect Rotation

**Files:**
- Create: `android/app/src/main/java/cool/happyword/wordmagic/core/PackSelectionStore.kt`
- Test: `android/app/src/test/java/cool/happyword/wordmagic/core/PackSelectionStoreTest.kt`

- [ ] **Step 1: Write the failing test**

```kotlin
package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PackSelectionStoreTest {
    @Test
    fun defaultsUseFiveBuiltinIdsAndRejectSixthActivePack() {
        val store = PackSelectionStore.initial(BuiltinPacks.defaultActiveOrder)

        assertEquals(5, store.activePackIds.size)
        assertFalse(store.activate("extra-pack").accepted)
        assertEquals("最多只能同时启用 5 个词包", store.activate("extra-pack").message)
    }

    @Test
    fun deactivatingPinnedPackClearsPin() {
        val store = PackSelectionStore.initial(BuiltinPacks.defaultActiveOrder)
            .togglePin("fruit-forest")
            .selection
            .deactivate("fruit-forest")
            .selection

        assertFalse("fruit-forest" in store.pinnedPackIds)
        assertFalse("fruit-forest" in store.activePackIds)
    }

    @Test
    fun threePerfectRunsRotateUnpinnedPackToBestCandidate() {
        val store = PackSelectionStore.initial(BuiltinPacks.defaultActiveOrder)
        val candidate = WordPack(
            id = "family-space",
            nameEn = "Family Space",
            nameZh = "家庭太空",
            source = PackSource.Family,
            version = 1,
            publishedAtMs = 9_000L,
            scene = BuiltinPacks.all.first().scene,
            words = listOf(WordEntry("space-moon", "moon", "月亮")),
        )
        val library = PackLibrary.merge(BuiltinPacks.all, emptyList(), listOf(candidate))

        val rotated = store
            .recordPerfectRun("fruit-forest", library).selection
            .recordPerfectRun("fruit-forest", library).selection
            .recordPerfectRun("fruit-forest", library).selection

        assertFalse("fruit-forest" in rotated.activePackIds)
        assertTrue("family-space" in rotated.activePackIds)
        assertEquals(5, rotated.activePackIds.size)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd android && ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.core.PackSelectionStoreTest
```

Expected: fail because `PackSelectionStore` does not exist.

- [ ] **Step 3: Add selection implementation**

Create `android/app/src/main/java/cool/happyword/wordmagic/core/PackSelectionStore.kt`:

```kotlin
package cool.happyword.wordmagic.core

data class PackSelectionMutation(
    val selection: PackSelectionStore,
    val accepted: Boolean,
    val message: String = "",
)

data class PackSelectionStore(
    val activePackIds: List<String>,
    val pinnedPackIds: Set<String>,
    val perfectScoresByPack: Map<String, Int>,
    val lastSelectionUpdatedAtMs: Long,
) {
    fun activate(packId: String, nowMs: Long = System.currentTimeMillis()): PackSelectionMutation {
        if (packId in activePackIds) return PackSelectionMutation(this, true)
        if (activePackIds.size >= MAX_ACTIVE) {
            return PackSelectionMutation(this, false, "最多只能同时启用 5 个词包")
        }
        return PackSelectionMutation(copy(activePackIds = activePackIds + packId, lastSelectionUpdatedAtMs = nowMs), true)
    }

    fun deactivate(packId: String, nowMs: Long = System.currentTimeMillis()): PackSelectionMutation {
        return PackSelectionMutation(
            copy(
                activePackIds = activePackIds.filterNot { it == packId },
                pinnedPackIds = pinnedPackIds - packId,
                lastSelectionUpdatedAtMs = nowMs,
            ),
            true,
        )
    }

    fun togglePin(packId: String, nowMs: Long = System.currentTimeMillis()): PackSelectionMutation {
        if (packId !in activePackIds) return PackSelectionMutation(this, false, "只能固定已启用的词包")
        val nextPins = if (packId in pinnedPackIds) pinnedPackIds - packId else pinnedPackIds + packId
        return PackSelectionMutation(copy(pinnedPackIds = nextPins, lastSelectionUpdatedAtMs = nowMs), true)
    }

    fun prune(library: PackLibrary, nowMs: Long = System.currentTimeMillis()): PackSelectionStore {
        val nextActive = library.existingIdsInOrder(activePackIds).take(MAX_ACTIVE)
        return copy(
            activePackIds = nextActive,
            pinnedPackIds = pinnedPackIds.intersect(nextActive.toSet()),
            perfectScoresByPack = perfectScoresByPack.filterKeys { it in nextActive },
            lastSelectionUpdatedAtMs = nowMs,
        )
    }

    fun recordPerfectRun(packId: String, library: PackLibrary, nowMs: Long = System.currentTimeMillis()): PackSelectionMutation {
        if (packId !in activePackIds || packId in pinnedPackIds) {
            return PackSelectionMutation(this, true)
        }
        val nextScore = (perfectScoresByPack[packId] ?: 0) + 1
        if (nextScore < PERFECT_RUNS_TO_ROTATE) {
            return PackSelectionMutation(
                copy(perfectScoresByPack = perfectScoresByPack + (packId to nextScore)),
                true,
            )
        }
        val candidate = rotationCandidates(library).firstOrNull()
        if (candidate == null) {
            return PackSelectionMutation(
                copy(perfectScoresByPack = perfectScoresByPack + (packId to nextScore)),
                true,
            )
        }
        val rotated = activePackIds.map { if (it == packId) candidate.id else it }
        return PackSelectionMutation(
            copy(
                activePackIds = rotated,
                perfectScoresByPack = perfectScoresByPack - packId,
                lastSelectionUpdatedAtMs = nowMs,
            ),
            true,
            "已轮换到 ${candidate.nameZh}",
        )
    }

    private fun rotationCandidates(library: PackLibrary): List<WordPack> {
        val active = activePackIds.toSet()
        return library.inactivePacks(activePackIds)
            .filterNot { it.id in active }
            .sortedWith(
                compareBy<WordPack> {
                    when (it.source) {
                        PackSource.Family -> 0
                        PackSource.Global -> 1
                        PackSource.Builtin -> 2
                    }
                }.thenByDescending { it.publishedAtMs ?: 0L }.thenBy { it.id },
            )
    }

    companion object {
        const val MAX_ACTIVE = 5
        const val PERFECT_RUNS_TO_ROTATE = 3

        fun initial(defaultIds: List<String>, nowMs: Long = 0L): PackSelectionStore {
            return PackSelectionStore(
                activePackIds = defaultIds.distinct().take(MAX_ACTIVE),
                pinnedPackIds = emptySet(),
                perfectScoresByPack = emptyMap(),
                lastSelectionUpdatedAtMs = nowMs,
            )
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd android && ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.core.PackSelectionStoreTest
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/cool/happyword/wordmagic/core/PackSelectionStore.kt android/app/src/test/java/cool/happyword/wordmagic/core/PackSelectionStoreTest.kt
git commit -m "feat(android): add pack selection rotation rules"
```

## Task 4: Learning Recorder And Battle Result Event Shape

**Files:**
- Create: `android/app/src/main/java/cool/happyword/wordmagic/core/LearningRecorder.kt`
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/core/Models.kt`
- Test: `android/app/src/test/java/cool/happyword/wordmagic/core/LearningRecorderTest.kt`

- [ ] **Step 1: Write the failing test**

```kotlin
package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LearningRecorderTest {
    @Test
    fun recordsAnswersByPackAndWordAndBuildsSessionSummary() {
        val recorder = LearningRecorder()
        recorder.recordAnswer(
            packId = "fruit-forest",
            wordId = "fruit-apple",
            correct = true,
            answeredAtMs = 100L,
        )
        recorder.recordAnswer(
            packId = "fruit-forest",
            wordId = "fruit-apple",
            correct = false,
            answeredAtMs = 200L,
        )
        recorder.recordSession(
            BattleSessionRecord(
                packId = "fruit-forest",
                won = true,
                stars = 3,
                correctCount = 4,
                wrongCount = 0,
                defeatedMonsters = 5,
                completedAtMs = 300L,
            ),
        )

        val stat = recorder.statsSnapshot().single()
        assertEquals("fruit-forest", stat.packId)
        assertEquals("fruit-apple", stat.wordId)
        assertEquals(2, stat.seenCount)
        assertEquals(1, stat.correctCount)
        assertEquals(200L, stat.lastSeenAtMs)
        assertTrue(recorder.sessionSnapshot().single().perfect)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd android && ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.core.LearningRecorderTest
```

Expected: fail because `LearningRecorder` and `BattleSessionRecord` do not exist.

- [ ] **Step 3: Add recorder models and implementation**

Create `android/app/src/main/java/cool/happyword/wordmagic/core/LearningRecorder.kt`:

```kotlin
package cool.happyword.wordmagic.core

data class WordLearningStat(
    val packId: String,
    val wordId: String,
    val seenCount: Int,
    val correctCount: Int,
    val wrongCount: Int,
    val lastSeenAtMs: Long,
) {
    val accuracyPercent: Int
        get() = if (seenCount == 0) 0 else (correctCount * 100) / seenCount
}

data class BattleSessionRecord(
    val packId: String,
    val won: Boolean,
    val stars: Int,
    val correctCount: Int,
    val wrongCount: Int,
    val defeatedMonsters: Int,
    val completedAtMs: Long,
) {
    val perfect: Boolean
        get() = won && wrongCount == 0
}

class LearningRecorder(
    initialStats: List<WordLearningStat> = emptyList(),
    initialSessions: List<BattleSessionRecord> = emptyList(),
) {
    private val statsByKey = linkedMapOf<String, WordLearningStat>()
    private val sessions = mutableListOf<BattleSessionRecord>()

    init {
        initialStats.forEach { statsByKey[key(it.packId, it.wordId)] = it }
        sessions += initialSessions
    }

    fun recordAnswer(packId: String, wordId: String, correct: Boolean, answeredAtMs: Long) {
        val key = key(packId, wordId)
        val previous = statsByKey[key]
        statsByKey[key] = WordLearningStat(
            packId = packId,
            wordId = wordId,
            seenCount = (previous?.seenCount ?: 0) + 1,
            correctCount = (previous?.correctCount ?: 0) + if (correct) 1 else 0,
            wrongCount = (previous?.wrongCount ?: 0) + if (correct) 0 else 1,
            lastSeenAtMs = answeredAtMs,
        )
    }

    fun recordSession(record: BattleSessionRecord) {
        sessions += record
    }

    fun statsSnapshot(): List<WordLearningStat> = statsByKey.values.toList()

    fun sessionSnapshot(): List<BattleSessionRecord> = sessions.toList()

    private fun key(packId: String, wordId: String): String = "$packId::$wordId"
}
```

Modify `SessionResult` in `android/app/src/main/java/cool/happyword/wordmagic/core/Models.kt` so the result can carry pack identity:

```kotlin
data class SessionResult(
    val won: Boolean,
    val stars: Int,
    val defeatedMonsters: Int,
    val correctCount: Int,
    val wrongCount: Int,
    val learnedWordCount: Int,
    val coinDelta: Int,
    val packId: String = "fruit-forest",
)
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd android && ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.core.LearningRecorderTest
cd android && ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.core.BattleEngineTest
```

Expected: both commands end with `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/cool/happyword/wordmagic/core/LearningRecorder.kt android/app/src/main/java/cool/happyword/wordmagic/core/Models.kt android/app/src/test/java/cool/happyword/wordmagic/core/LearningRecorderTest.kt
git commit -m "feat(android): record local learning progress"
```

## Task 5: Pack-Keyed Learning Report Builder

**Files:**
- Create: `android/app/src/main/java/cool/happyword/wordmagic/core/LearningReportBuilder.kt`
- Test: `android/app/src/test/java/cool/happyword/wordmagic/core/LearningReportBuilderTest.kt`

- [ ] **Step 1: Write the failing test**

```kotlin
package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LearningReportBuilderTest {
    @Test
    fun buildsPackRowsWithActiveFirstAndDedupedTotals() {
        val library = PackLibrary.merge(BuiltinPacks.all, emptyList(), emptyList())
        val recorder = LearningRecorder()
        recorder.recordAnswer("fruit-forest", "fruit-apple", true, 100L)
        recorder.recordAnswer("fruit-forest", "fruit-apple", true, 200L)
        recorder.recordAnswer("school-castle", "school-book", false, 300L)

        val report = LearningReportBuilder().build(
            library = library,
            activeIds = listOf("school-castle", "fruit-forest"),
            stats = recorder.statsSnapshot(),
        )

        assertEquals(2, report.totalSeenWords)
        assertEquals(2, report.totalCorrectAnswers)
        assertEquals("school-castle", report.packRows[0].packId)
        assertEquals("fruit-forest", report.packRows[1].packId)
        assertTrue(report.packRows[0].active)
        assertEquals(0, report.packRows[0].accuracyPercent)
        assertEquals(100, report.packRows[1].accuracyPercent)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd android && ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.core.LearningReportBuilderTest
```

Expected: fail because report types do not exist.

- [ ] **Step 3: Add report builder implementation**

Create `android/app/src/main/java/cool/happyword/wordmagic/core/LearningReportBuilder.kt`:

```kotlin
package cool.happyword.wordmagic.core

data class PackReportRow(
    val packId: String,
    val nameEn: String,
    val nameZh: String,
    val active: Boolean,
    val totalWords: Int,
    val seenWords: Int,
    val correctAnswers: Int,
    val wrongAnswers: Int,
    val accuracyPercent: Int,
)

data class LearningReport(
    val totalWords: Int,
    val totalSeenWords: Int,
    val totalCorrectAnswers: Int,
    val totalWrongAnswers: Int,
    val accuracyPercent: Int,
    val packRows: List<PackReportRow>,
)

class LearningReportBuilder {
    fun build(
        library: PackLibrary,
        activeIds: List<String>,
        stats: List<WordLearningStat>,
    ): LearningReport {
        val statsByPackWord = stats.associateBy { "${it.packId}::${it.wordId}" }
        val activeSet = activeIds.toSet()
        val activeRows = library.activePacks(activeIds).map { pack -> rowFor(pack, true, statsByPackWord) }
        val inactiveRows = library.inactivePacks(activeIds)
            .map { pack -> rowFor(pack, false, statsByPackWord) }
            .filter { it.seenWords > 0 }
            .sortedWith(compareBy<PackReportRow> { it.accuracyPercent }.thenBy { it.packId })
        val rows = activeRows + inactiveRows
        val uniqueSeen = stats.map { it.wordId }.toSet().size
        val correct = stats.sumOf { it.correctCount }
        val wrong = stats.sumOf { it.wrongCount }
        val attempts = correct + wrong
        return LearningReport(
            totalWords = library.allPacks().flatMap { it.words }.map { it.id }.toSet().size,
            totalSeenWords = uniqueSeen,
            totalCorrectAnswers = correct,
            totalWrongAnswers = wrong,
            accuracyPercent = if (attempts == 0) 0 else (correct * 100) / attempts,
            packRows = rows.filter { it.active || it.packId !in activeSet || it.seenWords > 0 },
        )
    }

    private fun rowFor(pack: WordPack, active: Boolean, statsByPackWord: Map<String, WordLearningStat>): PackReportRow {
        val packStats = pack.words.mapNotNull { word -> statsByPackWord["${pack.id}::${word.id}"] }
        val correct = packStats.sumOf { it.correctCount }
        val wrong = packStats.sumOf { it.wrongCount }
        val attempts = correct + wrong
        return PackReportRow(
            packId = pack.id,
            nameEn = pack.nameEn,
            nameZh = pack.nameZh,
            active = active,
            totalWords = pack.words.size,
            seenWords = packStats.count { it.seenCount > 0 },
            correctAnswers = correct,
            wrongAnswers = wrong,
            accuracyPercent = if (attempts == 0) 0 else (correct * 100) / attempts,
        )
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd android && ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.core.LearningReportBuilderTest
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/cool/happyword/wordmagic/core/LearningReportBuilder.kt android/app/src/test/java/cool/happyword/wordmagic/core/LearningReportBuilderTest.kt
git commit -m "feat(android): build pack keyed learning reports"
```

## Task 6: Today Plan Service

**Files:**
- Create: `android/app/src/main/java/cool/happyword/wordmagic/core/TodayPlanService.kt`
- Test: `android/app/src/test/java/cool/happyword/wordmagic/core/TodayPlanServiceTest.kt`

- [ ] **Step 1: Write the failing test**

```kotlin
package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Test

class TodayPlanServiceTest {
    @Test
    fun bucketsActivePackWordsByLocalStats() {
        val library = PackLibrary.merge(BuiltinPacks.all, emptyList(), emptyList())
        val recorder = LearningRecorder()
        recorder.recordAnswer("fruit-forest", "fruit-apple", true, 100L)
        recorder.recordAnswer("fruit-forest", "fruit-banana", false, 200L)

        val plan = TodayPlanService().build(
            library = library,
            activeIds = listOf("fruit-forest"),
            stats = recorder.statsSnapshot(),
        )

        assertEquals(listOf("fruit-banana"), plan.review.map { it.id })
        assertEquals(listOf("fruit-apple"), plan.learning.map { it.id })
        assertEquals(listOf("fruit-pear", "fruit-orange", "fruit-grape"), plan.newWords.map { it.id })
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd android && ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.core.TodayPlanServiceTest
```

Expected: fail because `TodayPlanService` does not exist.

- [ ] **Step 3: Add TodayPlan implementation**

Create `android/app/src/main/java/cool/happyword/wordmagic/core/TodayPlanService.kt`:

```kotlin
package cool.happyword.wordmagic.core

data class TodayPlan(
    val review: List<WordEntry>,
    val learning: List<WordEntry>,
    val newWords: List<WordEntry>,
)

class TodayPlanService {
    fun build(library: PackLibrary, activeIds: List<String>, stats: List<WordLearningStat>): TodayPlan {
        val statsByWord = stats.associateBy { it.wordId }
        val activeWords = library.activePacks(activeIds).flatMap { it.words }
        val review = activeWords.filter { word ->
            val stat = statsByWord[word.id]
            stat != null && stat.wrongCount > 0
        }
        val learning = activeWords.filter { word ->
            val stat = statsByWord[word.id]
            stat != null && stat.wrongCount == 0 && stat.seenCount > 0
        }
        val newWords = activeWords.filter { word -> statsByWord[word.id] == null }
        return TodayPlan(review = review, learning = learning, newWords = newWords)
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd android && ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.core.TodayPlanServiceTest
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/cool/happyword/wordmagic/core/TodayPlanService.kt android/app/src/test/java/cool/happyword/wordmagic/core/TodayPlanServiceTest.kt
git commit -m "feat(android): add local today plan service"
```

## Task 7: Coins, Wishlist, Redemption, And Monster Catalog Rules

**Files:**
- Create: `android/app/src/main/java/cool/happyword/wordmagic/core/GrowthModels.kt`
- Test: `android/app/src/test/java/cool/happyword/wordmagic/core/GrowthStoresTest.kt`

- [ ] **Step 1: Write the failing test**

```kotlin
package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GrowthStoresTest {
    @Test
    fun coinAccountCapsDailyBattleRewardsAtTwenty() {
        val account = CoinAccount(balance = 18, earnedByDay = mapOf("2026-05-11" to 18))
        val credited = account.creditBattleReward(stars = 3, dayKey = "2026-05-11")

        assertEquals(20, credited.account.balance)
        assertEquals(2, credited.delta)
    }

    @Test
    fun redeemWishDebitsCoinsAndAddsNewestHistory() {
        val wish = WishItem("toy-1", "贴纸", 5, "🌟", custom = false)
        val state = WishlistState(defaultWishes = listOf(wish), customWishes = emptyList())
        val result = RedemptionHistoryStore().redeem(
            account = CoinAccount(balance = 8),
            wishlist = state,
            wishId = "toy-1",
            redeemedAtMs = 100L,
            parentApproved = true,
        )

        assertTrue(result.accepted)
        assertEquals(3, result.account.balance)
        assertEquals("贴纸", result.history.records.first().title)
    }

    @Test
    fun monsterCatalogCyclesThroughCopiedRuntimeAssets() {
        val catalog = MonsterCatalog.default()

        assertEquals("Slime", catalog.current().nameEn)
        assertEquals("Zombie", catalog.next().current().nameEn)
        assertFalse(catalog.entries.isEmpty())
    }

    @Test
    fun redeemWithoutParentApprovalDoesNotMutateCoinsOrHistory() {
        val wish = WishItem("toy-1", "贴纸", 5, "🌟", custom = false)
        val result = RedemptionHistoryStore().redeem(
            account = CoinAccount(balance = 8),
            wishlist = WishlistState(defaultWishes = listOf(wish), customWishes = emptyList()),
            wishId = "toy-1",
            redeemedAtMs = 100L,
            parentApproved = false,
        )

        assertFalse(result.accepted)
        assertEquals(8, result.account.balance)
        assertEquals(0, result.history.records.size)
        assertEquals("需要家长确认", result.message)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd android && ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.core.GrowthStoresTest
```

Expected: fail because growth models do not exist.

- [ ] **Step 3: Add growth implementation**

Create `android/app/src/main/java/cool/happyword/wordmagic/core/GrowthModels.kt`:

```kotlin
package cool.happyword.wordmagic.core

data class CoinCreditResult(val account: CoinAccount, val delta: Int)

data class CoinAccount(
    val balance: Int = 28,
    val earnedByDay: Map<String, Int> = emptyMap(),
) {
    fun creditBattleReward(stars: Int, dayKey: String): CoinCreditResult {
        val reward = stars.coerceIn(0, 3)
        val earnedToday = earnedByDay[dayKey] ?: 0
        val allowed = (DAILY_BATTLE_REWARD_CAP - earnedToday).coerceAtLeast(0)
        val delta = reward.coerceAtMost(allowed)
        return CoinCreditResult(
            account = copy(
                balance = balance + delta,
                earnedByDay = earnedByDay + (dayKey to (earnedToday + delta)),
            ),
            delta = delta,
        )
    }

    fun debit(cost: Int): CoinAccount {
        require(cost > 0) { "coin cost must be positive" }
        require(balance >= cost) { "not enough coins" }
        return copy(balance = balance - cost)
    }

    companion object {
        const val DAILY_BATTLE_REWARD_CAP = 20
    }
}

data class WishItem(
    val id: String,
    val title: String,
    val cost: Int,
    val icon: String,
    val custom: Boolean,
)

data class WishlistState(
    val defaultWishes: List<WishItem>,
    val customWishes: List<WishItem>,
) {
    fun allWishes(): List<WishItem> = defaultWishes + customWishes

    companion object {
        fun default(): WishlistState = WishlistState(
            defaultWishes = listOf(
                WishItem("sticker", "贴纸", 5, "🌟", false),
                WishItem("story", "睡前故事", 8, "📖", false),
                WishItem("park", "公园时间", 12, "🎈", false),
            ),
            customWishes = emptyList(),
        )
    }
}

data class RedemptionRecord(
    val id: String,
    val wishId: String,
    val title: String,
    val cost: Int,
    val redeemedAtMs: Long,
    val status: String = "已兑换",
)

data class RedemptionResult(
    val accepted: Boolean,
    val account: CoinAccount,
    val history: RedemptionHistoryStore,
    val message: String,
)

data class RedemptionHistoryStore(
    val records: List<RedemptionRecord> = emptyList(),
) {
    fun redeem(
        account: CoinAccount,
        wishlist: WishlistState,
        wishId: String,
        redeemedAtMs: Long,
        parentApproved: Boolean,
    ): RedemptionResult {
        if (!parentApproved) {
            return RedemptionResult(false, account, this, "需要家长确认")
        }
        val wish = wishlist.allWishes().firstOrNull { it.id == wishId }
            ?: return RedemptionResult(false, account, this, "愿望不存在")
        if (account.balance < wish.cost) {
            return RedemptionResult(false, account, this, "魔法币不足")
        }
        val nextAccount = account.debit(wish.cost)
        val nextRecord = RedemptionRecord(
            id = "redemption-$redeemedAtMs-${wish.id}",
            wishId = wish.id,
            title = wish.title,
            cost = wish.cost,
            redeemedAtMs = redeemedAtMs,
        )
        return RedemptionResult(
            accepted = true,
            account = nextAccount,
            history = copy(records = (listOf(nextRecord) + records).take(MAX_RECORDS)),
            message = "兑换成功",
        )
    }

    companion object {
        const val MAX_RECORDS = 50
    }
}

data class MonsterEntry(
    val id: String,
    val nameEn: String,
    val kindZh: String,
    val descriptionZh: String,
    val rawResourceName: String,
)

data class MonsterCatalog(
    val entries: List<MonsterEntry>,
    val index: Int = 0,
) {
    fun current(): MonsterEntry = entries[index.mod(entries.size)]

    fun next(): MonsterCatalog = copy(index = (index + 1).mod(entries.size))

    fun previous(): MonsterCatalog = copy(index = (index - 1).mod(entries.size))

    companion object {
        fun default(): MonsterCatalog = MonsterCatalog(
            entries = listOf(
                MonsterEntry("slime", "Slime", "单词怪物", "会弹跳的入门怪物。", "character_slime"),
                MonsterEntry("zombie", "Zombie", "单词怪物", "守在校园城堡里的拼写怪物。", "character_zombie"),
                MonsterEntry("dragon", "Dragon", "首领怪物", "喜欢守护宝藏的强力怪物。", "character_dragon"),
            ),
        )
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd android && ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.core.GrowthStoresTest
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/cool/happyword/wordmagic/core/GrowthModels.kt android/app/src/test/java/cool/happyword/wordmagic/core/GrowthStoresTest.kt
git commit -m "feat(android): add local growth rule models"
```

## Task 8: Android Local Persistence Repositories

**Files:**
- Create: `android/app/src/main/java/cool/happyword/wordmagic/data/LocalJsonStore.kt`
- Create: `android/app/src/main/java/cool/happyword/wordmagic/data/AndroidPhase2Repositories.kt`
- Modify: `android/app/build.gradle.kts`

- [ ] **Step 1: Add serialization dependency**

Modify `android/build.gradle.kts` plugins by keeping the existing Android plugin version and adding only the serialization plugin line:

```kotlin
plugins {
    id("com.android.application") version "9.2.1" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.2.21" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.2.21" apply false
}
```

Modify `android/app/build.gradle.kts` plugins and dependencies:

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.04.01"))
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("com.caverock:androidsvg-aar:1.4")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    testImplementation("junit:junit:4.13.2")

    androidTestImplementation(platform("androidx.compose:compose-bom:2026.04.01"))
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.7.0")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
}
```

- [ ] **Step 2: Run Gradle sync check**

Run:

```bash
cd android && ./gradlew :app:tasks --all
```

Expected: Gradle configures without plugin or dependency errors.

- [ ] **Step 3: Add repository files**

Create `android/app/src/main/java/cool/happyword/wordmagic/data/LocalJsonStore.kt`:

```kotlin
package cool.happyword.wordmagic.data

import android.content.Context
import java.io.File

class LocalJsonStore(context: Context, private val fileName: String) {
    private val file: File = File(context.filesDir, fileName)

    fun readOrNull(): String? {
        return if (file.exists()) file.readText() else null
    }

    fun write(value: String) {
        file.parentFile?.mkdirs()
        file.writeText(value)
    }
}
```

Create `android/app/src/main/java/cool/happyword/wordmagic/data/AndroidPhase2Repositories.kt`:

```kotlin
package cool.happyword.wordmagic.data

import android.content.Context
import cool.happyword.wordmagic.core.BuiltinPacks
import cool.happyword.wordmagic.core.CoinAccount
import cool.happyword.wordmagic.core.LearningRecorder
import cool.happyword.wordmagic.core.PackSelectionStore
import cool.happyword.wordmagic.core.RedemptionRecord
import cool.happyword.wordmagic.core.RedemptionHistoryStore
import cool.happyword.wordmagic.core.WishlistState
import cool.happyword.wordmagic.core.WordLearningStat

class AndroidPhase2Repositories(context: Context) {
    private val prefs = context.getSharedPreferences("wordmagic-phase2", Context.MODE_PRIVATE)

    fun loadSelection(): PackSelectionStore {
        val ids = prefs.getString("activePackIds", null)
            ?.split(",")
            ?.filter { it.isNotBlank() }
            ?: BuiltinPacks.defaultActiveOrder
        val pins = prefs.getStringSet("pinnedPackIds", emptySet()) ?: emptySet()
        return PackSelectionStore.initial(ids).copy(pinnedPackIds = pins)
    }

    fun saveSelection(selection: PackSelectionStore) {
        prefs.edit()
            .putString("activePackIds", selection.activePackIds.joinToString(","))
            .putStringSet("pinnedPackIds", selection.pinnedPackIds)
            .apply()
    }

    fun loadCoinAccount(): CoinAccount {
        val earned = prefs.getString("coinEarnedByDay", "").orEmpty()
            .lineSequence()
            .mapNotNull { line ->
                val parts = line.split('\t')
                if (parts.size == 2) parts[0] to parts[1].toInt() else null
            }
            .toMap()
        return CoinAccount(balance = prefs.getInt("coinBalance", 28), earnedByDay = earned)
    }

    fun saveCoinAccount(account: CoinAccount) {
        prefs.edit()
            .putInt("coinBalance", account.balance)
            .putString("coinEarnedByDay", account.earnedByDay.entries.joinToString("\n") { "${it.key}\t${it.value}" })
            .apply()
    }

    fun loadWishlist(): WishlistState = WishlistState.default()

    fun loadRedemptionHistory(): RedemptionHistoryStore {
        val records = prefs.getString("redemptionHistory", "").orEmpty()
            .lineSequence()
            .mapNotNull { line ->
                val parts = line.split('\t')
                if (parts.size == 6) {
                    RedemptionRecord(
                        id = parts[0],
                        wishId = parts[1],
                        title = parts[2],
                        cost = parts[3].toInt(),
                        redeemedAtMs = parts[4].toLong(),
                        status = parts[5],
                    )
                } else {
                    null
                }
            }
            .toList()
        return RedemptionHistoryStore(records)
    }

    fun saveRedemptionHistory(history: RedemptionHistoryStore) {
        prefs.edit()
            .putString(
                "redemptionHistory",
                history.records.joinToString("\n") { "${it.id}\t${it.wishId}\t${it.title}\t${it.cost}\t${it.redeemedAtMs}\t${it.status}" },
            )
            .apply()
    }

    fun loadLearningRecorder(): LearningRecorder {
        val stats = prefs.getString("learningStats", "").orEmpty()
            .lineSequence()
            .mapNotNull { line ->
                val parts = line.split('\t')
                if (parts.size == 6) {
                    WordLearningStat(
                        packId = parts[0],
                        wordId = parts[1],
                        seenCount = parts[2].toInt(),
                        correctCount = parts[3].toInt(),
                        wrongCount = parts[4].toInt(),
                        lastSeenAtMs = parts[5].toLong(),
                    )
                } else {
                    null
                }
            }
            .toList()
        return LearningRecorder(initialStats = stats)
    }

    fun saveLearningRecorder(recorder: LearningRecorder) {
        prefs.edit()
            .putString(
                "learningStats",
                recorder.statsSnapshot().joinToString("\n") {
                    "${it.packId}\t${it.wordId}\t${it.seenCount}\t${it.correctCount}\t${it.wrongCount}\t${it.lastSeenAtMs}"
                },
            )
            .apply()
    }
}
```

- [ ] **Step 4: Run compile**

Run:

```bash
cd android && ./gradlew testDebugUnitTest
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
git add android/build.gradle.kts android/app/build.gradle.kts android/app/src/main/java/cool/happyword/wordmagic/data/LocalJsonStore.kt android/app/src/main/java/cool/happyword/wordmagic/data/AndroidPhase2Repositories.kt
git commit -m "feat(android): add phase2 local repositories"
```

## Task 9: App Shell State And Home Integration

**Files:**
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/MainActivity.kt`

- [ ] **Step 1: Extend routes**

Replace `AppRoute` with:

```kotlin
private enum class AppRoute {
    Home,
    Battle,
    Result,
    Config,
    ParentPin,
    ParentAdmin,
    LessonDraftReview,
    PackManager,
    Wishlist,
    RedemptionHistory,
    MonsterCodex,
    TodayPlan,
    LearningReport,
}
```

- [ ] **Step 2: Update orientation rule**

Update `ApplyOrientation` so only parent/admin/review remain portrait:

```kotlin
activity?.requestedOrientation = when (route) {
    AppRoute.ParentPin,
    AppRoute.ParentAdmin,
    AppRoute.LessonDraftReview -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    else -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
}
```

- [ ] **Step 3: Replace hardcoded `packs` state with library and selection**

Inside `WordMagicGameApp`, initialize:

```kotlin
val context = LocalContext.current
val repositories = remember { AndroidPhase2Repositories(context.applicationContext) }
val packLibrary = remember { PackLibrary.merge(BuiltinPacks.all, emptyList(), emptyList()) }
var selection by remember { mutableStateOf(repositories.loadSelection().prune(packLibrary)) }
var selectedPackId by remember { mutableStateOf(selection.activePackIds.first()) }
val selectedPack = packLibrary.findPack(selectedPackId) ?: packLibrary.requirePack(selection.activePackIds.first())
var coinAccount by remember { mutableStateOf(repositories.loadCoinAccount()) }
var learningRecorder by remember { mutableStateOf(repositories.loadLearningRecorder()) }
var wishlist by remember { mutableStateOf(repositories.loadWishlist()) }
var redemptionHistory by remember { mutableStateOf(repositories.loadRedemptionHistory()) }
```

Import these types:

```kotlin
import cool.happyword.wordmagic.core.BuiltinPacks
import cool.happyword.wordmagic.core.CoinAccount
import cool.happyword.wordmagic.core.LearningRecorder
import cool.happyword.wordmagic.core.PackLibrary
import cool.happyword.wordmagic.core.PackSelectionStore
import cool.happyword.wordmagic.core.WordPack
import cool.happyword.wordmagic.data.AndroidPhase2Repositories
```

- [ ] **Step 4: Update HomeScreen signature**

Change HomeScreen parameters:

```kotlin
private fun HomeScreen(
    activePacks: List<WordPack>,
    selectedPack: WordPack,
    coins: Int,
    onSelectPack: (WordPack) -> Unit,
    onStart: () -> Unit,
    onPackManager: () -> Unit,
    onWishlist: () -> Unit,
    onMonsterCodex: () -> Unit,
    onTodayPlan: () -> Unit,
    onConfig: () -> Unit,
)
```

Replace `homePacks` in the chip row with `activePacks`. Wire icon buttons:

```kotlin
IconCircle(R.drawable.icon_review, "复习", Modifier.testTag("HomeTodayPlanButton"), onClick = onTodayPlan)
IconCircle(R.drawable.icon_codex, "图鉴", Modifier.testTag("HomeCodexButton"), onClick = onMonsterCodex)
IconCircle(R.drawable.icon_scroll, "计划", Modifier.testTag("HomePackManagerButton"), onClick = onPackManager)
IconCircle(R.drawable.icon_wishlist, "愿望", Modifier.testTag("HomeWishlistButton"), onClick = onWishlist)
IconCircle(R.drawable.icon_gear, "设置", Modifier.testTag("HomeConfigButton"), onClick = onConfig)
```

- [ ] **Step 5: Start Battle with selected pack words**

In the Home `onStart` branch, replace the engine constructor with:

```kotlin
engine = BattleEngine(config = sessionConfig, words = selectedPack.words)
```

- [ ] **Step 6: Run tests**

Run:

```bash
cd android && ./gradlew testDebugUnitTest
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 7: Commit**

```bash
git add android/app/src/main/java/cool/happyword/wordmagic/MainActivity.kt
git commit -m "feat(android): connect home to local pack state"
```

## Task 10: Battle Result Recording, Coins, And Pack Rotation

**Files:**
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/MainActivity.kt`
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/core/BattleEngine.kt`
- Test: `android/app/src/test/java/cool/happyword/wordmagic/core/BattleEngineTest.kt`

- [ ] **Step 1: Add battle result test for selected pack id**

Append to `BattleEngineTest.kt`:

```kotlin
@Test
fun resultCanBeCopiedWithPackIdForLocalRecording() {
    val result = BattleEngine().resultFor(
        BattleState(
            playerHp = 5,
            monsterHp = 0,
            monsterIndex = 5,
            combo = 0,
            correctCount = 5,
            wrongCount = 0,
            defeatedMonsters = 5,
            question = Question("苹果", "apple", listOf("apple", "banana", "cat")),
            status = BattleStatus.Won,
        ),
    ).copy(packId = "fruit-forest")

    assertEquals("fruit-forest", result.packId)
    assertEquals(3, result.coinDelta)
}
```

- [ ] **Step 2: Run test**

Run:

```bash
cd android && ./gradlew testDebugUnitTest --tests cool.happyword.wordmagic.core.BattleEngineTest
```

Expected: `BUILD SUCCESSFUL` because Task 4 already added `packId`.

- [ ] **Step 3: Record result in `onBattleFinished`**

In `WordMagicGameApp`, replace the current `onBattleFinished` body with:

```kotlin
onBattleFinished = { finishedState ->
    val sessionResult = engine.resultFor(finishedState).copy(packId = selectedPack.id)
    val dayKey = java.time.LocalDate.now().toString()
    val credited = coinAccount.creditBattleReward(sessionResult.stars, dayKey)
    val sessionRecord = BattleSessionRecord(
        packId = selectedPack.id,
        won = sessionResult.won,
        stars = sessionResult.stars,
        correctCount = sessionResult.correctCount,
        wrongCount = sessionResult.wrongCount,
        defeatedMonsters = sessionResult.defeatedMonsters,
        completedAtMs = System.currentTimeMillis(),
    )
    learningRecorder.recordSession(sessionRecord)
    repositories.saveLearningRecorder(learningRecorder)
    if (sessionRecord.perfect) {
        val rotation = selection.recordPerfectRun(selectedPack.id, packLibrary)
        selection = rotation.selection
        repositories.saveSelection(selection)
        selectedPackId = selection.activePackIds.firstOrNull() ?: selectedPack.id
    }
    coinAccount = credited.account
    repositories.saveCoinAccount(coinAccount)
    result = sessionResult.copy(coinDelta = credited.delta)
    route = AppRoute.Result
}
```

Add imports:

```kotlin
import cool.happyword.wordmagic.core.BattleSessionRecord
```

- [ ] **Step 4: Record each answer**

In `onAnswer`, after `val outcome = engine.submitAnswerWithOutcome(...)`, add:

```kotlin
val answeredWord = selectedPack.words.firstOrNull { it.word == outcome.correctAnswer }
if (answeredWord != null) {
    learningRecorder.recordAnswer(
        packId = selectedPack.id,
        wordId = answeredWord.id,
        correct = outcome.correct,
        answeredAtMs = System.currentTimeMillis(),
    )
    repositories.saveLearningRecorder(learningRecorder)
}
```

- [ ] **Step 5: Run tests and assemble**

Run:

```bash
cd android && ./gradlew testDebugUnitTest
cd android && ./gradlew assembleDebug
```

Expected: both commands end with `BUILD SUCCESSFUL`.

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/java/cool/happyword/wordmagic/MainActivity.kt android/app/src/main/java/cool/happyword/wordmagic/core/BattleEngine.kt android/app/src/test/java/cool/happyword/wordmagic/core/BattleEngineTest.kt
git commit -m "feat(android): record battle rewards and pack progress"
```

## Task 11: Phase 2 Compose Screens

**Files:**
- Create: `android/app/src/main/java/cool/happyword/wordmagic/ui/Phase2Screens.kt`
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/MainActivity.kt`

- [ ] **Step 1: Create screen file with stable test tags**

Create `android/app/src/main/java/cool/happyword/wordmagic/ui/Phase2Screens.kt`:

```kotlin
package cool.happyword.wordmagic.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cool.happyword.wordmagic.R
import cool.happyword.wordmagic.core.CoinAccount
import cool.happyword.wordmagic.core.LearningReport
import cool.happyword.wordmagic.core.MonsterCatalog
import cool.happyword.wordmagic.core.PackSelectionStore
import cool.happyword.wordmagic.core.RedemptionHistoryStore
import cool.happyword.wordmagic.core.TodayPlan
import cool.happyword.wordmagic.core.WishItem
import cool.happyword.wordmagic.core.WishlistState
import cool.happyword.wordmagic.core.WordPack

@Composable
fun PackManagerScreen(
    packs: List<WordPack>,
    selection: PackSelectionStore,
    message: String,
    onToggleActive: (WordPack) -> Unit,
    onTogglePin: (WordPack) -> Unit,
    onBack: () -> Unit,
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().background(Color.White).padding(24.dp).testTag("PackManagerScreen"),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("我的词包", modifier = Modifier.testTag("PackManagerTitle"), fontSize = 28.sp, fontWeight = FontWeight.Black)
                Spacer(Modifier.weight(1f))
                Text("${selection.activePackIds.size}/5", modifier = Modifier.testTag("PackManagerActiveCount"))
                Spacer(Modifier.width(12.dp))
                OutlinedButton(onClick = onBack, modifier = Modifier.testTag("PackManagerBack")) { Text("返回") }
            }
            Text(message, color = Color(0xFFD94141), modifier = Modifier.testTag("PackManagerLimitMessage"))
        }
        items(packs) { pack ->
            Card(colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF7E6))) {
                Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(pack.nameEn, modifier = Modifier.testTag("PackLabel_${pack.id}"), fontWeight = FontWeight.Black)
                        Text("${pack.nameZh} · ${pack.source}", modifier = Modifier.testTag("PackSourceTag_${pack.id}"))
                    }
                    Switch(
                        checked = pack.id in selection.activePackIds,
                        onCheckedChange = { onToggleActive(pack) },
                        modifier = Modifier.testTag("PackToggle_${pack.id}"),
                    )
                    if (pack.id in selection.activePackIds) {
                        OutlinedButton(onClick = { onTogglePin(pack) }, modifier = Modifier.testTag("PackPin_${pack.id}")) {
                            Text(if (pack.id in selection.pinnedPackIds) "已固定" else "固定")
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun WishlistScreen(
    coinAccount: CoinAccount,
    wishlist: WishlistState,
    onRedeem: (WishItem) -> Unit,
    onHistory: () -> Unit,
    onBack: () -> Unit,
) {
    LazyColumn(Modifier.fillMaxSize().background(Color(0xFFFFF6E7)).padding(24.dp).testTag("WishlistScreen")) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("愿望", fontSize = 28.sp, fontWeight = FontWeight.Black)
                Spacer(Modifier.weight(1f))
                Text("✨ ${coinAccount.balance}", modifier = Modifier.testTag("WishlistCoinBalance"))
                Spacer(Modifier.width(12.dp))
                OutlinedButton(onClick = onHistory, modifier = Modifier.testTag("WishlistHistoryButton")) { Text("历史") }
                Spacer(Modifier.width(8.dp))
                OutlinedButton(onClick = onBack) { Text("返回") }
            }
        }
        items(wishlist.allWishes()) { wish ->
            Card(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(wish.icon, fontSize = 28.sp)
                    Spacer(Modifier.width(10.dp))
                    Text(wish.title, Modifier.weight(1f), fontWeight = FontWeight.Bold)
                    Text("${wish.cost}")
                    Spacer(Modifier.width(10.dp))
                    Button(onClick = { onRedeem(wish) }, modifier = Modifier.testTag("WishRedeem_${wish.id}")) { Text("兑换") }
                }
            }
        }
    }
}

@Composable
fun RedemptionHistoryScreen(history: RedemptionHistoryStore, onBack: () -> Unit) {
    LazyColumn(Modifier.fillMaxSize().background(Color.White).padding(24.dp).testTag("RedemptionHistoryScreen")) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("兑换历史", fontSize = 28.sp, fontWeight = FontWeight.Black)
                Spacer(Modifier.weight(1f))
                OutlinedButton(onClick = onBack) { Text("返回") }
            }
        }
        items(history.records) { record ->
            Text("${record.title} · -${record.cost} · ${record.status}", Modifier.padding(vertical = 8.dp).testTag("RedemptionRecord_${record.id}"))
        }
    }
}

@Composable
fun MonsterCodexScreen(catalog: MonsterCatalog, onPrevious: () -> Unit, onNext: () -> Unit, onBack: () -> Unit) {
    val current = catalog.current()
    Column(Modifier.fillMaxSize().background(Color.White).padding(24.dp).testTag("MonsterCodexScreen"), horizontalAlignment = Alignment.CenterHorizontally) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("怪物图鉴", fontSize = 28.sp, fontWeight = FontWeight.Black)
            Spacer(Modifier.weight(1f))
            OutlinedButton(onClick = onBack, modifier = Modifier.testTag("MonsterCodexBack")) { Text("返回") }
        }
        Spacer(Modifier.height(18.dp))
        Image(painterResource(resourceIdForMonster(current.rawResourceName)), contentDescription = current.nameEn, modifier = Modifier.height(180.dp).testTag("MonsterCodexImage"))
        Text(current.nameEn, modifier = Modifier.testTag("MonsterCodexName"), fontSize = 30.sp, fontWeight = FontWeight.Black)
        Text("${current.kindZh} · ${current.descriptionZh}")
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = onPrevious, modifier = Modifier.testTag("MonsterCodexPrevious")) { Text("上一个") }
            Button(onClick = onNext, modifier = Modifier.testTag("MonsterCodexNext")) { Text("下一个") }
        }
    }
}

@Composable
fun TodayPlanScreen(plan: TodayPlan, onReport: () -> Unit, onBack: () -> Unit) {
    Column(Modifier.fillMaxSize().background(Color(0xFFFFF7E6)).padding(24.dp).testTag("TodayPlanScreen")) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("今日计划", fontSize = 28.sp, fontWeight = FontWeight.Black)
            Spacer(Modifier.weight(1f))
            Button(onClick = onReport, modifier = Modifier.testTag("TodayPlanReportButton")) { Text("学习报告") }
            Spacer(Modifier.width(8.dp))
            OutlinedButton(onClick = onBack) { Text("返回") }
        }
        PlanBucket("复习", plan.review.map { it.word }, "TodayPlanReviewBucket")
        PlanBucket("学习中", plan.learning.map { it.word }, "TodayPlanLearningBucket")
        PlanBucket("新单词", plan.newWords.map { it.word }, "TodayPlanNewBucket")
    }
}

@Composable
fun LearningReportScreen(report: LearningReport, onBack: () -> Unit) {
    LazyColumn(Modifier.fillMaxSize().background(Color.White).padding(24.dp).testTag("LearningReportScreen")) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("学习报告", fontSize = 28.sp, fontWeight = FontWeight.Black)
                Spacer(Modifier.weight(1f))
                OutlinedButton(onClick = onBack) { Text("返回") }
            }
            Text("单词 ${report.totalSeenWords}/${report.totalWords}", modifier = Modifier.testTag("LearningReportTotalWords"))
            Text("正确率 ${report.accuracyPercent}%", modifier = Modifier.testTag("LearningReportAccuracy"))
        }
        items(report.packRows) { row ->
            Text("${row.nameEn} · ${row.seenWords}/${row.totalWords} · ${row.accuracyPercent}%", Modifier.padding(vertical = 8.dp).testTag("LearningReportPackRow_${row.packId}"))
        }
    }
}

@Composable
private fun PlanBucket(title: String, words: List<String>, tag: String) {
    Card(Modifier.fillMaxWidth().padding(vertical = 8.dp).testTag(tag)) {
        Column(Modifier.padding(14.dp)) {
            Text(title, fontWeight = FontWeight.Black)
            Text(if (words.isEmpty()) "暂无" else words.joinToString(" / "))
        }
    }
}

private fun resourceIdForMonster(name: String): Int = when (name) {
    "character_zombie" -> R.drawable.icon_codex
    "character_dragon" -> R.drawable.icon_wishlist
    else -> R.drawable.icon_review
}
```

- [ ] **Step 2: Wire routes in MainActivity**

Add imports:

```kotlin
import cool.happyword.wordmagic.core.LearningReportBuilder
import cool.happyword.wordmagic.core.MonsterCatalog
import cool.happyword.wordmagic.core.TodayPlanService
import cool.happyword.wordmagic.ui.LearningReportScreen
import cool.happyword.wordmagic.ui.MonsterCodexScreen
import cool.happyword.wordmagic.ui.PackManagerScreen
import cool.happyword.wordmagic.ui.RedemptionHistoryScreen
import cool.happyword.wordmagic.ui.TodayPlanScreen
import cool.happyword.wordmagic.ui.WishlistScreen
```

Add state:

```kotlin
var phase2Message by remember { mutableStateOf("") }
var monsterCatalog by remember { mutableStateOf(MonsterCatalog.default()) }
var pendingRedemptionWishId by remember { mutableStateOf<String?>(null) }
```

Add `when(route)` branches:

```kotlin
AppRoute.PackManager -> PackManagerScreen(
    packs = packLibrary.allPacks(),
    selection = selection,
    message = phase2Message,
    onToggleActive = { pack ->
        val mutation = if (pack.id in selection.activePackIds) selection.deactivate(pack.id) else selection.activate(pack.id)
        selection = mutation.selection
        phase2Message = mutation.message
        repositories.saveSelection(selection)
    },
    onTogglePin = { pack ->
        val mutation = selection.togglePin(pack.id)
        selection = mutation.selection
        phase2Message = mutation.message
        repositories.saveSelection(selection)
    },
    onBack = { route = AppRoute.Home },
)
AppRoute.Wishlist -> WishlistScreen(
    coinAccount = coinAccount,
    wishlist = wishlist,
    onRedeem = { wish ->
        pendingRedemptionWishId = wish.id
        route = AppRoute.ParentPin
    },
    onHistory = { route = AppRoute.RedemptionHistory },
    onBack = { route = AppRoute.Home },
)
AppRoute.RedemptionHistory -> RedemptionHistoryScreen(redemptionHistory) { route = AppRoute.Wishlist }
AppRoute.MonsterCodex -> MonsterCodexScreen(
    catalog = monsterCatalog,
    onPrevious = { monsterCatalog = monsterCatalog.previous() },
    onNext = { monsterCatalog = monsterCatalog.next() },
    onBack = { route = AppRoute.Home },
)
AppRoute.TodayPlan -> TodayPlanScreen(
    plan = TodayPlanService().build(packLibrary, selection.activePackIds, learningRecorder.statsSnapshot()),
    onReport = { route = AppRoute.LearningReport },
    onBack = { route = AppRoute.Home },
)
AppRoute.LearningReport -> LearningReportScreen(
    report = LearningReportBuilder().build(packLibrary, selection.activePackIds, learningRecorder.statsSnapshot()),
    onBack = { route = AppRoute.TodayPlan },
)
```

Update the existing `AppRoute.ParentPin` branch so a pending wish redemption is handled before entering the parent admin page:

```kotlin
AppRoute.ParentPin -> ParentPinScreen(
    hasPin = parentPin.isNotEmpty(),
    onBack = {
        if (pendingRedemptionWishId != null) {
            pendingRedemptionWishId = null
            route = AppRoute.Wishlist
        } else {
            route = AppRoute.Config
        }
    },
    onSubmit = { value ->
        val pinAccepted = if (parentPin.isEmpty()) {
            parentPin = value
            true
        } else {
            value == parentPin
        }
        if (pinAccepted && pendingRedemptionWishId != null) {
            val wishId = pendingRedemptionWishId.orEmpty()
            val redeemed = redemptionHistory.redeem(
                account = coinAccount,
                wishlist = wishlist,
                wishId = wishId,
                redeemedAtMs = System.currentTimeMillis(),
                parentApproved = true,
            )
            coinAccount = redeemed.account
            redemptionHistory = redeemed.history
            phase2Message = redeemed.message
            pendingRedemptionWishId = null
            repositories.saveCoinAccount(coinAccount)
            repositories.saveRedemptionHistory(redemptionHistory)
            route = AppRoute.Wishlist
        } else if (pinAccepted) {
            route = AppRoute.ParentAdmin
        }
    },
)
```

- [ ] **Step 3: Run compile**

Run:

```bash
cd android && ./gradlew assembleDebug
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/java/cool/happyword/wordmagic/ui/Phase2Screens.kt android/app/src/main/java/cool/happyword/wordmagic/MainActivity.kt
git commit -m "feat(android): add phase2 local growth screens"
```

## Task 12: Compose UI Tests For Phase 2 Flows

**Files:**
- Create: `android/app/src/androidTest/java/cool/happyword/wordmagic/Phase2FlowTest.kt`
- Modify: `android/app/src/androidTest/java/cool/happyword/wordmagic/SmokeTest.kt`

- [ ] **Step 1: Write UI tests**

Create `android/app/src/androidTest/java/cool/happyword/wordmagic/Phase2FlowTest.kt`:

```kotlin
package cool.happyword.wordmagic

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import org.junit.Rule
import org.junit.Test

class Phase2FlowTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun packManagerCanToggleAndReturnHome() {
        composeRule.onNodeWithTag("HomePackManagerButton").performClick()
        composeRule.onNodeWithTag("PackManagerScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("PackManagerActiveCount").assertIsDisplayed()
        composeRule.onNodeWithTag("PackToggle_fruit-forest").performClick()
        composeRule.onNodeWithTag("PackManagerBack").performClick()
        composeRule.onNodeWithTag("HomeScreen").assertIsDisplayed()
    }

    @Test
    fun wishlistRedeemWritesHistory() {
        composeRule.onNodeWithTag("HomeWishlistButton").performClick()
        composeRule.onNodeWithTag("WishlistScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("WishRedeem_sticker").performClick()
        composeRule.onNodeWithTag("ParentPinScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("ParentPinInput").performTextInput("123456")
        composeRule.onNodeWithTag("WishlistScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("WishlistHistoryButton").performClick()
        composeRule.onNodeWithTag("RedemptionHistoryScreen").assertIsDisplayed()
    }

    @Test
    fun codexAndTodayPlanAndReportOpen() {
        composeRule.onNodeWithTag("HomeCodexButton").performClick()
        composeRule.onNodeWithTag("MonsterCodexScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("MonsterCodexNext").performClick()
        composeRule.onNodeWithTag("MonsterCodexName").assertIsDisplayed()
        composeRule.onNodeWithTag("MonsterCodexBack").performClick()

        composeRule.onNodeWithTag("HomeTodayPlanButton").performClick()
        composeRule.onNodeWithTag("TodayPlanScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("TodayPlanReportButton").performClick()
        composeRule.onNodeWithTag("LearningReportScreen").assertIsDisplayed()
        composeRule.onNodeWithTag("LearningReportTotalWords").assertIsDisplayed()
    }
}
```

Update `SmokeTest` only if Home icon routing changes test setup. Keep the existing Phase 1 tests for Home, Battle countdown, and word switching.

- [ ] **Step 2: Run connected test**

Run with an emulator running:

```bash
cd android && ./gradlew connectedDebugAndroidTest
```

Expected: `SmokeTest` and `Phase2FlowTest` pass.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/androidTest/java/cool/happyword/wordmagic/Phase2FlowTest.kt android/app/src/androidTest/java/cool/happyword/wordmagic/SmokeTest.kt
git commit -m "test(android): cover phase2 local growth flows"
```

## Task 13: Visual Parity Pass And Screenshot Artifacts

**Files:**
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/ui/Phase2Screens.kt`
- Modify: `android/app/src/main/java/cool/happyword/wordmagic/MainActivity.kt`
- Create screenshots under: `assets/screenshots/android/`

- [ ] **Step 1: Install debug build**

Run:

```bash
cd android && ./gradlew installDebug
```

Expected: app installs on the active emulator.

- [ ] **Step 2: Capture PackManager screenshot**

Open PackManager from Home and run:

```bash
adb exec-out screencap -p > ../assets/screenshots/android/phase2-pack-manager.png
```

Compare with `assets/screenshots/harmonyos/pack-manager.png`. Adjust spacing, colors, labels, and visible rows in `Phase2Screens.kt` until Android is visually close.

- [ ] **Step 3: Capture Wishlist screenshot**

Open Wishlist and run:

```bash
adb exec-out screencap -p > ../assets/screenshots/android/phase2-wishlist.png
```

Compare with `assets/screenshots/harmonyos/wishlist.png`. Ensure Chinese labels, coin balance, cards, and history entry affordance match the HarmonyOS style.

- [ ] **Step 4: Capture MonsterCodex screenshot**

Open MonsterCodex and run:

```bash
adb exec-out screencap -p > ../assets/screenshots/android/phase2-monster-codex.png
```

Compare with `assets/screenshots/harmonyos/monster-codex-part1.png` and `monster-codex-part2.png`. If runtime images are icon fallbacks, replace `resourceIdForMonster` with raw SVG rendering using the same `SvgRawImage` pattern from `MainActivity.kt`.

- [ ] **Step 5: Capture TodayPlan screenshot**

Open TodayPlan and run:

```bash
adb exec-out screencap -p > ../assets/screenshots/android/phase2-today-plan.png
```

Compare with `assets/screenshots/harmonyos/today-plan.png`. Keep the page read-only and keep action buttons routed through existing paths.

- [ ] **Step 6: Capture LearningReport screenshot**

Open LearningReport and run:

```bash
adb exec-out screencap -p > ../assets/screenshots/android/phase2-learning-report.png
```

Compare with `assets/screenshots/harmonyos/learning-report-part1.png` and `learning-report-part2.png`. Verify rows are pack keyed, not category keyed.

- [ ] **Step 7: Run final Android verification**

Run:

```bash
cd android && ./gradlew testDebugUnitTest
cd android && ./gradlew assembleDebug
cd android && ./gradlew connectedDebugAndroidTest
```

Expected: all commands end with `BUILD SUCCESSFUL`.

- [ ] **Step 8: Commit**

```bash
git add android/app/src/main/java/cool/happyword/wordmagic/ui/Phase2Screens.kt android/app/src/main/java/cool/happyword/wordmagic/MainActivity.kt assets/screenshots/android/phase2-pack-manager.png assets/screenshots/android/phase2-wishlist.png assets/screenshots/android/phase2-monster-codex.png assets/screenshots/android/phase2-today-plan.png assets/screenshots/android/phase2-learning-report.png
git commit -m "style(android): align phase2 screens with harmonyos"
```

## Task 14: Docs And Command Manifest Update

**Files:**
- Modify: `.cursor/android-dev-commands.md`
- Modify: `docs/android-replica/00-index.md`

- [ ] **Step 1: Add Phase 2 commands to `.cursor/android-dev-commands.md`**

Append this section:

```markdown
## Android Phase 2 Local Growth Verification

After touching PackManager, Wishlist, RedemptionHistory, MonsterCodex, TodayPlan, or LearningReport:

- `cd android && ./gradlew testDebugUnitTest`
- `cd android && ./gradlew assembleDebug`
- `cd android && ./gradlew connectedDebugAndroidTest`
- `cd android && ./gradlew installDebug`

Capture updated screenshots:

- `adb exec-out screencap -p > ../assets/screenshots/android/phase2-pack-manager.png`
- `adb exec-out screencap -p > ../assets/screenshots/android/phase2-wishlist.png`
- `adb exec-out screencap -p > ../assets/screenshots/android/phase2-monster-codex.png`
- `adb exec-out screencap -p > ../assets/screenshots/android/phase2-today-plan.png`
- `adb exec-out screencap -p > ../assets/screenshots/android/phase2-learning-report.png`
```

- [ ] **Step 2: Link the plan from `docs/android-replica/00-index.md`**

Add this row or bullet under Android implementation plans:

```markdown
- Phase 2 local growth and pack management implementation plan: `docs/superpowers/plans/2026-05-11-android-replica-phase2-local-growth-pack.md`
```

- [ ] **Step 3: Run docs sanity scan**

Run:

```bash
rg -n "T[B]D|T[O]DO|implemen[t] later|fil[l] in|placeholde[r]|Simila[r] to|appropriat[e]" docs/superpowers/plans/2026-05-11-android-replica-phase2-local-growth-pack.md .cursor/android-dev-commands.md docs/android-replica/00-index.md
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add .cursor/android-dev-commands.md docs/android-replica/00-index.md docs/superpowers/plans/2026-05-11-android-replica-phase2-local-growth-pack.md
git commit -m "docs(android): add phase2 implementation plan"
```

## Acceptance Checklist

- [ ] Home chip row is driven by `PackSelectionStore.activePackIds`.
- [ ] Battle starts with the selected `WordPack.words`, not `BattleEngine.demoWords`.
- [ ] Result awards local coins through `CoinAccount` and respects the daily cap.
- [ ] Perfect zero-wrong runs update pack rotation state.
- [ ] PackManager can activate, deactivate, and pin packs offline.
- [ ] Wishlist can redeem a default wish, deduct coins, and append history.
- [ ] MonsterCodex renders copied game assets or an explicit temporary icon fallback that is replaced during visual pass.
- [ ] TodayPlan reads active packs and learning stats without mutating battle state.
- [ ] LearningReport rows are pack keyed and active rows render first.
- [ ] JVM tests cover pack, selection, recorder, report, plan, and growth rules.
- [ ] Compose UI tests cover PackManager, Wishlist, MonsterCodex, TodayPlan, and LearningReport entry points.
- [ ] Screenshots exist under `assets/screenshots/android/` and have been compared against the HarmonyOS references.
- [ ] No runtime code has been added under `shared/`.
