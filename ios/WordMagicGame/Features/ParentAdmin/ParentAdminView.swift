import SwiftUI

struct ParentAdminView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var stats: ParentStats?
    @State private var drafts = [LessonDraft.fixtureReviewedDraft]
    @State private var notes = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    MonsterCodexStyleBackButton(
                        action: { coordinator.route = .config },
                        accessibilityIdentifier: "ParentAdminBack"
                    )
                    Spacer()
                    Text("家长管理后台")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.navy)
                        .accessibilityIdentifier("ParentAdminTitle")
                    Spacer()
                    Color.clear.frame(width: 54, height: 54)
                }

                Text("本地模拟家长服务")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.mint)
                    .accessibilityIdentifier("ParentAdminServerLabel")

                HStack(spacing: 10) {
                    overview("单词", "\(stats?.wordCount ?? 42)")
                    overview("词包", "\(stats?.packCount ?? 3)")
                    overview("待审", "\(stats?.lessonImportDraftPending ?? 1)")
                    Button("刷新") {
                        Task { await load() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.mint)
                    .accessibilityIdentifier("ParentAdminRefresh")
                }

                card {
                    Text("课本导入")
                        .font(.headline.weight(.bold))
                    HStack {
                        Button("拍照导入") { coordinator.openLessonReview() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("ParentAdminPickCameraButton")
                        Button("从相册导入") { coordinator.openLessonReview() }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.red)
                            .accessibilityIdentifier("ParentAdminPickGalleryButton")
                    }
                    Text("准备就绪")
                        .font(.caption)
                        .accessibilityIdentifier("ParentAdminImportProgress")
                    Text("")
                        .accessibilityIdentifier("ParentAdminImportError")
                    Text("模拟导入会生成一个审核草稿")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mint)
                        .accessibilityIdentifier("ParentAdminImportSuccess")
                }

                Text("待审核草稿")
                    .font(.headline.weight(.bold))
                    .accessibilityIdentifier("ParentAdminPendingTitle")
                ForEach(drafts) { draft in
                    Button("\(draft.categoryLabel) · \(draft.words.count) 个单词") {
                        coordinator.openLessonReview(draft: draft)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("LessonDraftReviewLink_\(draft.id)")
                }

                card {
                    Text("发布新词包")
                        .font(.headline.weight(.bold))
                    TextField("备注", text: $notes)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("ParentAdminPublishNotes")
                    Button("发布") {
                        coordinator.parentAdminMessage = "已发布词包 v7"
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.red)
                    .accessibilityIdentifier("ParentAdminPublishButton")
                    Text(coordinator.parentAdminMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.mint)
                        .accessibilityIdentifier("ParentAdminPublishSummary")
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
            .padding(.vertical, 20)
        }
        .background(AppTheme.page)
        .task { await load() }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cream, in: RoundedRectangle(cornerRadius: 18))
    }

    private func overview(_ title: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.title3.weight(.heavy))
            Text(title).font(.caption.weight(.semibold))
        }
        .frame(width: 74)
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private func load() async {
        stats = try? await coordinator.parentClient.fetchStats()
        drafts = (try? await coordinator.parentClient.fetchLessonDrafts().items) ?? drafts
    }
}

struct LessonDraftReviewView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                MonsterCodexStyleBackButton(
                    action: { coordinator.route = .parentAdmin },
                    accessibilityIdentifier: "LessonReviewBack"
                )
                Spacer()
                Text("课本识别审核")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                    .accessibilityIdentifier("LessonReviewTitle")
                Spacer()
                Color.clear.frame(width: 54, height: 54)
            }

            RoundedRectangle(cornerRadius: 18)
                .fill(AppTheme.cream)
                .frame(height: 104)
                .overlay(Text("图片预览").font(.headline.weight(.bold)))
                .accessibilityIdentifier("LessonReviewThumbnail")

            TextField("分类", text: Binding(
                get: { coordinator.reviewStore.categoryLabel },
                set: { coordinator.reviewStore.setCategoryLabel($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("LessonReviewCategoryInput")

            ForEach(Array(coordinator.reviewStore.rows.enumerated()), id: \.element.id) { index, row in
                HStack {
                    Toggle("", isOn: Binding(
                        get: { row.keep },
                        set: { _ in coordinator.reviewStore.toggleKeep(rowId: row.id) }
                    ))
                    .labelsHidden()
                    .accessibilityIdentifier("LessonReviewRowToggle_\(index)")
                    VStack(alignment: .leading) {
                        Text(row.word).font(.headline.weight(.bold))
                        Text(row.meaningZh).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("编辑") {}
                        .accessibilityIdentifier("LessonReviewRowEdit_\(index)")
                }
                .padding()
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("LessonReviewRow_\(index)")
            }

            HStack {
                Button("拒绝") { coordinator.route = .parentAdmin }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("LessonReviewRejectButton")
                Spacer()
                Button("审核通过") { coordinator.approveLessonReview() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.red)
                    .accessibilityIdentifier("LessonReviewApproveButton")
            }
        }
        .padding(.horizontal, AppTheme.pageHorizontalPadding)
        .padding(.vertical, 20)
        .background(AppTheme.page)
    }
}
