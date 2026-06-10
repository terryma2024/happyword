#include <TargetConditionals.h>

#if !TARGET_OS_SIMULATOR

// Replaces the generated cocos/native/engine/common/Classes/Game.cpp so the
// host app does not depend on editor-generated sources. CC_REGISTER_APPLICATION
// provides the factory the engine resolves at startup.
#include "WMCocosEnginePrelude.h"

#include "cocos/cocos.h"

class Game : public cc::BaseGame {
public:
    Game() = default;

    int init() override {
        _windowInfo.title = "WordMagicBattle";
        _debuggerInfo.enabled = false;
        // Script encryption is disabled in the cocos build config.
        _xxteaKey = "";
        BaseGame::init();
        return 0;
    }
};

CC_REGISTER_APPLICATION(Game);

#endif
