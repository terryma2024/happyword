import Combine
import Foundation
import Security

enum DeveloperToolsPolicy {
    static func isDeveloperToolsVisible(isDebugBuild: Bool = Self.isDebugBuild) -> Bool {
        isDebugBuild
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

enum BackendEnvironment: String, CaseIterable, Codable, Equatable, Sendable {
    case local
    case staging
    case production
    case preview

    var title: String {
        switch self {
        case .local: "Local"
        case .staging: "Staging"
        case .production: "Production"
        case .preview: "Preview"
        }
    }
}

final class BackendEnvironmentStore: @unchecked Sendable {
    private let environmentKey = "wordMagicBackendEnvironment"
    private let previewURLKey = "wordMagicBackendPreviewURL"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-UITestResetState") {
            reset()
        }
    }

    var environment: BackendEnvironment {
        guard let rawValue = defaults.string(forKey: environmentKey),
              let environment = BackendEnvironment(rawValue: rawValue)
        else {
            return .staging
        }
        return environment
    }

    var previewURL: URL? {
        guard let value = defaults.string(forKey: previewURLKey) else { return nil }
        return URL(string: value)
    }

    func save(environment: BackendEnvironment, previewURL: URL? = nil) {
        defaults.set(environment.rawValue, forKey: environmentKey)
        if let previewURL {
            defaults.set(previewURL.absoluteString, forKey: previewURLKey)
        } else if environment != .preview {
            defaults.removeObject(forKey: previewURLKey)
        }
    }

    func reset() {
        defaults.removeObject(forKey: environmentKey)
        defaults.removeObject(forKey: previewURLKey)
    }
}

final class BypassSecretStore: @unchecked Sendable {
    private let secretKey = "wordMagicBackendBypassSecret"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-UITestResetState") {
            clear()
        }
    }

    var secret: String {
        defaults.string(forKey: secretKey) ?? ""
    }

    func save(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clear()
        } else {
            defaults.set(trimmed, forKey: secretKey)
        }
    }

    func clear() {
        defaults.removeObject(forKey: secretKey)
    }
}

protocol BackendURLProviding: Sendable {
    func effectiveBaseURL() -> URL
}

struct StaticBackendURLProvider: BackendURLProviding {
    private let url: URL

    init(_ url: URL) {
        self.url = url
    }

    func effectiveBaseURL() -> URL {
        url
    }
}

struct BackendURLProvider: BackendURLProviding {
    static let localBaseURL = URL(string: "http://127.0.0.1:8000")!
    static let stagingBaseURL = URL(string: "https://happyword.cool")!
    static let previewManifestURL = URL(string: "https://happyword.cool/api/v1/public/preview-urls.json")!

    private let store: BackendEnvironmentStore
    private let launchOverrideURL: URL?

    init(store: BackendEnvironmentStore = BackendEnvironmentStore(), launchOverrideURL: URL? = nil) {
        self.store = store
        self.launchOverrideURL = launchOverrideURL
    }

    func effectiveBaseURL() -> URL {
        if let launchOverrideURL {
            return launchOverrideURL
        }
        if let value = ProcessInfo.processInfo.environment["HAPPYWORD_API_BASE_URL"],
           let url = URL(string: value) {
            return url
        }
        guard DeveloperToolsPolicy.isDeveloperToolsVisible() else {
            return Self.stagingBaseURL
        }
        switch store.environment {
        case .local:
            return Self.localBaseURL
        case .staging, .production:
            return Self.stagingBaseURL
        case .preview:
            return store.previewURL ?? Self.stagingBaseURL
        }
    }

    /// Parent web login shell at `/family/login` on the same origin as API calls.
    static func parentFamilyLoginPageURL(baseURL: URL) -> URL {
        var base = baseURL.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return URL(string: "\(base)/family/login")!
    }
}

extension BackendURLProviding {
    func parentFamilyLoginPageURL() -> URL {
        BackendURLProvider.parentFamilyLoginPageURL(baseURL: effectiveBaseURL())
    }
}

protocol BackendHeaderProviding: Sendable {
    func headers() -> [String: String]
}

extension BackendHeaderProviding {
    func apply(to request: inout URLRequest) {
        for (field, value) in headers() {
            request.setValue(value, forHTTPHeaderField: field)
        }
    }
}

struct BackendHeaderProvider: BackendHeaderProviding {
    static let vercelBypassHeader = "x-vercel-protection-bypass"

    private let environmentStore: BackendEnvironmentStore
    private let secretStore: BypassSecretStore

    init(
        environmentStore: BackendEnvironmentStore = BackendEnvironmentStore(),
        secretStore: BypassSecretStore = BypassSecretStore()
    ) {
        self.environmentStore = environmentStore
        self.secretStore = secretStore
    }

    func headers() -> [String: String] {
        guard DeveloperToolsPolicy.isDeveloperToolsVisible(),
              environmentStore.environment == .preview
        else {
            return [:]
        }
        let secret = secretStore.secret
        guard !secret.isEmpty else { return [:] }
        return [Self.vercelBypassHeader: secret]
    }
}

enum CloudAPIEnvironment {
    static var defaultBaseURL: URL {
        BackendURLProvider().effectiveBaseURL()
    }
}

enum CloudClientFactory {
    static var shouldUseLocalMocks: Bool {
        shouldUseLocalMocks(arguments: ProcessInfo.processInfo.arguments)
    }

    static func shouldUseLocalMocks(arguments: [String]) -> Bool {
        arguments.contains("-UITestMockBinding")
            || arguments.contains("-UITestSeedBoundDevice")
    }

    static func bindingClient(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environmentStore: BackendEnvironmentStore = BackendEnvironmentStore(),
        bypassSecretStore: BypassSecretStore = BypassSecretStore(),
        transport: any HTTPTransporting = URLSessionHTTPTransport()
    ) -> any DeviceBindingClienting {
        shouldUseLocalMocks(arguments: arguments)
            ? MockDeviceBindingClient()
            : HTTPDeviceBindingClient(
                baseURLProvider: BackendURLProvider(store: environmentStore),
                headerProvider: BackendHeaderProvider(environmentStore: environmentStore, secretStore: bypassSecretStore),
                transport: transport
            )
    }

    static func packLayerClient(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environmentStore: BackendEnvironmentStore = BackendEnvironmentStore(),
        bypassSecretStore: BypassSecretStore = BypassSecretStore(),
        transport: any HTTPTransporting = URLSessionHTTPTransport()
    ) -> any PackLayerClienting {
        shouldUseLocalMocks(arguments: arguments)
            ? DemoPackLayerClient()
            : HTTPPackLayerClient(
                baseURLProvider: BackendURLProvider(store: environmentStore),
                headerProvider: BackendHeaderProvider(environmentStore: environmentStore, secretStore: bypassSecretStore),
                transport: transport
            )
    }

    static func wordStatsSyncClient(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environmentStore: BackendEnvironmentStore = BackendEnvironmentStore(),
        bypassSecretStore: BypassSecretStore = BypassSecretStore(),
        transport: any HTTPTransporting = URLSessionHTTPTransport()
    ) -> any WordStatsSyncClienting {
        shouldUseLocalMocks(arguments: arguments)
            ? MockWordStatsSyncClient()
            : HTTPWordStatsSyncClient(
                baseURLProvider: BackendURLProvider(store: environmentStore),
                headerProvider: BackendHeaderProvider(environmentStore: environmentStore, secretStore: bypassSecretStore),
                transport: transport
            )
    }

    static func unbindClient(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environmentStore: BackendEnvironmentStore = BackendEnvironmentStore(),
        bypassSecretStore: BypassSecretStore = BypassSecretStore(),
        transport: any HTTPTransporting = URLSessionHTTPTransport()
    ) -> any DeviceUnbindClienting {
        shouldUseLocalMocks(arguments: arguments)
            ? MockDeviceUnbindClient()
            : HTTPDeviceUnbindClient(
                baseURLProvider: BackendURLProvider(store: environmentStore),
                headerProvider: BackendHeaderProvider(environmentStore: environmentStore, secretStore: bypassSecretStore),
                transport: transport
            )
    }

    static func childProfileClient(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environmentStore: BackendEnvironmentStore = BackendEnvironmentStore(),
        bypassSecretStore: BypassSecretStore = BypassSecretStore(),
        transport: any HTTPTransporting = URLSessionHTTPTransport()
    ) -> any ChildProfileClienting {
        shouldUseLocalMocks(arguments: arguments)
            ? MockChildProfileClient()
            : HTTPChildProfileClient(
                baseURLProvider: BackendURLProvider(store: environmentStore),
                headerProvider: BackendHeaderProvider(environmentStore: environmentStore, secretStore: bypassSecretStore),
                transport: transport
            )
    }
}

extension JSONDecoder {
    static var snakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Self.decodeISO8601Date(value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }
        return decoder
    }

    private static func decodeISO8601Date(_ value: String) -> Date? {
        for options in [
            ISO8601DateFormatter.Options.withInternetDateTime.union(.withFractionalSeconds),
            ISO8601DateFormatter.Options.withInternetDateTime,
        ] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}

extension JSONEncoder {
    static var snakeCase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

protocol SecureStore {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func remove(forKey key: String)
}

final class MemorySecureStore: SecureStore {
    private var values: [String: String] = [:]

    func string(forKey key: String) -> String? {
        values[key]
    }

    func set(_ value: String, forKey key: String) {
        values[key] = value
    }

    func remove(forKey key: String) {
        values.removeValue(forKey: key)
    }
}

final class KeychainSecureStore: SecureStore {
    private let service: String

    init(service: String = "com.terryma.wordmagicgame.cloud") {
        self.service = service
    }

    func string(forKey key: String) -> String? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        var query = baseQuery(forKey: key)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    func remove(forKey key: String) {
        SecItemDelete(baseQuery(forKey: key) as CFDictionary)
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

struct PairRedeemResponse: Codable, Equatable, Sendable {
    var bindingId: String
    var familyId: String
    var childProfileId: String
    var nickname: String
    var avatarEmoji: String
    var deviceToken: String
}

enum DeviceBindingError: Error, Equatable, Sendable {
    case invalidShortCode
    case invalidPairingInput
}

enum PairingInput: Equatable, Sendable {
    case shortCode(String)
    case token(String)

    func requestBody(deviceId: String) -> PairRedeemRequest {
        switch self {
        case let .shortCode(value):
            PairRedeemRequest(shortCode: value, token: nil, deviceId: deviceId)
        case let .token(value):
            PairRedeemRequest(shortCode: nil, token: value, deviceId: deviceId)
        }
    }

    static func parse(_ input: String) throws -> PairingInput {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 6, trimmed.allSatisfy(\.isNumber) {
            return .shortCode(trimmed)
        }
        if let url = URL(string: trimmed),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
               !token.isEmpty {
                return .token(token)
            }
            let pathToken = components.path
                .split(separator: "/")
                .last
                .map(String.init) ?? ""
            if pathToken.count >= 8 {
                return .token(pathToken)
            }
        }
        if trimmed.count >= 8 {
            return .token(trimmed)
        }
        throw DeviceBindingError.invalidPairingInput
    }
}

struct PairRedeemRequest: Codable, Equatable, Sendable {
    var shortCode: String?
    var token: String?
    var deviceId: String
}

protocol DeviceBindingClienting: Sendable {
    func redeem(pairingInput: String, deviceId: String) async throws -> PairRedeemResponse
}

struct MockDeviceBindingClient: DeviceBindingClienting, Sendable {
    func redeem(pairingInput: String, deviceId: String) async throws -> PairRedeemResponse {
        let parsed = try PairingInput.parse(pairingInput)
        guard parsed == .shortCode("123456")
            || parsed == .shortCode("654321")
            || parsed == .token("pair-token-demo")
            || parsed == .token("qr-token-demo")
        else {
            throw DeviceBindingError.invalidShortCode
        }
        return PairRedeemResponse.demoBinding
    }
}

protocol HTTPTransporting: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPTransport: HTTPTransporting {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudHTTPError.invalidResponse
        }
        return (data, httpResponse)
    }
}

enum CloudHTTPError: Error, Equatable {
    case invalidResponse
    case unexpectedStatus(Int)
    case familyIdRequired
}

struct PreviewManifest: Decodable, Equatable {
    var updatedAt: String?
    var previews: [PreviewManifestRow]

    private enum CodingKeys: String, CodingKey {
        case updatedAt
        case previews
        case pulls
    }

    init(updatedAt: String? = nil, previews: [PreviewManifestRow]) {
        self.updatedAt = updatedAt
        self.previews = previews
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        previews = try container.decodeIfPresent([PreviewManifestRow].self, forKey: .previews)
            ?? container.decodeIfPresent([PreviewManifestRow].self, forKey: .pulls)
            ?? []
    }
}

struct PreviewManifestRow: Decodable, Equatable, Identifiable {
    var number: Int
    var title: String?
    var branch: String
    var url: URL
    var author: String?
    var headSha: String?
    var updatedAt: String?

    var id: Int { number }

    private enum CodingKeys: String, CodingKey {
        case number
        case pr
        case title
        case branch
        case url
        case author
        case headSha
        case updatedAt
    }

    init(
        number: Int,
        title: String? = nil,
        branch: String,
        url: URL,
        author: String? = nil,
        headSha: String? = nil,
        updatedAt: String? = nil
    ) {
        self.number = number
        self.title = title
        self.branch = branch
        self.url = url
        self.author = author
        self.headSha = headSha
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = try container.decodeIfPresent(Int.self, forKey: .number)
            ?? container.decode(Int.self, forKey: .pr)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        branch = try container.decode(String.self, forKey: .branch)
        url = try container.decode(URL.self, forKey: .url)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        headSha = try container.decodeIfPresent(String.self, forKey: .headSha)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct PreviewManifestClient: Sendable {
    private let manifestURL: URL
    private let transport: any HTTPTransporting

    init(
        manifestURL: URL = BackendURLProvider.previewManifestURL,
        transport: any HTTPTransporting = URLSessionHTTPTransport(),
        headerProvider: any BackendHeaderProviding = BackendHeaderProvider()
    ) {
        self.manifestURL = manifestURL
        self.transport = transport
        _ = headerProvider
    }

    func fetch() async throws -> PreviewManifest {
        var request = URLRequest(url: manifestURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 200 else {
            throw CloudHTTPError.unexpectedStatus(response.statusCode)
        }
        return try JSONDecoder.snakeCase.decode(PreviewManifest.self, from: data)
    }
}

struct DeveloperMenuCard: Identifiable, Equatable {
    var id: String
    var title: String
    var footer: String
    var environment: BackendEnvironment
    var previewURL: URL?
    var isSelected: Bool
}

struct DeveloperMenuActivationResult: Equatable {
    var didApply: Bool
    var toastMessage: String?

    static let environmentUpdated = DeveloperMenuActivationResult(
        didApply: true,
        toastMessage: "已切换环境，请重新绑定家长账号"
    )

    static func blocked(_ message: String? = nil) -> DeveloperMenuActivationResult {
        DeveloperMenuActivationResult(didApply: false, toastMessage: message)
    }
}

@MainActor
final class DeveloperMenuViewModel: ObservableObject {
    @Published var environment: BackendEnvironment
    @Published var previewURLText: String
    @Published var manifest = PreviewManifest(previews: [])
    @Published var statusMessage = ""
    @Published var lastProbeStatus = "未检测"
    @Published var isApplying = false

    private let environmentStore: BackendEnvironmentStore
    private let bypassSecretStore: BypassSecretStore
    private let manifestClient: PreviewManifestClient
    private let urlProvider: BackendURLProvider
    private let transport: any HTTPTransporting

    init(
        environmentStore: BackendEnvironmentStore = BackendEnvironmentStore(),
        bypassSecretStore: BypassSecretStore = BypassSecretStore(),
        manifestClient: PreviewManifestClient = PreviewManifestClient(),
        transport: any HTTPTransporting = URLSessionHTTPTransport()
    ) {
        self.environmentStore = environmentStore
        self.bypassSecretStore = bypassSecretStore
        self.manifestClient = manifestClient
        self.transport = transport
        environment = environmentStore.environment
        previewURLText = environmentStore.previewURL?.absoluteString ?? ""
        urlProvider = BackendURLProvider(store: environmentStore)
    }

    var routingDebug: String {
        "环境 \(environment.title) · \(urlProvider.effectiveBaseURL().absoluteString)"
    }

    var effectiveBaseURL: URL {
        urlProvider.effectiveBaseURL()
    }

    var bypassSecret: String {
        bypassSecretStore.secret
    }

    var cards: [DeveloperMenuCard] {
        let activePreviewURL = normalizeDeploymentURL(environmentStore.previewURL)
        var output: [DeveloperMenuCard] = [
            DeveloperMenuCard(
                id: "DevMenuLocalCard",
                title: BackendEnvironment.local.title,
                footer: BackendURLProvider.localBaseURL.absoluteString,
                environment: .local,
                previewURL: nil,
                isSelected: environment == .local
            ),
            DeveloperMenuCard(
                id: "DevMenuStagingCard",
                title: BackendEnvironment.staging.title,
                footer: BackendURLProvider.stagingBaseURL.absoluteString,
                environment: .staging,
                previewURL: nil,
                isSelected: environment == .staging
            ),
        ]

        output.append(contentsOf: manifest.previews.map { preview in
            let previewURL = normalizeDeploymentURL(preview.url)
            let shortSHA = String((preview.headSha ?? "").prefix(7))
            return DeveloperMenuCard(
                id: "DevMenuPreviewCard_\(preview.number)",
                title: preview.title?.isEmpty == false ? preview.title! : preview.branch,
                footer: "#\(preview.number)(\(shortSHA))",
                environment: .preview,
                previewURL: preview.url,
                isSelected: environment == .preview && activePreviewURL == previewURL
            )
        })
        return output
    }

    func select(_ environment: BackendEnvironment) {
        self.environment = environment
        if environment == .preview, let url = URL(string: previewURLText), !previewURLText.isEmpty {
            environmentStore.save(environment: environment, previewURL: url)
        } else {
            environmentStore.save(environment: environment)
        }
        statusMessage = "已切换到 \(environment.title)"
    }

    func selectPreview(_ preview: PreviewManifestRow) {
        environment = .preview
        previewURLText = preview.url.absoluteString
        environmentStore.save(environment: .preview, previewURL: preview.url)
        statusMessage = "已选择 PR #\(preview.number)"
    }

    @discardableResult
    func activate(_ card: DeveloperMenuCard) async -> DeveloperMenuActivationResult {
        guard !isApplying else { return .blocked() }
        isApplying = true
        defer { isApplying = false }

        switch card.environment {
        case .local, .staging, .production:
            environmentStore.save(environment: card.environment)
            environment = card.environment
            previewURLText = ""
            statusMessage = "已切换到 \(card.environment.title)"
            return .environmentUpdated
        case .preview:
            guard let previewURL = card.previewURL else { return .blocked() }
            let secret = bypassSecretStore.secret
            guard !secret.isEmpty else {
                statusMessage = "请先保存 bypass secret"
                return .blocked(statusMessage)
            }
            lastProbeStatus = "Probing \(endpoint("/api/v1/public/health", baseURL: previewURL).absoluteString)…"
            let result = await probeHealth(baseURL: previewURL, bypassSecret: secret)
            lastProbeStatus = result.message
            guard result.ok else {
                statusMessage = "Cannot reach /api/v1/public/health"
                return .blocked(statusMessage)
            }
            environmentStore.save(environment: .preview, previewURL: previewURL)
            environment = .preview
            previewURLText = previewURL.absoluteString
            statusMessage = "已选择 \(card.footer)"
            return .environmentUpdated
        }
    }

    func saveBypassSecret(_ value: String) {
        bypassSecretStore.save(value)
        statusMessage = bypassSecretStore.secret.isEmpty ? "已清除 bypass secret" : "已保存 bypass secret"
    }

    func clearBypassSecret() {
        bypassSecretStore.clear()
        statusMessage = "已清除 bypass secret"
    }

    func refreshManifest() async {
        do {
            manifest = try await manifestClient.fetch()
            statusMessage = manifest.previews.isEmpty ? "暂无 Preview" : "已刷新 \(manifest.previews.count) 个 Preview"
        } catch {
            statusMessage = "Preview 刷新失败"
        }
    }

    func probeHealth() async {
        let result = await probeHealth(baseURL: urlProvider.effectiveBaseURL(), bypassSecret: bypassSecretStore.secret)
        lastProbeStatus = result.message
    }

    private func normalizeDeploymentURL(_ url: URL?) -> String {
        guard let url else { return "" }
        var value = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private func probeHealth(baseURL: URL, bypassSecret: String) async -> (ok: Bool, message: String) {
        let url = endpoint("/api/v1/public/health", baseURL: baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if !bypassSecret.isEmpty {
            request.setValue(bypassSecret, forHTTPHeaderField: BackendHeaderProvider.vercelBypassHeader)
        }
        do {
            let (_, response) = try await transport.data(for: request)
            return (response.statusCode == 200, "\(url.absoluteString) → HTTP \(response.statusCode)")
        } catch {
            return (false, "\(url.absoluteString) → unreachable (\(error.localizedDescription))")
        }
    }
}

struct HTTPDeviceBindingClient: DeviceBindingClienting, Sendable {
    private let baseURLProvider: any BackendURLProviding
    private let headerProvider: any BackendHeaderProviding
    private let transport: any HTTPTransporting

    init(
        baseURL: URL = CloudAPIEnvironment.defaultBaseURL,
        transport: any HTTPTransporting = URLSessionHTTPTransport(),
        headerProvider: any BackendHeaderProviding = BackendHeaderProvider()
    ) {
        baseURLProvider = StaticBackendURLProvider(baseURL)
        self.headerProvider = headerProvider
        self.transport = transport
    }

    init(
        baseURLProvider: any BackendURLProviding,
        headerProvider: any BackendHeaderProviding = BackendHeaderProvider(),
        transport: any HTTPTransporting = URLSessionHTTPTransport()
    ) {
        self.baseURLProvider = baseURLProvider
        self.headerProvider = headerProvider
        self.transport = transport
    }

    func redeem(pairingInput: String, deviceId: String) async throws -> PairRedeemResponse {
        let pairing = try PairingInput.parse(pairingInput)
        var request = URLRequest(url: endpoint("/api/v1/public/pair/redeem", baseURL: baseURLProvider.effectiveBaseURL()))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headerProvider.apply(to: &request)
        request.httpBody = try JSONEncoder.snakeCase.encode(pairing.requestBody(deviceId: deviceId))

        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 200 else {
            throw CloudHTTPError.unexpectedStatus(response.statusCode)
        }
        return try JSONDecoder.snakeCase.decode(PairRedeemResponse.self, from: data)
    }
}

private func endpoint(_ path: String, baseURL: URL) -> URL {
    URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
}

/// Builds `/api/v1/family/{familyId}{suffix}` with a percent-encoded path segment (e.g. `suffix` = `/profile`).
private func familyScopedAPIPath(suffix: String, familyId: String) -> String {
    let segment = familyId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? familyId
    return "/api/v1/family/\(segment)\(suffix)"
}

extension PairRedeemResponse {
    static let demoBinding = PairRedeemResponse(
        bindingId: "binding-demo",
        familyId: "family-demo",
        childProfileId: "child-demo",
        nickname: "小明测试46373",
        avatarEmoji: "🦁",
        deviceToken: "device-token-demo-not-a-secret"
    )
}

struct CloudCredentials: Codable, Equatable {
    var bindingId: String
    var familyId: String
    var childProfileId: String
    var nickname: String
    var avatarEmoji: String
    var deviceToken: String
    var pairedAt: Date?
    var apiBaseURL: String?
}

final class CloudCredentialsStore {
    static let deviceTokenKey = "wordMagicCloudDeviceToken"

    private let metadataKey = "wordMagicCloudCredentialsMetadata"
    private let secureStore: SecureStore
    private let defaults: UserDefaults

    init(secureStore: SecureStore = KeychainSecureStore(), defaults: UserDefaults = .standard) {
        self.secureStore = secureStore
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-UITestResetState") {
            clear()
        }
    }

    var credentials: CloudCredentials? {
        guard let token = secureStore.string(forKey: Self.deviceTokenKey),
              let data = defaults.data(forKey: metadataKey),
              let metadata = try? JSONDecoder().decode(Metadata.self, from: data)
        else {
            return nil
        }
        return CloudCredentials(
            bindingId: metadata.bindingId,
            familyId: metadata.familyId,
            childProfileId: metadata.childProfileId,
            nickname: metadata.nickname,
            avatarEmoji: metadata.avatarEmoji,
            deviceToken: token,
            pairedAt: metadata.pairedAt,
            apiBaseURL: metadata.apiBaseURL
        )
    }

    func save(_ response: PairRedeemResponse, apiBaseURL: URL? = nil) {
        save(CloudCredentials(
            bindingId: response.bindingId,
            familyId: response.familyId,
            childProfileId: response.childProfileId,
            nickname: response.nickname,
            avatarEmoji: response.avatarEmoji,
            deviceToken: response.deviceToken,
            pairedAt: Date(),
            apiBaseURL: apiBaseURL?.absoluteString
        ))
    }

    func save(_ credentials: CloudCredentials) {
        secureStore.set(credentials.deviceToken, forKey: Self.deviceTokenKey)
        let metadata = Metadata(
            bindingId: credentials.bindingId,
            familyId: credentials.familyId,
            childProfileId: credentials.childProfileId,
            nickname: credentials.nickname,
            avatarEmoji: credentials.avatarEmoji,
            pairedAt: credentials.pairedAt ?? Date(),
            apiBaseURL: credentials.apiBaseURL
        )
        if let data = try? JSONEncoder().encode(metadata) {
            defaults.set(data, forKey: metadataKey)
        }
    }

    func clear() {
        secureStore.remove(forKey: Self.deviceTokenKey)
        defaults.removeObject(forKey: metadataKey)
    }

    private struct Metadata: Codable, Equatable {
        var bindingId: String
        var familyId: String
        var childProfileId: String
        var nickname: String
        var avatarEmoji: String
        var pairedAt: Date?
        var apiBaseURL: String?
    }
}

final class DeviceIdProvider {
    static let deviceIdKey = "wordMagicCloudDeviceId"

    private let secureStore: SecureStore

    init(secureStore: SecureStore = KeychainSecureStore()) {
        self.secureStore = secureStore
    }

    func deviceId() -> String {
        if let existing = secureStore.string(forKey: Self.deviceIdKey) {
            return existing
        }
        let created = UUID().uuidString.lowercased()
        secureStore.set(created, forKey: Self.deviceIdKey)
        return created
    }

    func sourceLabel() -> String {
        "Keychain (持久)"
    }
}

struct PackLayerFixture: Codable, Equatable {
    var status: Int
    var headers: PackLayerHeaders
    var body: RemotePackPayload?
}

struct PackLayerHeaders: Codable, Equatable {
    var eTag: String?

    enum CodingKeys: String, CodingKey {
        case eTag = "ETag"
    }
}

struct RemotePackPayload: Codable, Equatable {
    var packs: [RemotePack]
}

struct RemotePack: Codable, Equatable {
    var packId: String
    var name: String
    var description: String?
    var version: Int?
    var publishedAt: Date?
    var scene: SceneMetadata?
    var words: [WordEntry]

    func pack(source: PackSource) -> Pack {
        Pack(
            id: packId,
            title: name,
            subtitle: description ?? "\(words.count) words",
            story: description ?? name,
            source: source,
            version: version ?? 1,
            publishedAt: publishedAt,
            scene: scene ?? .empty,
            words: words
        )
    }
}

struct PackLayerCache: Codable, Equatable {
    var etag: String?
    var packs: [Pack]
}

enum PackLayer: String, Codable {
    case global
    case family

    var source: PackSource {
        switch self {
        case .global: .global
        case .family: .family
        }
    }
}

enum PackSyncError: Error, Equatable {
    case bindingGone
    case missingBody
    case unsupportedStatus(Int)
}

struct PackSyncClient {
    func apply(
        status: Int,
        etag: String?,
        body: RemotePackPayload?,
        source: PackSource,
        cached: PackLayerCache?
    ) throws -> PackLayerCache? {
        switch status {
        case 200:
            guard let body else { throw PackSyncError.missingBody }
            return PackLayerCache(
                etag: etag,
                packs: body.packs.map { $0.pack(source: source) }
            )
        case 204:
            return nil
        case 304, 401, 403:
            return cached
        case 410:
            throw PackSyncError.bindingGone
        case 500...599:
            return cached
        default:
            throw PackSyncError.unsupportedStatus(status)
        }
    }
}

final class FileBackedPackLayerStore {
    private let directory: URL

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("WordMagicGame/PackLayers", isDirectory: true)) {
        self.directory = directory
    }

    func load(layer: PackLayer) throws -> PackLayerCache? {
        let url = fileURL(for: layer)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.snakeCase.decode(PackLayerCache.self, from: data)
    }

    func save(_ cache: PackLayerCache?, layer: PackLayer) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(for: layer)
        guard let cache else {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        let data = try JSONEncoder.snakeCase.encode(cache)
        try data.write(to: url, options: [.atomic])
    }

    func clear() throws {
        try save(nil, layer: .global)
        try save(nil, layer: .family)
    }

    private func fileURL(for layer: PackLayer) -> URL {
        directory.appendingPathComponent("\(layer.rawValue).json")
    }
}

protocol PackLayerClienting: Sendable {
    func fetchGlobal(cached: PackLayerCache?) async throws -> PackLayerCache?
    func fetchFamily(familyId: String, deviceToken: String, cached: PackLayerCache?) async throws -> PackLayerCache?
}

struct HTTPPackLayerClient: PackLayerClienting, Sendable {
    private let baseURLProvider: any BackendURLProviding
    private let headerProvider: any BackendHeaderProviding
    private let transport: any HTTPTransporting
    private let syncClient = PackSyncClient()

    init(
        baseURL: URL = CloudAPIEnvironment.defaultBaseURL,
        transport: any HTTPTransporting = URLSessionHTTPTransport(),
        headerProvider: any BackendHeaderProviding = BackendHeaderProvider()
    ) {
        baseURLProvider = StaticBackendURLProvider(baseURL)
        self.headerProvider = headerProvider
        self.transport = transport
    }

    init(
        baseURLProvider: any BackendURLProviding,
        headerProvider: any BackendHeaderProviding = BackendHeaderProvider(),
        transport: any HTTPTransporting = URLSessionHTTPTransport()
    ) {
        self.baseURLProvider = baseURLProvider
        self.headerProvider = headerProvider
        self.transport = transport
    }

    func fetchGlobal(cached: PackLayerCache?) async throws -> PackLayerCache? {
        try await fetch(path: "/api/v1/public/global-packs/latest.json", deviceToken: nil, source: .global, cached: cached)
    }

    func fetchFamily(familyId: String, deviceToken: String, cached: PackLayerCache?) async throws -> PackLayerCache? {
        guard !familyId.isEmpty else { throw CloudHTTPError.familyIdRequired }
        let path = familyScopedAPIPath(suffix: "/family-packs/latest.json", familyId: familyId)
        return try await fetch(path: path, deviceToken: deviceToken, source: .family, cached: cached)
    }

    private func fetch(path: String, deviceToken: String?, source: PackSource, cached: PackLayerCache?) async throws -> PackLayerCache? {
        var request = URLRequest(url: endpoint(path, baseURL: baseURLProvider.effectiveBaseURL()))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let deviceToken {
            request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        }
        if let etag = cached?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        headerProvider.apply(to: &request)

        do {
            let (data, response) = try await transport.data(for: request)
            let body: RemotePackPayload?
            if data.isEmpty {
                body = nil
            } else {
                body = try JSONDecoder.snakeCase.decode(RemotePackPayload.self, from: data)
            }
            let etag = response.value(forHTTPHeaderField: "ETag")
            return try syncClient.apply(status: response.statusCode, etag: etag, body: body, source: source, cached: cached)
        } catch let error as PackSyncError {
            throw error
        } catch {
            return cached
        }
    }
}

struct DemoPackLayerClient: PackLayerClienting, Sendable {
    private let syncClient = PackSyncClient()

    func fetchGlobal(cached: PackLayerCache?) async throws -> PackLayerCache? {
        let response = try JSONDecoder.snakeCase.decode(PackLayerFixture.self, from: DemoPackLayerFixtures.global)
        return try syncClient.apply(
            status: response.status,
            etag: response.headers.eTag,
            body: response.body,
            source: .global,
            cached: cached
        )
    }

    func fetchFamily(familyId: String, deviceToken: String, cached: PackLayerCache?) async throws -> PackLayerCache? {
        let response = try JSONDecoder.snakeCase.decode(PackLayerFixture.self, from: DemoPackLayerFixtures.family)
        return try syncClient.apply(
            status: response.status,
            etag: response.headers.eTag,
            body: response.body,
            source: .family,
            cached: cached
        )
    }
}

enum DemoPackLayerFixtures {
    static let global = Data("""
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
              { "id": "space-star", "word": "star", "meaningZh": "星星", "category": "space", "difficulty": 1 },
              { "id": "space-moon", "word": "moon", "meaningZh": "月亮", "category": "space", "difficulty": 1 }
            ]
          }
        ]
      }
    }
    """.utf8)

    static let family = Data("""
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
            "description": "家庭自定义点心单词",
            "version": 1,
            "schema_version": 1,
            "words": [
              { "id": "snack-cookie", "word": "cookie", "meaningZh": "饼干", "category": "snacks", "difficulty": 1 },
              { "id": "snack-juice", "word": "juice", "meaningZh": "果汁", "category": "snacks", "difficulty": 1 }
            ]
          }
        ]
      }
    }
    """.utf8)
}

struct WordStatsSyncPayload: Codable, Equatable {
    var items: [WordStatSyncItem]
    var syncedThroughMs: Int

    static func from(recorder: LearningRecorder, syncedThroughMs: Int) -> WordStatsSyncPayload {
        let items = recorder.statsByWordId.values
            .sorted { $0.wordId < $1.wordId }
            .map(WordStatSyncItem.init(stat:))
        return WordStatsSyncPayload(items: items, syncedThroughMs: syncedThroughMs)
    }
}

struct WordStatsSyncResponse: Codable, Equatable {
    var accepted: Int
    var rejected: Int
    var serverPulls: [WordStatSyncItem]
    var serverNowMs: Int

    private enum CodingKeys: String, CodingKey {
        case accepted
        case rejected
        case serverPulls
        case serverNowMs
    }

    init(accepted: Int, rejected: Int, serverPulls: [WordStatSyncItem], serverNowMs: Int) {
        self.accepted = accepted
        self.rejected = rejected
        self.serverPulls = serverPulls
        self.serverNowMs = serverNowMs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accepted = try container.decodeFlexibleCount(forKey: .accepted)
        rejected = try container.decodeFlexibleCount(forKey: .rejected)
        serverPulls = try container.decodeIfPresent([WordStatSyncItem].self, forKey: .serverPulls) ?? []
        serverNowMs = try container.decode(Int.self, forKey: .serverNowMs)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accepted, forKey: .accepted)
        try container.encode(rejected, forKey: .rejected)
        try container.encode(serverPulls, forKey: .serverPulls)
        try container.encode(serverNowMs, forKey: .serverNowMs)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleCount(forKey key: Key) throws -> Int {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let values = try? decodeIfPresent([String].self, forKey: key) {
            return values.count
        }
        return 0
    }
}

protocol WordStatsSyncClienting: Sendable {
    func sync(payload: WordStatsSyncPayload, familyId: String, deviceToken: String) async throws -> WordStatsSyncResponse
}

struct HTTPWordStatsSyncClient: WordStatsSyncClienting, Sendable {
    private let baseURLProvider: any BackendURLProviding
    private let headerProvider: any BackendHeaderProviding
    private let transport: any HTTPTransporting

    init(
        baseURL: URL = CloudAPIEnvironment.defaultBaseURL,
        transport: any HTTPTransporting = URLSessionHTTPTransport(),
        headerProvider: any BackendHeaderProviding = BackendHeaderProvider()
    ) {
        baseURLProvider = StaticBackendURLProvider(baseURL)
        self.headerProvider = headerProvider
        self.transport = transport
    }

    init(
        baseURLProvider: any BackendURLProviding,
        headerProvider: any BackendHeaderProviding = BackendHeaderProvider(),
        transport: any HTTPTransporting = URLSessionHTTPTransport()
    ) {
        self.baseURLProvider = baseURLProvider
        self.headerProvider = headerProvider
        self.transport = transport
    }

    func sync(payload: WordStatsSyncPayload, familyId: String, deviceToken: String) async throws -> WordStatsSyncResponse {
        guard !familyId.isEmpty else { throw CloudHTTPError.familyIdRequired }
        let path = familyScopedAPIPath(suffix: "/word-stats/sync", familyId: familyId)
        var request = URLRequest(url: endpoint(path, baseURL: baseURLProvider.effectiveBaseURL()))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        headerProvider.apply(to: &request)
        request.httpBody = try JSONEncoder.snakeCase.encode(payload)

        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 200 else {
            throw CloudHTTPError.unexpectedStatus(response.statusCode)
        }
        return try JSONDecoder.snakeCase.decode(WordStatsSyncResponse.self, from: data)
    }
}

struct MockWordStatsSyncClient: WordStatsSyncClienting, Sendable {
    func sync(payload: WordStatsSyncPayload, familyId: String, deviceToken: String) async throws -> WordStatsSyncResponse {
        WordStatsSyncResponse(
            accepted: payload.items.count,
            rejected: 0,
            serverPulls: [],
            serverNowMs: Int((Date().timeIntervalSince1970 * 1000).rounded())
        )
    }
}

final class WordStatsSyncStateStore {
    private let defaults: UserDefaults
    private let syncedThroughKey = "wordMagicWordStatsSyncedThroughMs"
    private let needsRetryKey = "wordMagicWordStatsNeedsRetry"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-UITestResetState") {
            defaults.removeObject(forKey: syncedThroughKey)
            defaults.removeObject(forKey: needsRetryKey)
        }
    }

    var syncedThroughMs: Int {
        defaults.integer(forKey: syncedThroughKey)
    }

    var needsRetry: Bool {
        defaults.bool(forKey: needsRetryKey)
    }

    func markSuccess(serverNowMs: Int) {
        defaults.set(serverNowMs, forKey: syncedThroughKey)
        defaults.set(false, forKey: needsRetryKey)
    }

    func markFailure() {
        defaults.set(true, forKey: needsRetryKey)
    }
}

protocol DeviceUnbindClienting: Sendable {
    func unbind(familyId: String, deviceToken: String) async throws
}

struct HTTPDeviceUnbindClient: DeviceUnbindClienting, Sendable {
    private let baseURLProvider: any BackendURLProviding
    private let headerProvider: any BackendHeaderProviding
    private let transport: any HTTPTransporting

    init(
        baseURL: URL = CloudAPIEnvironment.defaultBaseURL,
        transport: any HTTPTransporting = URLSessionHTTPTransport(),
        headerProvider: any BackendHeaderProviding = BackendHeaderProvider()
    ) {
        baseURLProvider = StaticBackendURLProvider(baseURL)
        self.headerProvider = headerProvider
        self.transport = transport
    }

    init(
        baseURLProvider: any BackendURLProviding,
        headerProvider: any BackendHeaderProviding = BackendHeaderProvider(),
        transport: any HTTPTransporting = URLSessionHTTPTransport()
    ) {
        self.baseURLProvider = baseURLProvider
        self.headerProvider = headerProvider
        self.transport = transport
    }

    func unbind(familyId: String, deviceToken: String) async throws {
        guard !familyId.isEmpty else { throw CloudHTTPError.familyIdRequired }
        let path = familyScopedAPIPath(suffix: "/unbind", familyId: familyId)
        var request = URLRequest(url: endpoint(path, baseURL: baseURLProvider.effectiveBaseURL()))
        request.httpMethod = "POST"
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        headerProvider.apply(to: &request)
        let (_, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw CloudHTTPError.unexpectedStatus(response.statusCode)
        }
    }
}

struct MockDeviceUnbindClient: DeviceUnbindClienting, Sendable {
    func unbind(familyId: String, deviceToken: String) async throws {}
}

struct ChildProfileUpdateResponse: Codable, Equatable {
    var profileId: String
    var familyId: String
    var nickname: String
    var avatarEmoji: String
    var updatedAt: Date?
}

private struct ChildProfileUpdateRequest: Codable, Equatable {
    var nickname: String
    var avatarEmoji: String?
}

protocol ChildProfileClienting: Sendable {
    func update(nickname: String, avatarEmoji: String?, familyId: String, deviceToken: String) async throws -> ChildProfileUpdateResponse
}

struct HTTPChildProfileClient: ChildProfileClienting, Sendable {
    private let baseURLProvider: any BackendURLProviding
    private let headerProvider: any BackendHeaderProviding
    private let transport: any HTTPTransporting

    init(
        baseURL: URL = CloudAPIEnvironment.defaultBaseURL,
        transport: any HTTPTransporting = URLSessionHTTPTransport(),
        headerProvider: any BackendHeaderProviding = BackendHeaderProvider()
    ) {
        baseURLProvider = StaticBackendURLProvider(baseURL)
        self.headerProvider = headerProvider
        self.transport = transport
    }

    init(
        baseURLProvider: any BackendURLProviding,
        headerProvider: any BackendHeaderProviding = BackendHeaderProvider(),
        transport: any HTTPTransporting = URLSessionHTTPTransport()
    ) {
        self.baseURLProvider = baseURLProvider
        self.headerProvider = headerProvider
        self.transport = transport
    }

    func update(nickname: String, avatarEmoji: String?, familyId: String, deviceToken: String) async throws -> ChildProfileUpdateResponse {
        guard !familyId.isEmpty else { throw CloudHTTPError.familyIdRequired }
        let path = familyScopedAPIPath(suffix: "/profile", familyId: familyId)
        var request = URLRequest(url: endpoint(path, baseURL: baseURLProvider.effectiveBaseURL()))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        headerProvider.apply(to: &request)
        request.httpBody = try JSONEncoder.snakeCase.encode(ChildProfileUpdateRequest(nickname: nickname, avatarEmoji: avatarEmoji))

        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 200 else {
            throw CloudHTTPError.unexpectedStatus(response.statusCode)
        }
        return try JSONDecoder.snakeCase.decode(ChildProfileUpdateResponse.self, from: data)
    }
}

struct MockChildProfileClient: ChildProfileClienting, Sendable {
    func update(nickname: String, avatarEmoji: String?, familyId: String, deviceToken: String) async throws -> ChildProfileUpdateResponse {
        ChildProfileUpdateResponse(
            profileId: PairRedeemResponse.demoBinding.childProfileId,
            familyId: PairRedeemResponse.demoBinding.familyId,
            nickname: nickname,
            avatarEmoji: avatarEmoji ?? PairRedeemResponse.demoBinding.avatarEmoji,
            updatedAt: Date()
        )
    }
}

struct WordStatSyncItem: Codable, Equatable {
    var wordId: String
    var seenCount: Int
    var correctCount: Int
    var wrongCount: Int
    var lastAnsweredMs: Int
    var lastCorrectMs: Int?
    var nextReviewMs: Int?
    var memoryState: String
    var consecutiveCorrect: Int
    var consecutiveWrong: Int
    var mastery: Double

    init(stat: WordLearningStat) {
        wordId = stat.wordId
        seenCount = stat.attempts
        correctCount = stat.correct
        wrongCount = max(stat.attempts - stat.correct, 0)
        lastAnsweredMs = Self.ms(stat.lastSeenAt)
        lastCorrectMs = stat.correct > 0 ? lastAnsweredMs : nil
        nextReviewMs = lastAnsweredMs + 86_400_000
        consecutiveCorrect = stat.correct == stat.attempts ? stat.correct : 0
        consecutiveWrong = stat.correct == 0 ? wrongCount : 0
        mastery = min(max(stat.accuracy, 0), 1)
        if stat.attempts >= 3 && stat.accuracy >= 0.9 {
            memoryState = "mastered"
        } else if stat.attempts > 0 {
            memoryState = "learning"
        } else {
            memoryState = "new"
        }
    }

    private static func ms(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1000).rounded())
    }
}
