package cool.happyword.wordmagic.cocos

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class CocosBridgeMessagesTest {

    // ── Fixture loading ───────────────────────────────────────────────────────

    private fun fixturesDir(): File {
        var dir = File(System.getProperty("user.dir"))
        while (!File(dir, "shared/fixtures/cocos-battle-bridge").isDirectory) {
            dir = dir.parentFile ?: error("fixtures dir not found above ${System.getProperty("user.dir")}")
        }
        return File(dir, "shared/fixtures/cocos-battle-bridge")
    }

    private fun fixture(name: String): String =
        File(fixturesDir(), "$name.json").readText()

    // ── Deep equality (key-order-insensitive) ─────────────────────────────────

    private fun jsonDeepEqual(a: Any?, b: Any?): Boolean {
        if (a === b) return true
        if (a == null || b == null) return false
        if (a is JSONObject && b is JSONObject) {
            if (a.length() != b.length()) return false
            for (key in a.keys()) {
                if (!b.has(key)) return false
                if (!jsonDeepEqual(a.get(key), b.get(key))) return false
            }
            return true
        }
        if (a is JSONArray && b is JSONArray) {
            if (a.length() != b.length()) return false
            for (i in 0 until a.length()) {
                if (!jsonDeepEqual(a.get(i), b.get(i))) return false
            }
            return true
        }
        return a == b
    }

    private fun assertJsonDeepEqual(expected: String, actual: String) {
        val expObj = JSONObject(expected)
        val actObj = JSONObject(actual)
        assertTrue(
            "JSON trees differ.\nExpected: $expected\nActual:   $actual",
            jsonDeepEqual(expObj, actObj),
        )
    }

    // ── All-fixtures gate ─────────────────────────────────────────────────────

    @Test
    fun allFixturesGate_exactly19Files() {
        val files = fixturesDir().listFiles { f -> f.extension == "json" } ?: emptyArray()
        assertEquals(19, files.size)
    }

    @Test
    fun allFixturesGate_eachDecodeOrRoundTrips() {
        val files = fixturesDir().listFiles { f -> f.extension == "json" }!!
            .sortedBy { it.name }
        var processed = 0
        for (file in files) {
            val raw = file.readText()
            val envelope = JSONObject(raw)
            val msgType = envelope.getString("type")
            when {
                CocosBridgeMessages.SCENE_TYPES.contains(msgType) -> {
                    val decoded = CocosBridgeMessages.decodeSceneMessage(raw)
                    assertNotNull("Expected decode of $msgType from ${file.name}", decoded)
                    processed++
                }
                msgType == "battle/init" -> {
                    val p = envelope.getJSONObject("payload")
                    val art = p.getJSONObject("playerArt")
                    val encoded = CocosBridgeMessages.encodeInit(
                        playerMaxHp = p.getInt("playerMaxHp"),
                        monsterMaxHp = p.getInt("monsterMaxHp"),
                        monstersTotal = p.getInt("monstersTotal"),
                        startingSeconds = p.getInt("startingSeconds"),
                        playerArtIdle = art.getString("idle"),
                        playerArtFight = art.getString("fight"),
                        playerArtHurt = art.getString("hurt"),
                    )
                    assertJsonDeepEqual(raw, encoded)
                    processed++
                }
                msgType == "battle/state" -> {
                    val p = envelope.getJSONObject("payload")
                    val m = p.getJSONObject("monster")
                    val encoded = CocosBridgeMessages.encodeState(
                        playerHp = p.getInt("playerHp"),
                        playerMaxHp = p.getInt("playerMaxHp"),
                        monsterHp = p.getInt("monsterHp"),
                        monsterMaxHp = p.getInt("monsterMaxHp"),
                        monsterIndex = p.getInt("monsterIndex"),
                        monstersTotal = p.getInt("monstersTotal"),
                        remainingSeconds = p.getInt("remainingSeconds"),
                        comboCount = p.getInt("comboCount"),
                        status = p.getString("status"),
                        monsterCatalogIndex = m.getInt("catalogIndex"),
                        monsterImageKey = m.getString("imageKey"),
                        monsterName = m.getString("name"),
                        monsterLevelLabel = m.getString("levelLabel"),
                        monsterBonus = m.getBoolean("bonus"),
                    )
                    assertJsonDeepEqual(raw, encoded)
                    processed++
                }
                msgType == "battle/question" -> {
                    val p = envelope.getJSONObject("payload")
                    val encoded = CocosBridgeMessages.encodeQuestion(
                        wordId = p.getString("wordId"),
                        kind = p.getString("kind"),
                        promptZh = p.getString("promptZh"),
                        answer = p.getString("answer"),
                        options = jsonArrayToStringList(p.getJSONArray("options")),
                        letterTemplate = p.getString("letterTemplate"),
                        missingIndex = p.getInt("missingIndex"),
                        letterOptions = jsonArrayToStringList(p.getJSONArray("letterOptions")),
                        letterAnswer = p.getString("letterAnswer"),
                        letterTemplateBase = p.getString("letterTemplateBase"),
                        missingIndices = jsonArrayToIntList(p.getJSONArray("missingIndices")),
                        letterOptionsSteps = jsonArrayToStringListList(p.getJSONArray("letterOptionsSteps")),
                        letterAnswers = jsonArrayToStringList(p.getJSONArray("letterAnswers")),
                        currentStep = p.getInt("currentStep"),
                        spellLetters = jsonArrayToStringList(p.getJSONArray("spellLetters")),
                        spellRevealedMask = jsonArrayToBooleanList(p.getJSONArray("spellRevealedMask")),
                        spellPool = jsonArrayToStringList(p.getJSONArray("spellPool")),
                        sentenceTemplate = p.getString("sentenceTemplate"),
                        sentenceZh = p.getString("sentenceZh"),
                    )
                    assertJsonDeepEqual(raw, encoded)
                    processed++
                }
                msgType == "battle/animation" -> {
                    val p = envelope.getJSONObject("payload")
                    val encoded = CocosBridgeMessages.encodeAnimation(
                        projectileDirection = p.getString("projectileDirection"),
                        projectileIntensity = p.getInt("projectileIntensity"),
                        projectileLabel = p.getString("projectileLabel"),
                        playerMotion = p.getString("playerMotion"),
                        monsterMotion = p.getString("monsterMotion"),
                        feedbackText = p.getString("feedbackText"),
                        showsCritOverlay = p.getBoolean("showsCritOverlay"),
                        damageLabel = p.getString("damageLabel"),
                        playsMonsterDefeatCue = p.getBoolean("playsMonsterDefeatCue"),
                        correct = p.getBoolean("correct"),
                        comboTriggered = p.getBoolean("comboTriggered"),
                        battleEnded = p.getBoolean("battleEnded"),
                    )
                    assertJsonDeepEqual(raw, encoded)
                    processed++
                }
                msgType == "battle/bossIntro" -> {
                    val p = envelope.getJSONObject("payload")
                    val encoded = CocosBridgeMessages.encodeBossIntro(
                        monsterIndex = p.getInt("monsterIndex"),
                        name = p.getString("name"),
                        introLineEn = p.getString("introLineEn"),
                        introLineZh = p.getString("introLineZh"),
                    )
                    assertJsonDeepEqual(raw, encoded)
                    processed++
                }
                msgType == "battle/end" -> {
                    val p = envelope.getJSONObject("payload")
                    val encoded = CocosBridgeMessages.encodeEnd(status = p.getString("status"))
                    assertJsonDeepEqual(raw, encoded)
                    processed++
                }
                msgType == "battle/ping" -> {
                    val p = envelope.getJSONObject("payload")
                    val encoded = CocosBridgeMessages.encodePing(echo = p.getString("echo"))
                    assertJsonDeepEqual(raw, encoded)
                    processed++
                }
            }
        }
        assertEquals("Not all 19 fixtures were processed", files.size, processed)
    }

    // ── JSON array helpers ────────────────────────────────────────────────────

    private fun jsonArrayToStringList(arr: JSONArray): List<String> =
        (0 until arr.length()).map { arr.getString(it) }

    private fun jsonArrayToIntList(arr: JSONArray): List<Int> =
        (0 until arr.length()).map { arr.getInt(it) }

    private fun jsonArrayToBooleanList(arr: JSONArray): List<Boolean> =
        (0 until arr.length()).map { arr.getBoolean(it) }

    private fun jsonArrayToStringListList(arr: JSONArray): List<List<String>> =
        (0 until arr.length()).map { jsonArrayToStringList(arr.getJSONArray(it)) }

    // ── Scene→Native decode: per-type tests ──────────────────────────────────

    @Test
    fun decodesSceneReady() {
        val msg = CocosBridgeMessages.decodeSceneMessage(fixture("ready"))
        assertNotNull(msg)
        assertTrue(msg is CocosBridgeMessages.SceneMessage.Ready)
    }

    @Test
    fun decodesSceneSubmitOption() {
        val raw = fixture("submit-option")
        val msg = CocosBridgeMessages.decodeSceneMessage(raw)
        assertNotNull(msg)
        assertTrue(msg is CocosBridgeMessages.SceneMessage.SubmitOption)
        val submitMsg = msg as CocosBridgeMessages.SceneMessage.SubmitOption
        val fix = JSONObject(raw)
        assertEquals(fix.getJSONObject("payload").getString("option"), submitMsg.option)
    }

    @Test
    fun decodesSceneSpellWrongTap() {
        val msg = CocosBridgeMessages.decodeSceneMessage(fixture("spell-wrong-tap"))
        assertNotNull(msg)
        assertTrue(msg is CocosBridgeMessages.SceneMessage.SpellWrongTap)
    }

    @Test
    fun decodesSceneSpeakAnswer() {
        val msg = CocosBridgeMessages.decodeSceneMessage(fixture("speak-answer"))
        assertNotNull(msg)
        assertTrue(msg is CocosBridgeMessages.SceneMessage.SpeakAnswer)
    }

    @Test
    fun decodesSceneEscape() {
        val msg = CocosBridgeMessages.decodeSceneMessage(fixture("escape"))
        assertNotNull(msg)
        assertTrue(msg is CocosBridgeMessages.SceneMessage.Escape)
    }

    @Test
    fun decodesScenePong() {
        val raw = fixture("pong")
        val msg = CocosBridgeMessages.decodeSceneMessage(raw)
        assertNotNull(msg)
        assertTrue(msg is CocosBridgeMessages.SceneMessage.Pong)
        val pongMsg = msg as CocosBridgeMessages.SceneMessage.Pong
        val fix = JSONObject(raw)
        assertEquals(fix.getJSONObject("payload").getString("echo"), pongMsg.echo)
    }

    // ── Native→Scene round-trips: per-type tests ──────────────────────────────

    @Test
    fun roundTripsInit() {
        val raw = fixture("init")
        val p = JSONObject(raw).getJSONObject("payload")
        val art = p.getJSONObject("playerArt")
        val encoded = CocosBridgeMessages.encodeInit(
            playerMaxHp = p.getInt("playerMaxHp"),
            monsterMaxHp = p.getInt("monsterMaxHp"),
            monstersTotal = p.getInt("monstersTotal"),
            startingSeconds = p.getInt("startingSeconds"),
            playerArtIdle = art.getString("idle"),
            playerArtFight = art.getString("fight"),
            playerArtHurt = art.getString("hurt"),
        )
        assertJsonDeepEqual(raw, encoded)
    }

    @Test
    fun roundTripsState() {
        val raw = fixture("state")
        val p = JSONObject(raw).getJSONObject("payload")
        val m = p.getJSONObject("monster")
        val encoded = CocosBridgeMessages.encodeState(
            playerHp = p.getInt("playerHp"),
            playerMaxHp = p.getInt("playerMaxHp"),
            monsterHp = p.getInt("monsterHp"),
            monsterMaxHp = p.getInt("monsterMaxHp"),
            monsterIndex = p.getInt("monsterIndex"),
            monstersTotal = p.getInt("monstersTotal"),
            remainingSeconds = p.getInt("remainingSeconds"),
            comboCount = p.getInt("comboCount"),
            status = p.getString("status"),
            monsterCatalogIndex = m.getInt("catalogIndex"),
            monsterImageKey = m.getString("imageKey"),
            monsterName = m.getString("name"),
            monsterLevelLabel = m.getString("levelLabel"),
            monsterBonus = m.getBoolean("bonus"),
        )
        assertJsonDeepEqual(raw, encoded)
    }

    @Test
    fun roundTripsQuestionChoice() {
        roundTripsQuestion("question-choice")
    }

    @Test
    fun roundTripsQuestionFillLetter() {
        roundTripsQuestion("question-fill-letter")
    }

    @Test
    fun roundTripsQuestionFillLetterMedium() {
        roundTripsQuestion("question-fill-letter-medium")
    }

    @Test
    fun roundTripsQuestionSpell() {
        roundTripsQuestion("question-spell")
    }

    @Test
    fun roundTripsQuestionSentenceCloze() {
        roundTripsQuestion("question-sentence-cloze")
    }

    private fun roundTripsQuestion(fixtureName: String) {
        val raw = fixture(fixtureName)
        val p = JSONObject(raw).getJSONObject("payload")
        val encoded = CocosBridgeMessages.encodeQuestion(
            wordId = p.getString("wordId"),
            kind = p.getString("kind"),
            promptZh = p.getString("promptZh"),
            answer = p.getString("answer"),
            options = jsonArrayToStringList(p.getJSONArray("options")),
            letterTemplate = p.getString("letterTemplate"),
            missingIndex = p.getInt("missingIndex"),
            letterOptions = jsonArrayToStringList(p.getJSONArray("letterOptions")),
            letterAnswer = p.getString("letterAnswer"),
            letterTemplateBase = p.getString("letterTemplateBase"),
            missingIndices = jsonArrayToIntList(p.getJSONArray("missingIndices")),
            letterOptionsSteps = jsonArrayToStringListList(p.getJSONArray("letterOptionsSteps")),
            letterAnswers = jsonArrayToStringList(p.getJSONArray("letterAnswers")),
            currentStep = p.getInt("currentStep"),
            spellLetters = jsonArrayToStringList(p.getJSONArray("spellLetters")),
            spellRevealedMask = jsonArrayToBooleanList(p.getJSONArray("spellRevealedMask")),
            spellPool = jsonArrayToStringList(p.getJSONArray("spellPool")),
            sentenceTemplate = p.getString("sentenceTemplate"),
            sentenceZh = p.getString("sentenceZh"),
        )
        assertJsonDeepEqual(raw, encoded)
    }

    @Test
    fun roundTripsAnimationCorrect() {
        roundTripsAnimation("animation-correct")
    }

    @Test
    fun roundTripsAnimationCombo() {
        roundTripsAnimation("animation-combo")
    }

    @Test
    fun roundTripsAnimationWrong() {
        roundTripsAnimation("animation-wrong")
    }

    private fun roundTripsAnimation(fixtureName: String) {
        val raw = fixture(fixtureName)
        val p = JSONObject(raw).getJSONObject("payload")
        val encoded = CocosBridgeMessages.encodeAnimation(
            projectileDirection = p.getString("projectileDirection"),
            projectileIntensity = p.getInt("projectileIntensity"),
            projectileLabel = p.getString("projectileLabel"),
            playerMotion = p.getString("playerMotion"),
            monsterMotion = p.getString("monsterMotion"),
            feedbackText = p.getString("feedbackText"),
            showsCritOverlay = p.getBoolean("showsCritOverlay"),
            damageLabel = p.getString("damageLabel"),
            playsMonsterDefeatCue = p.getBoolean("playsMonsterDefeatCue"),
            correct = p.getBoolean("correct"),
            comboTriggered = p.getBoolean("comboTriggered"),
            battleEnded = p.getBoolean("battleEnded"),
        )
        assertJsonDeepEqual(raw, encoded)
    }

    @Test
    fun roundTripsBossIntro() {
        val raw = fixture("boss-intro")
        val p = JSONObject(raw).getJSONObject("payload")
        val encoded = CocosBridgeMessages.encodeBossIntro(
            monsterIndex = p.getInt("monsterIndex"),
            name = p.getString("name"),
            introLineEn = p.getString("introLineEn"),
            introLineZh = p.getString("introLineZh"),
        )
        assertJsonDeepEqual(raw, encoded)
    }

    @Test
    fun roundTripsEnd() {
        val raw = fixture("end")
        val p = JSONObject(raw).getJSONObject("payload")
        val encoded = CocosBridgeMessages.encodeEnd(status = p.getString("status"))
        assertJsonDeepEqual(raw, encoded)
    }

    @Test
    fun roundTripsPing() {
        val raw = fixture("ping")
        val p = JSONObject(raw).getJSONObject("payload")
        val encoded = CocosBridgeMessages.encodePing(echo = p.getString("echo"))
        assertJsonDeepEqual(raw, encoded)
    }

    // ── Field-value spot checks ───────────────────────────────────────────────

    @Test
    fun encodeInitFieldValues() {
        val json = CocosBridgeMessages.encodeInit(
            playerMaxHp = 10,
            monsterMaxHp = 1,
            monstersTotal = 2,
            startingSeconds = 300,
            playerArtIdle = "CharacterMagician",
            playerArtFight = "CharacterMagicianFight",
            playerArtHurt = "CharacterMagicianBeaten",
        )
        val obj = JSONObject(json)
        assertEquals(1, obj.getInt("v"))
        assertEquals("battle/init", obj.getString("type"))
        val p = obj.getJSONObject("payload")
        assertEquals(10, p.getInt("playerMaxHp"))
        assertEquals(1, p.getInt("monsterMaxHp"))
        assertEquals(2, p.getInt("monstersTotal"))
        assertEquals(300, p.getInt("startingSeconds"))
        val art = p.getJSONObject("playerArt")
        assertEquals("CharacterMagician", art.getString("idle"))
        assertEquals("CharacterMagicianFight", art.getString("fight"))
        assertEquals("CharacterMagicianBeaten", art.getString("hurt"))
    }

    @Test
    fun encodeStateFieldValues() {
        val json = CocosBridgeMessages.encodeState(
            playerHp = 9,
            playerMaxHp = 10,
            monsterHp = 1,
            monsterMaxHp = 1,
            monsterIndex = 1,
            monstersTotal = 2,
            remainingSeconds = 297,
            comboCount = 2,
            status = "playing",
            monsterCatalogIndex = 3,
            monsterImageKey = "CharacterSnowGoblin",
            monsterName = "Snow Goblin",
            monsterLevelLabel = "L1",
            monsterBonus = false,
        )
        val obj = JSONObject(json)
        assertEquals("battle/state", obj.getString("type"))
        val p = obj.getJSONObject("payload")
        assertEquals(9, p.getInt("playerHp"))
        assertEquals("playing", p.getString("status"))
        val m = p.getJSONObject("monster")
        assertEquals(3, m.getInt("catalogIndex"))
        assertEquals("CharacterSnowGoblin", m.getString("imageKey"))
    }

    @Test
    fun encodePingFieldValues() {
        val json = CocosBridgeMessages.encodePing("hello")
        val obj = JSONObject(json)
        assertEquals(1, obj.getInt("v"))
        assertEquals("battle/ping", obj.getString("type"))
        assertEquals("hello", obj.getJSONObject("payload").getString("echo"))
    }

    @Test
    fun encodeBossIntroFieldValues() {
        val json = CocosBridgeMessages.encodeBossIntro(
            monsterIndex = 2,
            name = "云眠巨龙",
            introLineEn = "You dare wake me, little wizard?",
            introLineZh = "小法师，你竟敢吵醒我？",
        )
        val obj = JSONObject(json)
        assertEquals(1, obj.getInt("v"))
        assertEquals("battle/bossIntro", obj.getString("type"))
        val p = obj.getJSONObject("payload")
        assertEquals(2, p.getInt("monsterIndex"))
        assertEquals("云眠巨龙", p.getString("name"))
    }

    @Test
    fun encodeEndFieldValues() {
        val json = CocosBridgeMessages.encodeEnd("won")
        val obj = JSONObject(json)
        assertEquals("battle/end", obj.getString("type"))
        assertEquals("won", obj.getJSONObject("payload").getString("status"))
    }

    // ── Error cases ───────────────────────────────────────────────────────────

    @Test
    fun decodeSceneMessageRejectsUnknownType() {
        val result = CocosBridgeMessages.decodeSceneMessage(
            """{"v":1,"type":"battle/unknown","payload":{}}"""
        )
        assertNull(result)
    }

    @Test
    fun decodeSceneMessageRejectsWrongVersion() {
        val result = CocosBridgeMessages.decodeSceneMessage(
            """{"v":2,"type":"battle/ready","payload":{}}"""
        )
        assertNull(result)
    }

    @Test
    fun decodeSceneMessageRejectsNonJson() {
        val result = CocosBridgeMessages.decodeSceneMessage("not json")
        assertNull(result)
    }

    @Test
    fun decodeSceneMessageRejectsJsonNull() {
        val result = CocosBridgeMessages.decodeSceneMessage("null")
        assertNull(result)
    }

    @Test
    fun decodeSceneMessageRejectsJsonTrue() {
        val result = CocosBridgeMessages.decodeSceneMessage("true")
        assertNull(result)
    }
}
