import SwiftUI

#if DEBUG
struct DevMenuView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var env = BackendEnv.preview
    @State private var previewURL = UserDefaults.standard.string(forKey: "debug.previewURL") ?? ""
    @State private var bypassSecret = UserDefaults.standard.string(forKey: "debug.bypassSecret") ?? ""
    @State private var debugSessionID = UserDefaults.standard.string(forKey: "debug.sessionID") ?? ""
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button("返回") { coordinator.route = .config }
                    Spacer()
                    Text("Debug")
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                    Spacer()
                    Button("保存") { save() }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.red)
                        .accessibilityIdentifier("DevMenuSaveButton")
                }

                Picker("Backend", selection: $env) {
                    ForEach(BackendEnv.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("DevMenuBackendPicker")

                TextField("Preview branch URL", text: $previewURL)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .accessibilityIdentifier("DevMenuPreviewURLInput")

                SecureField("Vercel bypass secret", text: $bypassSecret)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("DevMenuBypassSecretInput")

                TextField("Debug session", text: $debugSessionID)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("DevMenuDebugSessionInput")

                HStack {
                    Button("清除") { clear() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("DevMenuClearButton")
                    Text(message)
                        .font(.headline)
                        .foregroundStyle(AppTheme.navy)
                    Spacer()
                }
            }
            .padding(.horizontal, 42)
            .padding(.vertical, 24)
        }
        .background(AppTheme.page)
    }

    private func save() {
        UserDefaults.standard.set(env.rawValue, forKey: "debug.backendEnv")
        UserDefaults.standard.set(previewURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "debug.previewURL")
        UserDefaults.standard.set(bypassSecret.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "debug.bypassSecret")
        UserDefaults.standard.set(debugSessionID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "debug.sessionID")
        message = "已保存"
    }

    private func clear() {
        previewURL = ""
        bypassSecret = ""
        debugSessionID = ""
        UserDefaults.standard.removeObject(forKey: "debug.previewURL")
        UserDefaults.standard.removeObject(forKey: "debug.bypassSecret")
        UserDefaults.standard.removeObject(forKey: "debug.sessionID")
        message = "已清除"
    }
}
#endif
