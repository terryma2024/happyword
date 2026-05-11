# Android Replica Phase 4 Debug Preview Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add debug-only Android DevMenu, backend environment selection, preview manifest selection, bypass secret storage, and routing/header providers.

**Architecture:** Keep debug routing as local Android code, not shared runtime. API clients read one `BackendURLProvider`; debug UI mutates a `BackendEnvironmentStore`; release builds keep provider abstractions but do not render DevMenu or BypassSecret navigation.

**Tech Stack:** Kotlin, Jetpack Compose Material3, SharedPreferences/app-private storage, JUnit4, Compose UI tests.

---

## Tasks

- [ ] Create `core/DebugRouting.kt` with `BackendEnv`, `BackendEnvironmentStore`, `BackendURLProvider`, `BackendHeaderProvider`, `PreviewManifestClient`, `BypassSecretStore`, and `DevMenuViewModel`.
- [ ] Create JVM tests for precedence, bypass header preview-only behavior, manifest parsing, secret save/clear, and view-model refresh/probe.
- [ ] Create `data/AndroidDebugRoutingRepository.kt`.
- [ ] Create `ui/Phase4Screens.kt` with `DevMenuScreen` and `BypassSecretScreen`.
- [ ] Wire debug-only `ConfigDeveloperRow`, `DevMenu`, and `BypassSecret` routes in `MainActivity`.
- [ ] Add Compose UI test opening DevMenu, selecting preview, saving bypass secret, and checking routing summary.
- [ ] Run `cd android && ./gradlew testDebugUnitTest assembleDebug connectedDebugAndroidTest`.

## Acceptance Checklist

- [ ] Debug build Config exposes Developer row.
- [ ] DevMenu shows effective backend URL and preview rows after refresh.
- [ ] Selecting a preview updates routing summary.
- [ ] Bypass secret save/clear works locally.
- [ ] Header provider attaches bypass secret only to preview routes.
- [ ] Release build UI path is guarded by `BuildConfig.DEBUG`.
