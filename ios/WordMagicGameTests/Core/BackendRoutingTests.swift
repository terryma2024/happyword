import Foundation
import Testing
@testable import WordMagicGame

struct BackendRoutingTests {
    @Test func previewHeadersArePreviewOnly() {
        let provider = BackendHeaderProvider()

        #expect(provider.headers(state: BackendRouteState(env: .staging, debugSessionID: "dbg_1"), bypassSecret: "secret").isEmpty)
        let headers = provider.headers(state: BackendRouteState(env: .preview, debugSessionID: " dbg_1 "), bypassSecret: " secret ")
        #expect(headers["x-vercel-protection-bypass"] == "secret")
        #expect(headers["x-hw-debug-session"] == "dbg_1")
    }

    @Test func previewManifestPrefersBranchURL() throws {
        let json = """
        {
          "previews": [
            {
              "branch": "feature/stable",
              "title": "Feature",
              "url": "https://commit-url.vercel.app",
              "branch_url": "https://branch-url.vercel.app",
              "deployment_url": "https://commit-url.vercel.app",
              "deployment_id": "dpl_123",
              "head_sha": "abc123"
            },
            {
              "branch": "bad",
              "url": "ftp://bad"
            }
          ]
        }
        """

        let targets = try PreviewManifestClient().parse(Data(json.utf8))

        #expect(targets.map(\.id) == ["feature/stable"])
        #expect(targets.first?.url.absoluteString == "https://branch-url.vercel.app")
        #expect(targets.first?.deploymentURL?.absoluteString == "https://commit-url.vercel.app")
        #expect(targets.first?.deploymentID == "dpl_123")
        #expect(targets.first?.headSHA == "abc123")
    }
}
