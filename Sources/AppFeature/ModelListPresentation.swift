import LLMKit

extension [ModelInfo] {
    /// The models a recommended-first picker should list.
    ///
    /// By default just the curated recommended set (plus the current `selection` if it
    /// isn't one, so the picker can still show it); everything when `showAll` is true.
    /// Falls back to the full list when nothing is recommended. Shared by the onboarding
    /// and Settings model pickers so they behave identically. A single flat list —
    /// macOS `Picker` flattens `Section`s, so membership is controlled directly.
    func recommendedFirst(selection: String, showAll: Bool) -> [ModelInfo] {
        let recommended = filter(\.isRecommended)
        guard !recommended.isEmpty else { return Array(self) }
        if showAll { return recommended + filter { !$0.isRecommended } }
        if let selected = first(where: { $0.id == selection }), !selected.isRecommended {
            return recommended + [selected]
        }
        return recommended
    }

    /// Whether a "Show all models" toggle is meaningful (there are both recommended and
    /// non-recommended models).
    var hasRecommendedAndOthers: Bool {
        contains(where: \.isRecommended) && contains(where: { !$0.isRecommended })
    }

    /// The free model matching `id`, if the current selection is a free model (drives the
    /// "may need a privacy setting" note).
    func freeSelection(_ id: String) -> ModelInfo? {
        first(where: { $0.id == id && $0.isFree })
    }
}
