import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct ParentAdminView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var stats: ParentStats?
    @State private var drafts = [LessonDraft.fixtureReviewedDraft]
    @State private var notes = ""
    @State private var busy = false
    @State private var importProgress = "准备就绪"
    @State private var importError = ""
    @State private var importSuccess = ""
    @State private var galleryItem: PhotosPickerItem?
    @State private var showingCamera = false

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

                Text(coordinator.parentAdminUsesLocalMock ? "本地模拟家长服务" : "云端家长服务")
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
                        Button("拍照导入") {
                            if coordinator.parentAdminUsesLocalMock {
                                coordinator.openLessonReview()
                            } else if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                showingCamera = true
                            } else {
                                importError = "当前设备不可用相机，请从相册导入"
                            }
                        }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("ParentAdminPickCameraButton")
                        if coordinator.parentAdminUsesLocalMock {
                            Button("从相册导入") { coordinator.openLessonReview() }
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.red)
                                .accessibilityIdentifier("ParentAdminPickGalleryButton")
                        } else {
                            PhotosPicker(selection: $galleryItem, matching: .images, photoLibrary: .shared()) {
                                Text("从相册导入")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.red)
                            .accessibilityIdentifier("ParentAdminPickGalleryButton")
                        }
                    }
                    Text(importProgress)
                        .font(.caption)
                        .accessibilityIdentifier("ParentAdminImportProgress")
                    Text(importError)
                        .font(.caption)
                        .foregroundStyle(AppTheme.red)
                        .accessibilityIdentifier("ParentAdminImportError")
                    Text(importSuccess)
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
                    Button(busy ? "发布中..." : "发布") {
                        Task { await publishPack() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.red)
                    .disabled(busy)
                    .accessibilityIdentifier("ParentAdminPublishButton")
                    Text(coordinator.parentAdminMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.mint)
                        .accessibilityIdentifier("ParentAdminPublishSummary")
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
            .padding(.top, AppTheme.portraitPageTopPadding)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.page)
        .task { await load() }
        .onChange(of: galleryItem) { _, newValue in
            guard let newValue else { return }
            Task { await importGalleryItem(newValue) }
        }
        .sheet(isPresented: $showingCamera) {
            CameraLessonImagePicker { image in
                Task { await importPickedImage(image) }
            }
        }
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

    private func publishPack() async {
        busy = true
        defer { busy = false }
        do {
            let published = try await coordinator.parentClient.publishPack(notes: notes)
            notes = ""
            coordinator.parentAdminMessage = "已发布词包 v\(published.version)"
            await load()
        } catch {
            coordinator.parentAdminMessage = "发布失败，请稍后重试"
        }
    }

    private func importGalleryItem(_ item: PhotosPickerItem) async {
        defer { galleryItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                importError = "图片读取失败"
                return
            }
            let contentType = item.supportedContentTypes.first ?? .jpeg
            await importPickedImage(
                PickedLessonImage(
                    data: data,
                    filename: "lesson.\(Self.fileExtension(for: contentType))",
                    mimeType: Self.mimeType(for: contentType),
                    sizeBytes: data.count
                )
            )
        } catch {
            importError = "图片读取失败"
        }
    }

    private func importPickedImage(_ image: PickedLessonImage) async {
        importProgress = "上传中..."
        importError = ""
        importSuccess = ""
        busy = true
        defer { busy = false }
        do {
            let draft = try await coordinator.importLessonImage(image)
            await load()
            if draft.status == .pending {
                importProgress = "已生成待复核草稿"
                coordinator.openLessonReview(draft: draft)
            } else {
                importProgress = "已上传，等待 AI 识别"
                importSuccess = "稍后点击刷新查看待复核草稿"
            }
        } catch ParentApiError.boundFamilyRequired {
            importProgress = "准备就绪"
            importError = "请先绑定家长账号"
        } catch ParentApiError.imageTooLarge {
            importProgress = "准备就绪"
            importError = "图片过大，请换一张"
        } catch ParentApiError.unsupportedMimeType {
            importProgress = "准备就绪"
            importError = "图片格式不支持"
        } catch {
            importProgress = "准备就绪"
            importError = "导入失败，请稍后重试"
        }
    }

    private static func mimeType(for contentType: UTType) -> String {
        if contentType.conforms(to: .png) {
            return "image/png"
        }
        if contentType.conforms(to: .webP) {
            return "image/webp"
        }
        return "image/jpeg"
    }

    private static func fileExtension(for contentType: UTType) -> String {
        if contentType.conforms(to: .png) {
            return "png"
        }
        if contentType.conforms(to: .webP) {
            return "webp"
        }
        return "jpg"
    }
}

struct LessonDraftReviewView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var editingRowId: String?
    @State private var editingWord = ""
    @State private var editingMeaning = ""

    var body: some View {
        ScrollView {
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

                LessonReviewThumbnailView(sourceImageUrl: coordinator.reviewStore.draft.sourceImageUrl)

                TextField("分类", text: Binding(
                    get: { coordinator.reviewStore.categoryLabel },
                    set: { coordinator.reviewStore.setCategoryLabel($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("LessonReviewCategoryInput")

                Text("共 \(coordinator.reviewStore.rows.count) 个候选词")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("LessonReviewCount")

                if coordinator.reviewStore.rows.isEmpty {
                    Text("暂未识别到候选词，请返回后刷新或重新导入。")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("LessonReviewEmptyWords")
                }

                ForEach(Array(coordinator.reviewStore.rows.enumerated()), id: \.element.id) { index, row in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { row.keep },
                            set: { _ in coordinator.reviewStore.toggleKeep(rowId: row.id) }
                        ))
                        .labelsHidden()
                        .accessibilityIdentifier("LessonReviewRowToggle_\(index)")
                        if editingRowId == row.id {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("英文", text: $editingWord)
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityIdentifier("LessonReviewRowWordInput_\(index)")
                                TextField("中文释义", text: $editingMeaning)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityIdentifier("LessonReviewRowMeaningInput_\(index)")
                                HStack {
                                    Button("取消") { cancelEditing() }
                                        .accessibilityIdentifier("LessonReviewRowCancel_\(index)")
                                    Button("保存") { saveEditing(rowId: row.id) }
                                        .buttonStyle(.borderedProminent)
                                        .tint(AppTheme.mint)
                                        .accessibilityIdentifier("LessonReviewRowSave_\(index)")
                                }
                            }
                        } else {
                            VStack(alignment: .leading) {
                                Text(row.word).font(.headline.weight(.bold))
                                Text(row.meaningZh).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("编辑") { beginEditing(row: row) }
                                .accessibilityIdentifier("LessonReviewRowEdit_\(index)")
                        }
                    }
                    .padding()
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                }

                HStack {
                    Button("拒绝") { Task { await coordinator.rejectLessonReview() } }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("LessonReviewRejectButton")
                    Spacer()
                    Button("审核通过") { Task { await coordinator.approveLessonReview() } }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.red)
                        .accessibilityIdentifier("LessonReviewApproveButton")
                }
                if !coordinator.parentAdminMessage.isEmpty {
                    Text(coordinator.parentAdminMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.mint)
                        .accessibilityIdentifier("LessonReviewMessage")
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontalPadding)
            .padding(.top, AppTheme.portraitPageTopPadding)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.page)
    }

    private func beginEditing(row: LessonReviewWord) {
        editingRowId = row.id
        editingWord = row.word
        editingMeaning = row.meaningZh
    }

    private func cancelEditing() {
        editingRowId = nil
        editingWord = ""
        editingMeaning = ""
    }

    private func saveEditing(rowId: String) {
        coordinator.reviewStore.edit(
            rowId: rowId,
            word: editingWord.trimmingCharacters(in: .whitespacesAndNewlines),
            meaningZh: editingMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        cancelEditing()
    }
}

private struct LessonReviewThumbnailView: View {
    let sourceImageUrl: String

    var body: some View {
        ZStack {
            if let url = URL(string: sourceImageUrl), !sourceImageUrl.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        thumbnailShell {
                            ProgressView()
                            Text("图片加载中")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                            .background(AppTheme.cream, in: RoundedRectangle(cornerRadius: 18))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    case .failure:
                        thumbnailShell {
                            Text("图片加载失败")
                                .font(.headline.weight(.bold))
                            Text("请返回后刷新或重新导入")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    @unknown default:
                        thumbnailShell {
                            Text("图片预览")
                                .font(.headline.weight(.bold))
                        }
                    }
                }
            } else {
                thumbnailShell {
                    Text("暂无原图")
                        .font(.headline.weight(.bold))
                    Text("请返回后重新导入")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("LessonReviewThumbnail")
        .accessibilityElement(children: .contain)
    }

    private func thumbnailShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(AppTheme.cream)
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .overlay(
                VStack(spacing: 8) {
                    content()
                }
            )
    }
}

private struct CameraLessonImagePicker: UIViewControllerRepresentable {
    var onImage: (PickedLessonImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraLessonImagePicker

        init(parent: CameraLessonImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            defer { parent.dismiss() }
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.86)
            else {
                return
            }
            parent.onImage(
                PickedLessonImage(
                    data: data,
                    filename: "lesson-camera.jpg",
                    mimeType: "image/jpeg",
                    sizeBytes: data.count
                )
            )
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
