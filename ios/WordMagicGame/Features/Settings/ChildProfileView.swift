import SwiftUI

struct ChildProfileView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var nickname = ""
    @FocusState private var isNicknameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                MonsterCodexStyleBackButton(
                    action: { coordinator.route = .home },
                    accessibilityIdentifier: "ChildProfileBackButton"
                )
                Spacer()
            }

            HStack(spacing: 24) {
                Text(coordinator.currentChildAvatarEmoji())
                    .font(.system(size: 62))
                    .frame(width: 104, height: 104)
                    .background(AppTheme.paleBlue, in: Circle())

                VStack(alignment: .leading, spacing: 12) {
                    Text("学习档案")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.navy)
                    TextField("学习者名字", text: $nickname)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .frame(maxWidth: 360)
                        .focused($isNicknameFocused)
                        .accessibilityIdentifier("学习者名字")
                    HStack(spacing: 14) {
                        Button("保存名字") {
                            isNicknameFocused = false
                            Task {
                                await coordinator.updateChildNickname(nickname)
                            }
                        }
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.white)
                        .frame(width: 132, height: 44)
                        .background(AppTheme.red, in: Capsule())
                        .buttonStyle(.plain)

                        Text(coordinator.bindingMessage)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(coordinator.bindingMessage.hasPrefix("已保存") ? AppTheme.mint : AppTheme.red)
                            .accessibilityIdentifier("ChildProfileMessage")
                    }
                }
                Spacer()
            }
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
            .padding(.vertical, 24)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18).stroke(Color.gray.opacity(0.16), lineWidth: 1.2)
            }

            Spacer()
        }
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.top, AppTheme.portraitPageTopPadding)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.page)
        .ignoresSafeArea(.keyboard)
        .onAppear {
            nickname = coordinator.currentChildNickname()
        }
    }
}
