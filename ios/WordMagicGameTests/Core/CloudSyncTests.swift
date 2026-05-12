@testable import WordMagicGame
import Foundation
import XCTest

final class CloudSyncTests: XCTestCase {
    func testCloudClientFactoryKeepsRouteOnlyUITestsOnHTTPClients() {
        XCTAssertFalse(CloudClientFactory.shouldUseLocalMocks(arguments: ["WordMagicGame", "-UITestRouteScanBinding"]))
        XCTAssertFalse(CloudClientFactory.shouldUseLocalMocks(arguments: ["WordMagicGame", "-UITestResetState"]))
        XCTAssertTrue(CloudClientFactory.shouldUseLocalMocks(arguments: ["WordMagicGame", "-UITestMockBinding"]))
        XCTAssertTrue(CloudClientFactory.shouldUseLocalMocks(arguments: ["WordMagicGame", "-UITestSeedBoundDevice"]))
    }

    func testFactoryBindingClientFollowsDeveloperOptionsChangedAfterCreation() async throws {
        let defaults = UserDefaults(suiteName: "FactoryBindingRouting-\(UUID().uuidString)")!
        let environmentStore = BackendEnvironmentStore(defaults: defaults)
        environmentStore.save(environment: .staging)
        let secretStore = BypassSecretStore(defaults: defaults)
        let recorder = RequestURLRecorder()
        let transport = RecordingHTTPTransport { request in
            recorder.append(request.url?.absoluteString)
            return Self.httpResponse(request: request, status: 200, body: Self.pairRedeemFixture)
        }
        let client = CloudClientFactory.bindingClient(
            arguments: ["WordMagicGame"],
            environmentStore: environmentStore,
            bypassSecretStore: secretStore,
            transport: transport
        )

        environmentStore.save(
            environment: .preview,
            previewURL: URL(string: "https://happyword-preview.example.test")!
        )
        _ = try await client.redeem(pairingInput: "123456", deviceId: "device-test")

        XCTAssertEqual(recorder.urls, ["https://happyword-preview.example.test/api/v1/pair/redeem"])
    }

    func testBackendURLProviderUsesOverridePreviewAndFixedEnvironmentPrecedence() {
        let defaults = UserDefaults(suiteName: "BackendRouting-\(UUID().uuidString)")!
        let store = BackendEnvironmentStore(defaults: defaults)

        store.save(environment: .staging)
        XCTAssertEqual(BackendURLProvider(store: store).effectiveBaseURL().absoluteString, "https://happyword.cool")

        store.save(environment: .local)
        XCTAssertEqual(BackendURLProvider(store: store).effectiveBaseURL().absoluteString, "http://127.0.0.1:8000")

        store.save(environment: .preview, previewURL: URL(string: "https://happyword-preview.example.test")!)
        XCTAssertEqual(BackendURLProvider(store: store).effectiveBaseURL().absoluteString, "https://happyword-preview.example.test")

        let provider = BackendURLProvider(
            store: store,
            launchOverrideURL: URL(string: "http://127.0.0.1:8123")!
        )
        XCTAssertEqual(provider.effectiveBaseURL().absoluteString, "http://127.0.0.1:8123")
    }

    func testBackendHeaderProviderAttachesVercelBypassOnlyForPreview() {
        let defaults = UserDefaults(suiteName: "BackendHeaders-\(UUID().uuidString)")!
        let environmentStore = BackendEnvironmentStore(defaults: defaults)
        let secretStore = BypassSecretStore(defaults: defaults)
        let provider = BackendHeaderProvider(environmentStore: environmentStore, secretStore: secretStore)

        secretStore.save("secret-demo")
        environmentStore.save(environment: .staging)
        XCTAssertEqual(provider.headers(), [:])

        environmentStore.save(environment: .preview, previewURL: URL(string: "https://happyword-preview.example.test")!)
        XCTAssertEqual(provider.headers()[BackendHeaderProvider.vercelBypassHeader], "secret-demo")

        secretStore.clear()
        XCTAssertEqual(provider.headers(), [:])
    }

    func testPreviewManifestDecodesSharedFixture() throws {
        let manifest = try JSONDecoder.snakeCase.decode(
            PreviewManifest.self,
            from: Self.sharedFixtureData("public/preview-urls.sample.json")
        )

        XCTAssertEqual(manifest.previews.map(\.number), [55])
        XCTAssertEqual(manifest.previews.first?.branch, "codex/polish_docs")
        XCTAssertEqual(manifest.previews.first?.url.absoluteString, "https://happyword-preview.example.test")
    }

    func testPreviewManifestClientDoesNotAttachPreviewBypassHeader() async throws {
        let defaults = UserDefaults(suiteName: "PreviewManifestHeaders-\(UUID().uuidString)")!
        let environmentStore = BackendEnvironmentStore(defaults: defaults)
        environmentStore.save(environment: .preview, previewURL: URL(string: "https://happyword-preview.example.test")!)
        let secretStore = BypassSecretStore(defaults: defaults)
        secretStore.save("secret-demo")

        let transport = RecordingHTTPTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "https://happyword.cool/api/v1/preview-urls.json")
            XCTAssertNil(request.value(forHTTPHeaderField: BackendHeaderProvider.vercelBypassHeader))
            return Self.httpResponse(request: request, status: 200, body: Self.previewManifestFixture)
        }
        let client = PreviewManifestClient(
            transport: transport,
            headerProvider: BackendHeaderProvider(environmentStore: environmentStore, secretStore: secretStore)
        )

        let manifest = try await client.fetch()

        XCTAssertEqual(manifest.previews.first?.number, 65)
        XCTAssertEqual(manifest.previews.first?.headSha, "24cd43a9988")
        XCTAssertEqual(manifest.previews.first?.updatedAt, "2026-05-12T00:00:00Z")
    }

    @MainActor
    func testDeveloperMenuCardsMatchHarmonyGridOrderAndHighlight() {
        let defaults = UserDefaults(suiteName: "DevMenuCards-\(UUID().uuidString)")!
        let environmentStore = BackendEnvironmentStore(defaults: defaults)
        environmentStore.save(environment: .staging)
        let viewModel = DeveloperMenuViewModel(
            environmentStore: environmentStore,
            bypassSecretStore: BypassSecretStore(defaults: defaults),
            manifestClient: PreviewManifestClient(transport: RecordingHTTPTransport { request in
                Self.httpResponse(request: request, status: 200, body: Self.previewManifestFixture)
            }),
            transport: RecordingHTTPTransport { request in
                Self.httpResponse(request: request, status: 200, body: Data())
            }
        )
        viewModel.manifest = PreviewManifest(previews: [
            PreviewManifestRow(
                number: 65,
                title: "fix(harmony): stabilize UI suite with question type controls",
                branch: "fix/harmony-ui",
                url: URL(string: "https://happyword-git-fix-harmony.vercel.app")!,
                headSha: "24cd43a9988"
            ),
            PreviewManifestRow(
                number: 61,
                title: "feat(server): V0.8.2 system admin console",
                branch: "feat/admin",
                url: URL(string: "https://happyword-git-admin.vercel.app")!,
                headSha: "a1211b8"
            ),
        ])

        let cards = viewModel.cards

        XCTAssertEqual(cards.map(\.id), ["DevMenuLocalCard", "DevMenuStagingCard", "DevMenuPreviewCard_65", "DevMenuPreviewCard_61"])
        XCTAssertEqual(cards.map(\.title), [
            "Local",
            "Staging",
            "fix(harmony): stabilize UI suite with question type controls",
            "feat(server): V0.8.2 system admin console",
        ])
        XCTAssertEqual(cards.map(\.footer), [
            "http://127.0.0.1:8000",
            "https://happyword.cool",
            "#65(24cd43a)",
            "#61(a1211b8)",
        ])
        XCTAssertEqual(cards.map(\.isSelected), [false, true, false, false])
    }

    func testDeveloperMenuLayoutUsesHarmonyCompactLandscapeMetrics() {
        XCTAssertEqual(DeveloperMenuLayoutSpec.titleFontSize, 20)
        XCTAssertEqual(DeveloperMenuLayoutSpec.sectionFontSize, 14)
        XCTAssertEqual(DeveloperMenuLayoutSpec.headerButtonFontSize, 13)
        XCTAssertEqual(DeveloperMenuLayoutSpec.headerButtonHeight, 36)
        XCTAssertEqual(DeveloperMenuLayoutSpec.headerButtonLineLimit, 1)
        XCTAssertEqual(DeveloperMenuLayoutSpec.cardTitleFontSize, 14)
        XCTAssertEqual(DeveloperMenuLayoutSpec.cardFooterFontSize, 13)
        XCTAssertEqual(DeveloperMenuLayoutSpec.cardHeight, 96)
        XCTAssertGreaterThanOrEqual(DeveloperMenuLayoutSpec.refreshButtonMinWidth, 156)
    }

    @MainActor
    func testDeveloperMenuPreviewCardProbeFailureDoesNotPersistPreview() async throws {
        let defaults = UserDefaults(suiteName: "DevMenuPreviewFail-\(UUID().uuidString)")!
        let environmentStore = BackendEnvironmentStore(defaults: defaults)
        environmentStore.save(environment: .staging)
        let secretStore = BypassSecretStore(defaults: defaults)
        secretStore.save("secret-demo")
        let transport = RecordingHTTPTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "https://happyword-git-fail.vercel.app/api/v1/health")
            XCTAssertEqual(request.value(forHTTPHeaderField: BackendHeaderProvider.vercelBypassHeader), "secret-demo")
            return Self.httpResponse(request: request, status: 401, body: Data())
        }
        let viewModel = DeveloperMenuViewModel(
            environmentStore: environmentStore,
            bypassSecretStore: secretStore,
            transport: transport
        )
        viewModel.manifest = PreviewManifest(previews: [
            PreviewManifestRow(number: 65, title: "preview", branch: "branch", url: URL(string: "https://happyword-git-fail.vercel.app")!, headSha: "24cd43a")
        ])

        await viewModel.activate(viewModel.cards[2])

        XCTAssertEqual(environmentStore.environment, .staging)
        XCTAssertNil(environmentStore.previewURL)
        XCTAssertEqual(viewModel.environment, .staging)
        XCTAssertEqual(viewModel.lastProbeStatus, "https://happyword-git-fail.vercel.app/api/v1/health → HTTP 401")
    }

    @MainActor
    func testDeveloperMenuPreviewCardPersistsOnlyAfterSuccessfulProbe() async throws {
        let defaults = UserDefaults(suiteName: "DevMenuPreviewSuccess-\(UUID().uuidString)")!
        let environmentStore = BackendEnvironmentStore(defaults: defaults)
        environmentStore.save(environment: .staging)
        let secretStore = BypassSecretStore(defaults: defaults)
        secretStore.save("secret-demo")
        let transport = RecordingHTTPTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "https://happyword-git-ok.vercel.app/api/v1/health")
            XCTAssertEqual(request.value(forHTTPHeaderField: BackendHeaderProvider.vercelBypassHeader), "secret-demo")
            return Self.httpResponse(request: request, status: 200, body: Data())
        }
        let viewModel = DeveloperMenuViewModel(
            environmentStore: environmentStore,
            bypassSecretStore: secretStore,
            transport: transport
        )
        viewModel.manifest = PreviewManifest(previews: [
            PreviewManifestRow(number: 66, title: "preview", branch: "branch", url: URL(string: "https://happyword-git-ok.vercel.app")!, headSha: "abcdef123")
        ])

        await viewModel.activate(viewModel.cards[2])

        XCTAssertEqual(environmentStore.environment, .preview)
        XCTAssertEqual(environmentStore.previewURL?.absoluteString, "https://happyword-git-ok.vercel.app")
        XCTAssertEqual(viewModel.environment, .preview)
        XCTAssertEqual(viewModel.lastProbeStatus, "https://happyword-git-ok.vercel.app/api/v1/health → HTTP 200")
    }

    @MainActor
    func testDeveloperMenuSuccessfulPreviewActivationReturnsHomeAndShowsToast() async throws {
        let defaults = UserDefaults(suiteName: "DevMenuCoordinatorSuccess-\(UUID().uuidString)")!
        let environmentStore = BackendEnvironmentStore(defaults: defaults)
        environmentStore.save(environment: .staging)
        let secretStore = BypassSecretStore(defaults: defaults)
        secretStore.save("secret-demo")
        let transport = RecordingHTTPTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "https://happyword-git-ok.vercel.app/api/v1/health")
            return Self.httpResponse(request: request, status: 200, body: Data())
        }
        let viewModel = DeveloperMenuViewModel(
            environmentStore: environmentStore,
            bypassSecretStore: secretStore,
            transport: transport
        )
        viewModel.manifest = PreviewManifest(previews: [
            PreviewManifestRow(number: 66, title: "preview", branch: "branch", url: URL(string: "https://happyword-git-ok.vercel.app")!, headSha: "abcdef123")
        ])
        let coordinator = AppCoordinator(developerMenuViewModel: viewModel)
        coordinator.route = .devMenu

        await coordinator.activateDeveloperMenuCard(viewModel.cards[2])

        XCTAssertEqual(coordinator.route, .home)
        XCTAssertEqual(coordinator.toastMessage, "Environment updated. Re-bind parent account if needed.")
    }

    @MainActor
    func testDeveloperMenuDomainSwitchClearsLocalBindingAndPromptsRebind() async throws {
        let defaults = UserDefaults(suiteName: "DevMenuCoordinatorDomainSwitch-\(UUID().uuidString)")!
        let environmentStore = BackendEnvironmentStore(defaults: defaults)
        environmentStore.save(environment: .staging)
        let secretStore = BypassSecretStore(defaults: defaults)
        secretStore.save("secret-demo")
        let transport = RecordingHTTPTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "https://happyword-git-ok.vercel.app/api/v1/health")
            return Self.httpResponse(request: request, status: 200, body: Data())
        }
        let viewModel = DeveloperMenuViewModel(
            environmentStore: environmentStore,
            bypassSecretStore: secretStore,
            transport: transport
        )
        viewModel.manifest = PreviewManifest(previews: [
            PreviewManifestRow(number: 66, title: "preview", branch: "branch", url: URL(string: "https://happyword-git-ok.vercel.app")!, headSha: "abcdef123")
        ])
        let credentialsStore = CloudCredentialsStore(
            secureStore: MemorySecureStore(),
            defaults: UserDefaults(suiteName: "DevMenuCoordinatorDomainSwitchCredentials-\(UUID().uuidString)")!
        )
        credentialsStore.save(.demoBinding)
        let coordinator = AppCoordinator(
            cloudCredentialsStore: credentialsStore,
            developerMenuViewModel: viewModel
        )
        coordinator.route = .devMenu

        await coordinator.activateDeveloperMenuCard(viewModel.cards[2])

        XCTAssertNil(credentialsStore.credentials)
        XCTAssertFalse(coordinator.showsChildProfileShortcut)
        XCTAssertEqual(coordinator.route, .home)
        XCTAssertEqual(coordinator.toastMessage, "已切换环境，请重新绑定家长账号")
    }

    @MainActor
    func testDeveloperMenuReactivatingPreviewClearsLegacyBindingWithoutRecordedBaseURL() async throws {
        let previewURL = URL(string: "https://happyword-git-ok.vercel.app")!
        let defaults = UserDefaults(suiteName: "DevMenuCoordinatorLegacyBinding-\(UUID().uuidString)")!
        let environmentStore = BackendEnvironmentStore(defaults: defaults)
        environmentStore.save(environment: .preview, previewURL: previewURL)
        let secretStore = BypassSecretStore(defaults: defaults)
        secretStore.save("secret-demo")
        let transport = RecordingHTTPTransport { request in
            XCTAssertEqual(request.url?.absoluteString, "https://happyword-git-ok.vercel.app/api/v1/health")
            return Self.httpResponse(request: request, status: 200, body: Data())
        }
        let viewModel = DeveloperMenuViewModel(
            environmentStore: environmentStore,
            bypassSecretStore: secretStore,
            transport: transport
        )
        viewModel.manifest = PreviewManifest(previews: [
            PreviewManifestRow(number: 66, title: "preview", branch: "branch", url: previewURL, headSha: "abcdef123")
        ])
        let credentialsStore = CloudCredentialsStore(
            secureStore: MemorySecureStore(),
            defaults: UserDefaults(suiteName: "DevMenuCoordinatorLegacyBindingCredentials-\(UUID().uuidString)")!
        )
        credentialsStore.save(.demoBinding)
        let coordinator = AppCoordinator(
            cloudCredentialsStore: credentialsStore,
            developerMenuViewModel: viewModel
        )

        await coordinator.activateDeveloperMenuCard(viewModel.cards[2])

        XCTAssertNil(credentialsStore.credentials)
        XCTAssertEqual(coordinator.toastMessage, "已切换环境，请重新绑定家长账号")
    }

    @MainActor
    func testDeveloperMenuPreviewCardWithoutSecretOpensSecretPageAndContinuesAfterSave() async throws {
        let defaults = UserDefaults(suiteName: "DevMenuCoordinatorSecretContinue-\(UUID().uuidString)")!
        let environmentStore = BackendEnvironmentStore(defaults: defaults)
        environmentStore.save(environment: .staging)
        let secretStore = BypassSecretStore(defaults: defaults)
        let counter = RequestCounter()
        let transport = RecordingHTTPTransport { request in
            counter.increment()
            XCTAssertEqual(request.url?.absoluteString, "https://happyword-git-ok.vercel.app/api/v1/health")
            XCTAssertEqual(request.value(forHTTPHeaderField: BackendHeaderProvider.vercelBypassHeader), "secret-demo")
            return Self.httpResponse(request: request, status: 200, body: Data())
        }
        let viewModel = DeveloperMenuViewModel(
            environmentStore: environmentStore,
            bypassSecretStore: secretStore,
            transport: transport
        )
        viewModel.manifest = PreviewManifest(previews: [
            PreviewManifestRow(number: 66, title: "preview", branch: "branch", url: URL(string: "https://happyword-git-ok.vercel.app")!, headSha: "abcdef123")
        ])
        let coordinator = AppCoordinator(developerMenuViewModel: viewModel)
        coordinator.route = .devMenu

        await coordinator.activateDeveloperMenuCard(viewModel.cards[2])

        XCTAssertEqual(counter.value, 0)
        XCTAssertEqual(coordinator.route, .bypassSecret)
        XCTAssertEqual(environmentStore.environment, .staging)

        await coordinator.saveBypassSecretAndContinue("secret-demo")

        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(environmentStore.environment, .preview)
        XCTAssertEqual(environmentStore.previewURL?.absoluteString, "https://happyword-git-ok.vercel.app")
        XCTAssertEqual(coordinator.route, .home)
        XCTAssertEqual(coordinator.toastMessage, "Environment updated. Re-bind parent account if needed.")
    }

    @MainActor
    func testDeveloperMenuLocalAndStagingCardsApplyWithoutHealthProbe() async {
        let defaults = UserDefaults(suiteName: "DevMenuLocalStaging-\(UUID().uuidString)")!
        let environmentStore = BackendEnvironmentStore(defaults: defaults)
        environmentStore.save(environment: .preview, previewURL: URL(string: "https://happyword-git-old.vercel.app")!)
        let transport = RecordingHTTPTransport { request in
            XCTFail("Local and Staging cards should not probe health, got \(request.url?.absoluteString ?? "")")
            return Self.httpResponse(request: request, status: 500, body: Data())
        }
        let viewModel = DeveloperMenuViewModel(
            environmentStore: environmentStore,
            bypassSecretStore: BypassSecretStore(defaults: defaults),
            transport: transport
        )

        await viewModel.activate(viewModel.cards[0])
        XCTAssertEqual(environmentStore.environment, .local)
        XCTAssertNil(environmentStore.previewURL)

        await viewModel.activate(viewModel.cards[1])
        XCTAssertEqual(environmentStore.environment, .staging)
        XCTAssertNil(environmentStore.previewURL)
    }

    func testSharedCloudContractFixturesDecodeInSwift() throws {
        let pair = try JSONDecoder.snakeCase.decode(
            PairRedeemResponse.self,
            from: Self.sharedFixtureData("pairing/pair-redeem.sample.json")
        )
        XCTAssertEqual(pair.familyId, "family-demo")

        let globalPack = try JSONDecoder.snakeCase.decode(
            PackLayerFixture.self,
            from: Self.sharedFixtureData("packs/global-packs-latest.sample.json")
        )
        XCTAssertEqual(globalPack.body?.packs.first?.packId, "space-station")

        let familyPack = try JSONDecoder.snakeCase.decode(
            PackLayerFixture.self,
            from: Self.sharedFixtureData("packs/family-packs-latest.sample.json")
        )
        XCTAssertEqual(familyPack.body?.packs.first?.packId, "family-snacks")

        let stats = try JSONDecoder.snakeCase.decode(
            WordStatsSyncResponse.self,
            from: Self.sharedFixtureData("child/word-stats-sync.sample.json")
        )
        XCTAssertEqual(stats.accepted, 1)
        XCTAssertEqual(stats.serverPulls.first?.wordId, "space-star")

        let preview = try JSONDecoder.snakeCase.decode(
            PreviewManifest.self,
            from: Self.sharedFixtureData("public/preview-urls.sample.json")
        )
        XCTAssertEqual(preview.previews.count, 1)
    }

    func testHTTPClientsUseBackendURLProviderAndBypassHeader() async throws {
        let defaults = UserDefaults(suiteName: "HTTPBackendRouting-\(UUID().uuidString)")!
        let environmentStore = BackendEnvironmentStore(defaults: defaults)
        environmentStore.save(environment: .preview, previewURL: URL(string: "https://happyword-preview.example.test")!)
        let secretStore = BypassSecretStore(defaults: defaults)
        secretStore.save("secret-demo")

        let transport = RecordingHTTPTransport { request in
            XCTAssertEqual(request.url?.host, "happyword-preview.example.test")
            XCTAssertEqual(request.value(forHTTPHeaderField: BackendHeaderProvider.vercelBypassHeader), "secret-demo")
            return Self.httpResponse(request: request, status: 200, body: Self.wordStatsSyncResponseFixture)
        }
        let client = HTTPWordStatsSyncClient(
            baseURLProvider: BackendURLProvider(store: environmentStore),
            headerProvider: BackendHeaderProvider(environmentStore: environmentStore, secretStore: secretStore),
            transport: transport
        )

        let response = try await client.sync(payload: WordStatsSyncPayload(items: [], syncedThroughMs: 0), deviceToken: "token-demo")

        XCTAssertEqual(response.serverNowMs, 1_778_400_000_000)
    }

    func testHTTPChildProfileClientDecodesServerDatetimeWithFractionalSeconds() async throws {
        let transport = RecordingHTTPTransport { request in
            XCTAssertEqual(request.url?.path, "/api/v1/child/profile")
            XCTAssertEqual(request.httpMethod, "PUT")
            return Self.httpResponse(request: request, status: 200, body: Self.childProfileUpdateFixtureWithFractionalDate)
        }
        let client = HTTPChildProfileClient(
            baseURL: URL(string: "https://api.example.test")!,
            transport: transport
        )

        let response = try await client.update(nickname: "MaChen", avatarEmoji: "🦄", deviceToken: "token-demo")

        XCTAssertEqual(response.nickname, "MaChen")
        XCTAssertEqual(try XCTUnwrap(response.updatedAt).timeIntervalSince1970, 1_747_044_754.123456, accuracy: 0.001)
    }

    func testDeveloperToolsPolicyIsReleaseHidden() {
        XCTAssertTrue(DeveloperToolsPolicy.isDeveloperToolsVisible(isDebugBuild: true))
        XCTAssertFalse(DeveloperToolsPolicy.isDeveloperToolsVisible(isDebugBuild: false))
    }

    func testPairRedeemFixtureDecodesAndCredentialsStorePersistsTokenInKeychain() throws {
        let response = try JSONDecoder.snakeCase.decode(PairRedeemResponse.self, from: Self.pairRedeemFixture)
        XCTAssertEqual(response.bindingId, "binding-demo")
        XCTAssertEqual(response.familyId, "family-demo")
        XCTAssertEqual(response.childProfileId, "child-demo")
        XCTAssertEqual(response.nickname, "Little Magician")
        XCTAssertEqual(response.avatarEmoji, "🧙")
        XCTAssertEqual(response.deviceToken, "device-token-demo-not-a-secret")

        let keychain = MemorySecureStore()
        let defaults = UserDefaults(suiteName: "CloudSyncTests-\(UUID().uuidString)")!
        let store = CloudCredentialsStore(secureStore: keychain, defaults: defaults)

        store.save(response)

        XCTAssertEqual(keychain.string(forKey: CloudCredentialsStore.deviceTokenKey), "device-token-demo-not-a-secret")
        XCTAssertEqual(store.credentials?.nickname, "Little Magician")
        XCTAssertEqual(store.credentials?.familyId, "family-demo")
        XCTAssertNotNil(store.credentials?.pairedAt)

        store.clear()

        XCTAssertNil(keychain.string(forKey: CloudCredentialsStore.deviceTokenKey))
        XCTAssertNil(store.credentials)
    }

    func testDeviceIdProviderReturnsStableKeychainBackedId() {
        let keychain = MemorySecureStore()
        let provider = DeviceIdProvider(secureStore: keychain)

        let first = provider.deviceId()
        let second = provider.deviceId()

        XCTAssertEqual(first, second)
        XCTAssertGreaterThanOrEqual(first.count, 8)
        XCTAssertEqual(keychain.string(forKey: DeviceIdProvider.deviceIdKey), first)
        XCTAssertEqual(provider.sourceLabel(), "Keychain (持久)")
    }

    func testPairingInputParsesShortCodeTokenAndLandingURL() throws {
        XCTAssertEqual(try PairingInput.parse("123456"), .shortCode("123456"))
        XCTAssertEqual(try PairingInput.parse("pair-token-demo"), .token("pair-token-demo"))
        XCTAssertEqual(
            try PairingInput.parse("https://happyword.example/pair?token=qr-token-demo"),
            .token("qr-token-demo")
        )
        XCTAssertThrowsError(try PairingInput.parse("12"))
    }

    func testHTTPDeviceBindingClientPostsRedeemRequestAndDecodesCredentials() async throws {
        let transport = RecordingHTTPTransport { request in
            XCTAssertEqual(request.url?.path, "/api/v1/pair/redeem")
            XCTAssertEqual(request.httpMethod, "POST")
            let json = try Self.jsonObject(from: request)
            XCTAssertEqual(json["short_code"] as? String, "123456")
            XCTAssertEqual(json["device_id"] as? String, "device-test")
            return Self.httpResponse(request: request, status: 200, body: Self.pairRedeemFixture)
        }
        let client = HTTPDeviceBindingClient(
            baseURL: URL(string: "https://api.example.test")!,
            transport: transport
        )

        let response = try await client.redeem(pairingInput: "123456", deviceId: "device-test")

        XCTAssertEqual(response.childProfileId, "child-demo")
        XCTAssertEqual(response.deviceToken, "device-token-demo-not-a-secret")
    }

    func testPackSyncResponsesHandle200204304AndFamilyOverridesGlobal() throws {
        let globalResponse = try JSONDecoder.snakeCase.decode(PackLayerFixture.self, from: Self.globalPackFixture)
        let familyResponse = try JSONDecoder.snakeCase.decode(PackLayerFixture.self, from: Self.familyPackFixture)
        let client = PackSyncClient()

        let globalCache = try client.apply(
            status: globalResponse.status,
            etag: globalResponse.headers.eTag,
            body: globalResponse.body,
            source: .global,
            cached: nil
        )
        XCTAssertEqual(globalCache?.etag, "\"global-v1\"")
        XCTAssertEqual(globalCache?.packs.map(\.id), ["space-station"])
        XCTAssertEqual(globalCache?.packs.first?.source, .global)

        let preserved = try client.apply(status: 304, etag: nil, body: nil, source: .global, cached: globalCache)
        XCTAssertEqual(preserved, globalCache)

        let cleared = try client.apply(status: 204, etag: nil, body: nil, source: .global, cached: globalCache)
        XCTAssertNil(cleared)

        let familyCache = try client.apply(
            status: familyResponse.status,
            etag: familyResponse.headers.eTag,
            body: familyResponse.body,
            source: .family,
            cached: nil
        )
        let overridingFamily = Pack(
            id: "space-station",
            title: "Family Space",
            subtitle: "Family",
            story: "family",
            source: .family,
            words: [DemoWords.words[0]]
        )
        let library = PackLibrary(
            builtin: [],
            global: globalCache?.packs ?? [],
            family: (familyCache?.packs ?? []) + [overridingFamily]
        )

        XCTAssertEqual(library.pack(id: "space-station")?.title, "Family Space")
        XCTAssertEqual(library.pack(id: "space-station")?.source, .family)
        XCTAssertEqual(library.pack(id: "family-snacks")?.title, "Family Snacks")
    }

    func testFamilyPackClientKeepsCacheForAuthProblemsAndMarksGoneBinding() throws {
        let cached = PackLayerCache(etag: "\"family-v1\"", packs: [
            Pack(id: "family-snacks", title: "Family Snacks", subtitle: "", story: "", source: .family, words: DemoWords.words)
        ])
        let client = PackSyncClient()

        XCTAssertEqual(try client.apply(status: 401, etag: nil, body: nil, source: .family, cached: cached), cached)
        XCTAssertEqual(try client.apply(status: 403, etag: nil, body: nil, source: .family, cached: cached), cached)

        do {
            _ = try client.apply(status: 410, etag: nil, body: nil, source: .family, cached: cached)
            XCTFail("Expected bindingGone")
        } catch PackSyncError.bindingGone {
            // Expected.
        }

        XCTAssertEqual(try client.apply(status: 500, etag: nil, body: nil, source: .family, cached: cached), cached)
    }

    func testHTTPPackLayerClientUsesETagBearerAndKeepsCacheOnServerError() async throws {
        let cached = PackLayerCache(etag: "\"family-v1\"", packs: [
            Pack(id: "family-snacks", title: "Family Snacks", subtitle: "", story: "", source: .family, words: DemoWords.words)
        ])
        let counter = RequestCounter()
        let transport = RecordingHTTPTransport { request in
            counter.increment()
            XCTAssertEqual(request.url?.path, "/api/v1/child/family-packs/latest.json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-demo")
            if counter.value == 1 {
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"family-v1\"")
                return Self.httpResponse(
                    request: request,
                    status: 200,
                    headers: ["ETag": "\"family-v2\""],
                    body: try JSONDecoder.snakeCase.decode(PackLayerFixture.self, from: Self.familyPackFixture).bodyData()
                )
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"family-v2\"")
            return Self.httpResponse(request: request, status: 500, body: Data())
        }
        let client = HTTPPackLayerClient(
            baseURL: URL(string: "https://api.example.test")!,
            transport: transport
        )

        let refreshed = try await client.fetchFamily(deviceToken: "token-demo", cached: cached)
        let fallback = try await client.fetchFamily(deviceToken: "token-demo", cached: refreshed)

        XCTAssertEqual(refreshed?.etag, "\"family-v2\"")
        XCTAssertEqual(refreshed?.packs.map(\.id), ["family-snacks"])
        XCTAssertEqual(fallback, refreshed)
    }

    func testFileBackedPackLayerStorePersistsLayerCache() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PackLayerStore-\(UUID().uuidString)", isDirectory: true)
        let store = FileBackedPackLayerStore(directory: directory)
        let cache = PackLayerCache(etag: "\"global-v1\"", packs: [
            Pack(id: "space-station", title: "Space Station", subtitle: "Space", story: "Story", source: .global, words: [
                WordEntry(id: "space-star", word: "star", meaningZh: "星星", category: "space", difficulty: 1)
            ])
        ])

        try store.save(cache, layer: .global)
        let reloaded = try store.load(layer: .global)

        XCTAssertEqual(reloaded, cache)
    }

    func testWordStatsSyncPayloadMatchesContractShape() throws {
        let recorder = LearningRecorder()
        let answeredAt = Date(timeIntervalSince1970: 1_778_399_999)
        recorder.record(wordId: "space-star", correct: true, at: answeredAt)
        recorder.record(wordId: "space-star", correct: false, at: answeredAt)
        let payload = WordStatsSyncPayload.from(recorder: recorder, syncedThroughMs: 1_778_300_000_000)

        XCTAssertEqual(payload.syncedThroughMs, 1_778_300_000_000)
        XCTAssertEqual(payload.items.count, 1)
        XCTAssertEqual(payload.items[0].wordId, "space-star")
        XCTAssertEqual(payload.items[0].seenCount, 2)
        XCTAssertEqual(payload.items[0].correctCount, 1)
        XCTAssertEqual(payload.items[0].wrongCount, 1)
        XCTAssertEqual(payload.items[0].lastAnsweredMs, 1_778_399_999_000)

        let encoded = try JSONEncoder.snakeCase.encode(payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(object["synced_through_ms"])
        let items = try XCTUnwrap(object["items"] as? [[String: Any]])
        XCTAssertNotNil(items[0]["word_id"])
        XCTAssertNotNil(items[0]["seen_count"])
    }

    func testWordStatsSyncClientPostsBearerPayloadAndDecodesAcceptedClock() async throws {
        let transport = RecordingHTTPTransport { request in
            XCTAssertEqual(request.url?.path, "/api/v1/child/word-stats/sync")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-demo")
            let json = try Self.jsonObject(from: request)
            XCTAssertEqual(json["synced_through_ms"] as? Int, 1_778_300_000_000)
            return Self.httpResponse(request: request, status: 200, body: Self.wordStatsSyncResponseFixture)
        }
        let client = HTTPWordStatsSyncClient(
            baseURL: URL(string: "https://api.example.test")!,
            transport: transport
        )
        let payload = WordStatsSyncPayload(
            items: [
                WordStatSyncItem(stat: WordLearningStat(
                    wordId: "space-star",
                    attempts: 2,
                    correct: 1,
                    lastSeenAt: Date(timeIntervalSince1970: 1_778_399_999)
                )),
            ],
            syncedThroughMs: 1_778_300_000_000
        )

        let response = try await client.sync(payload: payload, deviceToken: "token-demo")

        XCTAssertEqual(response.accepted, 1)
        XCTAssertEqual(response.serverNowMs, 1_778_400_000_000)
    }

    func testWordStatsSyncStateStoreTracksSuccessAndRetry() {
        let defaults = UserDefaults(suiteName: "WordStatsSyncState-\(UUID().uuidString)")!
        let store = WordStatsSyncStateStore(defaults: defaults)

        store.markFailure()
        XCTAssertTrue(store.needsRetry)

        store.markSuccess(serverNowMs: 1_778_400_000_000)
        XCTAssertFalse(store.needsRetry)
        XCTAssertEqual(store.syncedThroughMs, 1_778_400_000_000)
    }

    @MainActor
    func testCoordinatorShowsChildProfileShortcutOnlyAfterDeviceBinding() {
        let credentialsStore = CloudCredentialsStore(
            secureStore: MemorySecureStore(),
            defaults: UserDefaults(suiteName: "CoordinatorChildProfileShortcut-\(UUID().uuidString)")!
        )
        let coordinator = AppCoordinator(
            configStore: GameConfigStore(defaults: UserDefaults(suiteName: "CoordinatorChildProfileConfig-\(UUID().uuidString)")!),
            pronunciationService: MockPronunciationService(),
            cloudCredentialsStore: credentialsStore,
            deviceIdProvider: DeviceIdProvider(secureStore: MemorySecureStore()),
            bindingClient: MockDeviceBindingClient()
        )

        XCTAssertFalse(coordinator.showsChildProfileShortcut)

        credentialsStore.save(.demoBinding)

        XCTAssertTrue(coordinator.showsChildProfileShortcut)
    }

    @MainActor
    func testCoordinatorReturnsHomeAfterChildNicknameCloudSave() async {
        let credentialsStore = CloudCredentialsStore(
            secureStore: MemorySecureStore(),
            defaults: UserDefaults(suiteName: "CoordinatorChildProfileSave-\(UUID().uuidString)")!
        )
        credentialsStore.save(.demoBinding)
        let childProfileClient = RecordingChildProfileClient()
        let coordinator = AppCoordinator(
            configStore: GameConfigStore(defaults: UserDefaults(suiteName: "CoordinatorChildProfileSaveConfig-\(UUID().uuidString)")!),
            pronunciationService: MockPronunciationService(),
            cloudCredentialsStore: credentialsStore,
            deviceIdProvider: DeviceIdProvider(secureStore: MemorySecureStore()),
            bindingClient: MockDeviceBindingClient(),
            childProfileClient: childProfileClient
        )
        coordinator.route = .childProfile

        await coordinator.updateChildNickname("Sophia")

        XCTAssertEqual(childProfileClient.lastNickname, "Sophia")
        XCTAssertEqual(credentialsStore.credentials?.nickname, "Sophia")
        XCTAssertEqual(coordinator.bindingMessage, "已保存孩子名字")
        XCTAssertEqual(coordinator.route, .home)
    }

    @MainActor
    func testCoordinatorExplicitWordStatsSyncAndUnbindUseCloudClients() async {
        let credentialsStore = CloudCredentialsStore(
            secureStore: MemorySecureStore(),
            defaults: UserDefaults(suiteName: "CoordinatorCloudSync-\(UUID().uuidString)")!
        )
        credentialsStore.save(.demoBinding)
        let statsClient = RecordingWordStatsSyncClient()
        let unbindClient = RecordingDeviceUnbindClient()
        let stateStore = WordStatsSyncStateStore(defaults: UserDefaults(suiteName: "CoordinatorStatsState-\(UUID().uuidString)")!)
        let coordinator = AppCoordinator(
            configStore: GameConfigStore(defaults: UserDefaults(suiteName: "CoordinatorConfig-\(UUID().uuidString)")!),
            pronunciationService: MockPronunciationService(),
            cloudCredentialsStore: credentialsStore,
            deviceIdProvider: DeviceIdProvider(secureStore: MemorySecureStore()),
            bindingClient: MockDeviceBindingClient(),
            wordStatsSyncClient: statsClient,
            wordStatsSyncStateStore: stateStore,
            unbindClient: unbindClient
        )
        coordinator.learningRecorder.record(wordId: "space-star", correct: true, at: Date(timeIntervalSince1970: 1_778_399_999))
        var config = coordinator.configStore.config
        config.parentPin = "123456"
        coordinator.configStore.save(config)

        await coordinator.syncWordStatsExplicitly()
        XCTAssertEqual(statsClient.lastToken, PairRedeemResponse.demoBinding.deviceToken)
        XCTAssertEqual(stateStore.syncedThroughMs, 1_778_400_000_000)
        XCTAssertEqual(coordinator.packManagerMessage, "学习数据已同步")
        XCTAssertEqual(coordinator.toastMessage, "学习记录已同步")

        await coordinator.confirmUnbind(pin: "123456")

        XCTAssertEqual(unbindClient.lastToken, PairRedeemResponse.demoBinding.deviceToken)
        XCTAssertNil(credentialsStore.credentials)
    }

    @MainActor
    func testAnimatedBattleFinishAutomaticallySyncsRecordedWordStats() async throws {
        let credentialsStore = CloudCredentialsStore(
            secureStore: MemorySecureStore(),
            defaults: UserDefaults(suiteName: "CoordinatorAnimatedStats-\(UUID().uuidString)")!
        )
        credentialsStore.save(.demoBinding)
        let statsClient = RecordingWordStatsSyncClient()
        let configStore = GameConfigStore(defaults: UserDefaults(suiteName: "CoordinatorAnimatedStatsConfig-\(UUID().uuidString)")!)
        configStore.save(GameConfig(monsterMaxHp: 1, monstersTotal: 1, autoSpeak: false))
        let coordinator = AppCoordinator(
            configStore: configStore,
            pronunciationService: MockPronunciationService(),
            cloudCredentialsStore: credentialsStore,
            deviceIdProvider: DeviceIdProvider(secureStore: MemorySecureStore()),
            bindingClient: MockDeviceBindingClient(),
            wordStatsSyncClient: statsClient,
            wordStatsSyncStateStore: WordStatsSyncStateStore(defaults: UserDefaults(suiteName: "CoordinatorAnimatedStatsState-\(UUID().uuidString)")!)
        )
        coordinator.startBattle()
        let question = try XCTUnwrap(coordinator.battleEngine?.state.currentQuestion)

        let outcome = coordinator.submitBattleOptionForAnimation(question.answer)
        XCTAssertEqual(outcome?.battleEnded, true)
        coordinator.finishBattle()

        for _ in 0..<20 where statsClient.lastPayload == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let payload = try XCTUnwrap(statsClient.lastPayload)
        XCTAssertEqual(payload.items.map(\.wordId), [question.wordId])
        XCTAssertEqual(payload.items.first?.seenCount, 1)
        XCTAssertEqual(payload.items.first?.correctCount, 1)
    }

    private static let pairRedeemFixture = Data("""
    {
      "binding_id": "binding-demo",
      "family_id": "family-demo",
      "child_profile_id": "child-demo",
      "nickname": "Little Magician",
      "avatar_emoji": "🧙",
      "device_token": "device-token-demo-not-a-secret"
    }
    """.utf8)

    private static let globalPackFixture = Data("""
    {
      "status": 200,
      "headers": { "ETag": "\\"global-v1\\"" },
      "body": {
        "schema_version": 1,
        "merged_at": "2026-05-10T12:03:34Z",
        "packs": [
          {
            "pack_id": "space-station",
            "name": "Space Station",
            "description": "Space themed practice pack",
            "scene": {
              "bgPrimary": "#102A43",
              "bgAccent": "#F0B429",
              "bossName": "Star Wizard"
            },
            "version": 1,
            "schema_version": 1,
            "published_at": "2026-05-10T12:03:34Z",
            "words": [
              { "id": "space-star", "word": "star", "meaningZh": "星星", "category": "space", "difficulty": 1 }
            ]
          }
        ]
      }
    }
    """.utf8)

    private static let familyPackFixture = Data("""
    {
      "status": 200,
      "headers": { "ETag": "\\"family-v1\\"" },
      "body": {
        "schema_version": 1,
        "family_id": "family-demo",
        "merged_at": "2026-05-10T12:03:34Z",
        "packs": [
          {
            "pack_id": "family-snacks",
            "name": "Family Snacks",
            "version": 1,
            "schema_version": 1,
            "words": [
              { "id": "snack-cookie", "word": "snack", "meaningZh": "点心", "category": "snacks", "difficulty": 1 }
            ]
          }
        ]
      }
    }
    """.utf8)

    private static let wordStatsSyncResponseFixture = Data("""
    {
      "accepted": 1,
      "rejected": 0,
      "server_pulls": [],
      "server_now_ms": 1778400000000
    }
    """.utf8)

    private static let childProfileUpdateFixtureWithFractionalDate = Data("""
    {
      "profile_id": "child-demo",
      "family_id": "family-demo",
      "nickname": "MaChen",
      "avatar_emoji": "🦄",
      "updated_at": "2025-05-12T10:12:34.123456+00:00"
    }
    """.utf8)

    private static let previewManifestFixture = Data("""
    {
      "schema_version": 1,
      "updated_at": "2026-05-12T00:00:00Z",
      "previews": [
        {
          "pr": 65,
          "title": "fix(harmony): stabilize UI suite with question type controls",
          "branch": "fix/harmony-ui",
          "url": "https://happyword-git-fix-harmony.vercel.app",
          "author": "codex",
          "head_sha": "24cd43a9988",
          "updated_at": "2026-05-12T00:00:00Z"
        }
      ]
    }
    """.utf8)

    private static func jsonObject(from request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func httpResponse(
        request: URLRequest,
        status: Int,
        headers: [String: String] = [:],
        body: Data
    ) -> (Data, HTTPURLResponse) {
        (
            body,
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        )
    }

    private static func sharedFixtureData(_ relativePath: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures")
            .appendingPathComponent(relativePath)
        return try Data(contentsOf: url)
    }
}

private final class RecordingHTTPTransport: HTTPTransporting, @unchecked Sendable {
    private let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    init(handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try handler(request)
    }
}

private final class RequestCounter: @unchecked Sendable {
    var value = 0

    func increment() {
        value += 1
    }
}

private final class RequestURLRecorder: @unchecked Sendable {
    private(set) var urls: [String] = []

    func append(_ url: String?) {
        urls.append(url ?? "")
    }
}

private final class RecordingWordStatsSyncClient: WordStatsSyncClienting, @unchecked Sendable {
    var lastToken: String?
    var lastPayload: WordStatsSyncPayload?

    func sync(payload: WordStatsSyncPayload, deviceToken: String) async throws -> WordStatsSyncResponse {
        lastToken = deviceToken
        lastPayload = payload
        return WordStatsSyncResponse(accepted: payload.items.count, rejected: 0, serverPulls: [], serverNowMs: 1_778_400_000_000)
    }
}

private final class RecordingDeviceUnbindClient: DeviceUnbindClienting, @unchecked Sendable {
    var lastToken: String?

    func unbind(deviceToken: String) async throws {
        lastToken = deviceToken
    }
}

private final class RecordingChildProfileClient: ChildProfileClienting, @unchecked Sendable {
    var lastNickname: String?

    func update(nickname: String, avatarEmoji: String?, deviceToken: String) async throws -> ChildProfileUpdateResponse {
        lastNickname = nickname
        return ChildProfileUpdateResponse(
            profileId: PairRedeemResponse.demoBinding.childProfileId,
            familyId: PairRedeemResponse.demoBinding.familyId,
            nickname: nickname,
            avatarEmoji: avatarEmoji ?? PairRedeemResponse.demoBinding.avatarEmoji
        )
    }
}

@MainActor
private final class MockPronunciationService: PronunciationSpeaking {
    var isAvailable = false

    func prepare() {}
    func speak(_ word: String) {}
    func dispose() {}
}

private extension PackLayerFixture {
    func bodyData() throws -> Data {
        try JSONEncoder.snakeCase.encode(XCTUnwrap(body))
    }
}
