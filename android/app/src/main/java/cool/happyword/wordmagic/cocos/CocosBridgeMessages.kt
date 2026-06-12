package cool.happyword.wordmagic.cocos

import org.json.JSONArray
import org.json.JSONObject

/**
 * Kotlin bridge codec for the Cocos battle scene ↔ native host channel.
 *
 * Contract: shared/contracts/cocos-battle-bridge/battle-bridge.schema.json
 * Envelope: { v: 1, type: string, payload: object }
 *
 * Ported from cocos/assets/scripts/bridge/messages.ts and its ArkTS twin
 * harmonyos/entry/src/main/ets/services/CocosBridgeMessages.ets — same type
 * strings, same payload field names and optionality, same version check logic.
 *
 * Naming conventions:
 *   encodeX(...)         → String  — native→scene messages (native encodes)
 *   decodeSceneMessage() → SceneMessage? — scene→native (native decodes)
 */
object CocosBridgeMessages {

    // ── Type-string constants ─────────────────────────────────────────────────

    private const val TYPE_INIT = "battle/init"
    private const val TYPE_STATE = "battle/state"
    private const val TYPE_QUESTION = "battle/question"
    private const val TYPE_ANIMATION = "battle/animation"
    private const val TYPE_BOSS_INTRO = "battle/bossIntro"
    private const val TYPE_END = "battle/end"
    private const val TYPE_PING = "battle/ping"

    private const val TYPE_READY = "battle/ready"
    private const val TYPE_SUBMIT_OPTION = "battle/submitOption"
    private const val TYPE_SPELL_WRONG_TAP = "battle/spellWrongTap"
    private const val TYPE_SPEAK_ANSWER = "battle/speakAnswer"
    private const val TYPE_ESCAPE = "battle/escape"
    private const val TYPE_PONG = "battle/pong"

    /** All message types that the scene sends to native (scene→native direction). */
    val SCENE_TYPES: Set<String> = setOf(
        TYPE_READY,
        TYPE_SUBMIT_OPTION,
        TYPE_SPELL_WRONG_TAP,
        TYPE_SPEAK_ANSWER,
        TYPE_ESCAPE,
        TYPE_PONG,
    )

    // ── Discriminated union: scene→native ─────────────────────────────────────

    sealed class SceneMessage {
        /** battle/ready — scene is initialized and ready for game data. */
        object Ready : SceneMessage()

        /** battle/submitOption — player selected an answer option. */
        data class SubmitOption(val option: String) : SceneMessage()

        /** battle/spellWrongTap — player tapped a wrong letter in spell mode. */
        object SpellWrongTap : SceneMessage()

        /** battle/speakAnswer — player requested TTS pronunciation. */
        object SpeakAnswer : SceneMessage()

        /** battle/escape — player tapped the exit / back control. */
        object Escape : SceneMessage()

        /** battle/pong — reply to a ping from native. */
        data class Pong(val echo: String) : SceneMessage()
    }

    // ── Scene→Native decoder ──────────────────────────────────────────────────

    /**
     * Parse a JSON string sent by the Cocos battle scene to native.
     * Returns null for non-JSON, wrong version, unknown type, or any other
     * invalid input (JSON null, JSON true, etc.).
     */
    fun decodeSceneMessage(json: String): SceneMessage? {
        val obj: JSONObject = try {
            JSONObject(json)
        } catch (_: Exception) {
            return null
        }
        if (obj.optInt("v", -1) != 1) return null
        val type = obj.optString("type", "") ?: return null
        if (!SCENE_TYPES.contains(type)) return null
        val payload = obj.optJSONObject("payload") ?: JSONObject()
        return when (type) {
            TYPE_READY -> SceneMessage.Ready
            TYPE_SUBMIT_OPTION -> SceneMessage.SubmitOption(
                option = payload.optString("option", ""),
            )
            TYPE_SPELL_WRONG_TAP -> SceneMessage.SpellWrongTap
            TYPE_SPEAK_ANSWER -> SceneMessage.SpeakAnswer
            TYPE_ESCAPE -> SceneMessage.Escape
            TYPE_PONG -> SceneMessage.Pong(
                echo = payload.optString("echo", ""),
            )
            else -> null
        }
    }

    // ── Native→Scene encoders ─────────────────────────────────────────────────

    /** Encode a battle/init message (native→scene). */
    fun encodeInit(
        playerMaxHp: Int,
        monsterMaxHp: Int,
        monstersTotal: Int,
        startingSeconds: Int,
        playerArtIdle: String,
        playerArtFight: String,
        playerArtHurt: String,
    ): String = JSONObject()
        .put("v", 1)
        .put("type", TYPE_INIT)
        .put(
            "payload",
            JSONObject()
                .put("playerMaxHp", playerMaxHp)
                .put("monsterMaxHp", monsterMaxHp)
                .put("monstersTotal", monstersTotal)
                .put("startingSeconds", startingSeconds)
                .put(
                    "playerArt",
                    JSONObject()
                        .put("idle", playerArtIdle)
                        .put("fight", playerArtFight)
                        .put("hurt", playerArtHurt),
                ),
        )
        .toString()

    /** Encode a battle/state message (native→scene). */
    fun encodeState(
        playerHp: Int,
        playerMaxHp: Int,
        monsterHp: Int,
        monsterMaxHp: Int,
        monsterIndex: Int,
        monstersTotal: Int,
        remainingSeconds: Int,
        comboCount: Int,
        status: String,
        monsterCatalogIndex: Int,
        monsterImageKey: String,
        monsterName: String,
        monsterLevelLabel: String,
        monsterBonus: Boolean,
    ): String = JSONObject()
        .put("v", 1)
        .put("type", TYPE_STATE)
        .put(
            "payload",
            JSONObject()
                .put("playerHp", playerHp)
                .put("playerMaxHp", playerMaxHp)
                .put("monsterHp", monsterHp)
                .put("monsterMaxHp", monsterMaxHp)
                .put("monsterIndex", monsterIndex)
                .put("monstersTotal", monstersTotal)
                .put("remainingSeconds", remainingSeconds)
                .put("comboCount", comboCount)
                .put("status", status)
                .put(
                    "monster",
                    JSONObject()
                        .put("catalogIndex", monsterCatalogIndex)
                        .put("imageKey", monsterImageKey)
                        .put("name", monsterName)
                        .put("levelLabel", monsterLevelLabel)
                        .put("bonus", monsterBonus),
                ),
        )
        .toString()

    /** Encode a battle/question message (native→scene). All fields required. */
    @Suppress("LongParameterList")
    fun encodeQuestion(
        wordId: String,
        kind: String,
        promptZh: String,
        answer: String,
        options: List<String>,
        letterTemplate: String,
        missingIndex: Int,
        letterOptions: List<String>,
        letterAnswer: String,
        letterTemplateBase: String,
        missingIndices: List<Int>,
        letterOptionsSteps: List<List<String>>,
        letterAnswers: List<String>,
        currentStep: Int,
        spellLetters: List<String>,
        spellRevealedMask: List<Boolean>,
        spellPool: List<String>,
        sentenceTemplate: String,
        sentenceZh: String,
    ): String {
        val stepsArr = JSONArray()
        for (step in letterOptionsSteps) {
            val inner = JSONArray()
            for (s in step) inner.put(s)
            stepsArr.put(inner)
        }
        val payload = JSONObject()
            .put("wordId", wordId)
            .put("kind", kind)
            .put("promptZh", promptZh)
            .put("answer", answer)
            .put("options", JSONArray(options))
            .put("letterTemplate", letterTemplate)
            .put("missingIndex", missingIndex)
            .put("letterOptions", JSONArray(letterOptions))
            .put("letterAnswer", letterAnswer)
            .put("letterTemplateBase", letterTemplateBase)
            .put("missingIndices", JSONArray(missingIndices))
            .put("letterOptionsSteps", stepsArr)
            .put("letterAnswers", JSONArray(letterAnswers))
            .put("currentStep", currentStep)
            .put("spellLetters", JSONArray(spellLetters))
            .put("spellRevealedMask", JSONArray(spellRevealedMask))
            .put("spellPool", JSONArray(spellPool))
            .put("sentenceTemplate", sentenceTemplate)
            .put("sentenceZh", sentenceZh)
        return JSONObject()
            .put("v", 1)
            .put("type", TYPE_QUESTION)
            .put("payload", payload)
            .toString()
    }

    /** Encode a battle/animation message (native→scene). */
    @Suppress("LongParameterList")
    fun encodeAnimation(
        projectileDirection: String,
        projectileIntensity: Int,
        projectileLabel: String,
        playerMotion: String,
        monsterMotion: String,
        feedbackText: String,
        showsCritOverlay: Boolean,
        damageLabel: String,
        playsMonsterDefeatCue: Boolean,
        correct: Boolean,
        comboTriggered: Boolean,
        battleEnded: Boolean,
    ): String = JSONObject()
        .put("v", 1)
        .put("type", TYPE_ANIMATION)
        .put(
            "payload",
            JSONObject()
                .put("projectileDirection", projectileDirection)
                .put("projectileIntensity", projectileIntensity)
                .put("projectileLabel", projectileLabel)
                .put("playerMotion", playerMotion)
                .put("monsterMotion", monsterMotion)
                .put("feedbackText", feedbackText)
                .put("showsCritOverlay", showsCritOverlay)
                .put("damageLabel", damageLabel)
                .put("playsMonsterDefeatCue", playsMonsterDefeatCue)
                .put("correct", correct)
                .put("comboTriggered", comboTriggered)
                .put("battleEnded", battleEnded),
        )
        .toString()

    /** Encode a battle/bossIntro message (native→scene). */
    fun encodeBossIntro(
        monsterIndex: Int,
        name: String,
        introLineEn: String,
        introLineZh: String,
    ): String = JSONObject()
        .put("v", 1)
        .put("type", TYPE_BOSS_INTRO)
        .put(
            "payload",
            JSONObject()
                .put("monsterIndex", monsterIndex)
                .put("name", name)
                .put("introLineEn", introLineEn)
                .put("introLineZh", introLineZh),
        )
        .toString()

    /** Encode a battle/end message (native→scene). */
    fun encodeEnd(status: String): String = JSONObject()
        .put("v", 1)
        .put("type", TYPE_END)
        .put("payload", JSONObject().put("status", status))
        .toString()

    /** Encode a battle/ping message (native→scene). */
    fun encodePing(echo: String): String = JSONObject()
        .put("v", 1)
        .put("type", TYPE_PING)
        .put("payload", JSONObject().put("echo", echo))
        .toString()
}
