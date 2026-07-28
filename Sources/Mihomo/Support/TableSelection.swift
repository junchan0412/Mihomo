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
}
