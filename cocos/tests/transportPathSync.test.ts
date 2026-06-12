// transportPathSync.test.ts
//
// Guards the invariant that ARKTS_RECEIVER_CLS_PATH (used at runtime by the
// Cocos scene to call native.reflection.callStaticMethod) stays in sync with:
//   1. The actual ArkTS source file on disk (so napi_load_module_with_info
//      finds the module).
//   2. The runtimeOnly.sources list in harmonyos/entry/build-profile.json5
//      (so hvigor includes the module in the HAP).
//
// transport.ts imports 'cc' which is not available in the vitest headless
// environment, so we extract ARKTS_RECEIVER_CLS_PATH from the source text
// rather than importing it. The regex targets the exported const assignment
// so a rename or value change will cause this test to fail and remind the
// author to update both sides.
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

// Repo root is two levels up from cocos/
const REPO_ROOT = join(__dirname, '../../');

const TRANSPORT_SRC = join(
    REPO_ROOT,
    'cocos/assets/scripts/bridge/transport.ts',
);

function extractReceiverClsPath(): string {
    const src = readFileSync(TRANSPORT_SRC, 'utf8');
    // Matches: export const ARKTS_RECEIVER_CLS_PATH = '...';
    const m = src.match(/export\s+const\s+ARKTS_RECEIVER_CLS_PATH\s*=\s*'([^']+)'/);
    if (!m) {
        throw new Error(
            'Could not find exported ARKTS_RECEIVER_CLS_PATH in transport.ts — '
            + 'was it renamed or made non-exported?',
        );
    }
    return m[1];
}

describe('ARKTS_RECEIVER_CLS_PATH sync', () => {
    it('ARKTS_RECEIVER_CLS_PATH is exported from transport.ts', () => {
        // extractReceiverClsPath() throws if the export is missing.
        const path = extractReceiverClsPath();
        expect(typeof path).toBe('string');
        expect(path.length).toBeGreaterThan(0);
    });

    it('receiver .ets file exists at the path implied by ARKTS_RECEIVER_CLS_PATH', () => {
        const clsPath = extractReceiverClsPath();
        // ARKTS_RECEIVER_CLS_PATH uses the napi_load_module_with_info form
        // which starts from the module name: 'entry/src/main/ets/services/...'
        // So relative to the harmonyos/ directory the file is at
        // harmonyos/<clsPath>.ets
        const resolvedPath = join(REPO_ROOT, 'harmonyos', `${clsPath}.ets`);
        expect(
            existsSync(resolvedPath),
            `Expected receiver file to exist at: ${resolvedPath}`,
        ).toBe(true);
    });

    it('build-profile.json5 mentions CocosBridgeReceiver.ets in runtimeOnly.sources', () => {
        const buildProfilePath = join(
            REPO_ROOT,
            'harmonyos/entry/build-profile.json5',
        );
        const content = readFileSync(buildProfilePath, 'utf8');
        expect(
            content.includes('services/CocosBridgeReceiver.ets'),
            'build-profile.json5 must list CocosBridgeReceiver.ets under '
            + 'buildOption.arkOptions.runtimeOnly.sources',
        ).toBe(true);
    });
});
