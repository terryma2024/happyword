import Foundation

struct LessonDraftReviewStore: Equatable {
    let draft: LessonDraft
    private(set) var categoryId: String
    private(set) var categoryLabel: String
    private(set) var rows: [LessonReviewWord]

    init(draft: LessonDraft) {
        self.draft = draft
        categoryId = draft.categoryId
        categoryLabel = draft.categoryLabel
        rows = draft.words
    }

    mutating func setCategoryLabel(_ value: String) {
        categoryLabel = value
    }

    mutating func toggleKeep(rowId: String) {
        guard let index = rows.firstIndex(where: { $0.id == rowId }) else { return }
        rows[index].keep.toggle()
    }

    mutating func edit(rowId: String, word: String, meaningZh: String) {
        guard let index = rows.firstIndex(where: { $0.id == rowId }) else { return }
        rows[index].word = word
        rows[index].meaningZh = meaningZh
    }

    func approvePayload() -> LessonApprovePayload {
        LessonApprovePayload(categoryId: categoryId, labelZh: categoryLabel, words: rows.filter(\.keep))
    }
}
