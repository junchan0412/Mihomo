import AppKit

enum TableSelection {
    static func reconciled<ID: Hashable>(
        _ selection: Set<ID>,
        visibleIDs: [ID],
        preferredID: ID? = nil,
        selectsFirstWhenEmpty: Bool = false
    ) -> Set<ID> {
        let visibleIDSet = Set(visibleIDs)
        let retained = selection.intersection(visibleIDSet)
        guard retained.isEmpty else { return retained }

        if let preferredID, visibleIDSet.contains(preferredID) {
            return [preferredID]
        }
        if selectsFirstWhenEmpty, let firstID = visibleIDs.first {
            return [firstID]
        }
        return []
    }

    static func updated<ID: Hashable>(
        _ selection: Set<ID>,
        clicking id: ID,
        visibleIDs: [ID],
        anchor: ID?,
        modifiers: NSEvent.ModifierFlags
    ) -> (selection: Set<ID>, anchor: ID?) {
        let normalizedModifiers = modifiers.intersection(.deviceIndependentFlagsMask)

        if normalizedModifiers.contains(.shift),
           let anchor,
           let anchorIndex = visibleIDs.firstIndex(of: anchor),
           let clickedIndex = visibleIDs.firstIndex(of: id)
        {
            let bounds = min(anchorIndex, clickedIndex)...max(anchorIndex, clickedIndex)
            let rangeSelection = Set(bounds.map { visibleIDs[$0] })
            if normalizedModifiers.contains(.command) {
                return (selection.union(rangeSelection), anchor)
            }
            return (rangeSelection, anchor)
        }

        if normalizedModifiers.contains(.command) {
            var updated = selection
            if updated.contains(id) {
                updated.remove(id)
            } else {
                updated.insert(id)
            }
            return (updated, id)
        }

        return ([id], id)
    }
}
