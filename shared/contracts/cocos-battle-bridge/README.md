# Cocos battle bridge contract (v1)

Message contract between a native battle host (Swift today; ArkTS/Kotlin later)
and the Cocos battle scene (`cocos/`). The native side owns ALL battle logic
(engine, timer, audio, records); the scene is presentation + input only.

## Transport

- iOS: Cocos `JsbBridgeWrapper`, events `wmBattleToScript` (native → script)
  and `wmBattleToNative` (script → native); the event argument is the JSON
  envelope below as a string.

## Envelope

```json
{ "v": 1, "type": "<message-type>", "payload": { } }
```

- `v` is the protocol version. Payloads are additive within `v:1` — receivers
  must ignore unknown payload fields.
- Unknown `type` values are ignored with a warning log on both sides.

## Messages

Native → script: `battle/init`, `battle/state`, `battle/question`,
`battle/animation`, `battle/bossIntro`, `battle/end`, `battle/ping` (debug).

Script → native: `battle/ready`, `battle/submitOption`, `battle/spellWrongTap`,
`battle/speakAnswer`, `battle/escape`, `battle/pong` (debug).

Payload shapes: `battle-bridge.schema.json` (JSON Schema draft-07).
Reference implementations: `cocos/assets/scripts/bridge/messages.ts` and
`ios/WordMagicGame/Core/CocosBattleBridgeMessage.swift`.

## Fixtures

`shared/fixtures/cocos-battle-bridge/*.json` — one realistic example per
message type. Both ends decode every fixture in their test suites
(`cocos/tests/messages.test.ts`, `WordMagicGameTests/CocosBattleBridgeMessageTests`),
so a contract change that breaks either side fails its tests.

## Flow

1. Scene loads → script sends `battle/ready`.
2. Native replies `battle/init`, then `battle/state` + `battle/question`
   (and `battle/bossIntro` when the current monster has an intro).
3. User taps an option → `battle/submitOption` → native runs the engine and
   replies `battle/animation` + `battle/state`, then `battle/question` for the
   next question (no animation message for fill-letter-medium step advances).
4. Battle end: native sends `battle/end`; the scene locks input; native routes
   to its result page.
5. Re-entry after the first battle: native sends `battle/init` directly
   (the scene must treat `battle/init` as a full reset).
