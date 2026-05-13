import Foundation
import os

enum BackendEnv: String, CaseIterable, Equatable {
    case production
    case staging
    case local
    case preview

    var defaultURL: URL {
        switch self {
        case .production:
            URL(string: "https://happyword.cool")!
        case .staging:
            URL(string: "https://happyword-staging.vercel.app")!
        case .local:
            URL(string: "http://127.0.0.1:8000")!
        case .preview:
            URL(string: "https://happyword.cool")!
        }
    }
}

struct PreviewTarget: Equatable, Identifiable {
    let id: String
    let title: String
    let url: URL
    let deploymentURL: URL?
    let deploymentID: String?
    let headSHA: String?
}

struct BackendRouteState: Equatable {
    var env: BackendEnv = .production
    var selectedPreview: PreviewTarget?
    var instrumentationOverrideURL: URL?
    var debugSessionID: String = ""
}

struct BackendURLProvider {
    func resolve(_ state: BackendRouteState) -> URL {
        if let instrumentationOverrideURL = state.instrumentationOverrideURL {
            return instrumentationOverrideURL
        }
        if state.env == .preview, let previewURL = state.selectedPreview?.url {
            return previewURL
        }
        return state.env.defaultURL
    }
}

struct BackendHeaderProvider {
    private let bypassHeader = "x-vercel-protection-bypass"
    private let debugSessionHeader = "x-hw-debug-session"

    func headers(state: BackendRouteState, bypassSecret: String) -> [String: String] {
        guard state.env == .preview else { return [:] }

        var result: [String: String] = [:]
        let trimmedBypass = bypassSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBypass.isEmpty {
            result[bypassHeader] = trimmedBypass
        }

        let sessionID = state.debugSessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sessionID.isEmpty {
            result[debugSessionHeader] = sessionID
        }
        return result
    }
}

struct PreviewManifestClient {
    private struct Manifest: Decodable {
        let previews: [ManifestRow]
    }

    private struct ManifestRow: Decodable {
        let branch: String?
        let pr: Int?
        let title: String?
        let url: String?
        let branchURL: String?
        let deploymentURL: String?
        let deploymentID: String?
        let headSHA: String?

        enum CodingKeys: String, CodingKey {
            case branch
            case pr
            case title
            case url
            case branchURL = "branch_url"
            case deploymentURL = "deployment_url"
            case deploymentID = "deployment_id"
            case headSHA = "head_sha"
        }
    }

    func parse(_ data: Data) throws -> [PreviewTarget] {
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        return manifest.previews.compactMap { row in
            let stableURLString = row.branchURL ?? row.url
            guard let stableURLString, let stableURL = URL(string: stableURLString), stableURL.scheme == "https" else {
                return nil
            }
            let branch = row.branch ?? "preview"
            let id = row.branch ?? row.deploymentID ?? row.url ?? stableURL.absoluteString
            let title = row.title ?? row.pr.map { "PR #\($0) \(branch)" } ?? branch
            let deploymentURL = row.deploymentURL.flatMap { URL(string: $0) }
            return PreviewTarget(
                id: id,
                title: title,
                url: stableURL,
                deploymentURL: deploymentURL,
                deploymentID: row.deploymentID,
                headSHA: row.headSHA
            )
        }
    }

    func fetch(from url: URL = URL(string: "https://happyword.cool/api/v1/preview-urls.json")!) async throws -> [PreviewTarget] {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try parse(data)
    }
}

final class DebugNetworkClient {
    private let routeState: () -> BackendRouteState
    private let bypassSecret: () -> String
    private let urlProvider: BackendURLProvider
    private let headerProvider: BackendHeaderProvider
    private let logger = Logger(subsystem: "cool.happyword.wordmagic", category: "HW_NET_DEBUG")

    init(
        routeState: @escaping () -> BackendRouteState,
        bypassSecret: @escaping () -> String,
        urlProvider: BackendURLProvider = BackendURLProvider(),
        headerProvider: BackendHeaderProvider = BackendHeaderProvider()
    ) {
        self.routeState = routeState
        self.bypassSecret = bypassSecret
        self.urlProvider = urlProvider
        self.headerProvider = headerProvider
    }

    func request(path: String, method: String = "GET", body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        let state = routeState()
        let baseURL = urlProvider.resolve(state)
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        let headers = headerProvider.headers(state: state, bypassSecret: bypassSecret())
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if headers["x-hw-debug-session"] != nil {
            logger.info("request \(method, privacy: .public) \(url.absoluteString, privacy: .public)")
        }

        let started = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if headers["x-hw-debug-session"] != nil {
            let durationMs = Int(Date().timeIntervalSince(started) * 1000)
            logger.info("response \(method, privacy: .public) \(url.path, privacy: .public) -> \(httpResponse.statusCode, privacy: .public) \(durationMs, privacy: .public)ms")
        }
        return (data, httpResponse)
    }
}
