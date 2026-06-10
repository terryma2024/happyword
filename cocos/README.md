# WordMagicBattle (Cocos Creator 3.8)

Battle presentation layer for WordMagicGame. Logic stays in the native clients;
this project renders the battle scene and reports user input over the JSB bridge.
Contract: `shared/contracts/cocos-battle-bridge/`.

## Requirements
- Cocos Creator 3.8.x (Cocos Dashboard)
- node 18+ (`npm install` for tests)

## Commands
- Unit tests (pure TS, no editor): `npm test`
- iOS build: open in Cocos Creator → Project → Build → platform iOS,
  output `build/ios` (gitignored). See "iOS embed" below.

## iOS embed
(filled in by the Phase 0 spike — keep updated)
