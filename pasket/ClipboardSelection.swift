import Foundation

nonisolated struct ClipboardSelection {
    private(set) var ids: Set<UUID> = []
    private(set) var focusedID: UUID?
    private(set) var anchorID: UUID?
    private var rangeBase: Set<UUID>?
    private var addsRange = false

    mutating func focus(_ id: UUID) {
        if ids.contains(id) { focusedID = id }
    }

    mutating func selectOnly(_ id: UUID?) {
        ids = Set(id.map { [$0] } ?? [])
        focusedID = id
        anchorID = id
        rangeBase = nil
    }

    mutating func select(_ id: UUID, in order: [UUID], command: Bool = false, shift: Bool = false) {
        guard let end = order.firstIndex(of: id) else { return }
        if shift, let anchorID, let start = order.firstIndex(of: anchorID) {
            if rangeBase == nil || addsRange != command {
                rangeBase = command ? ids : []
                addsRange = command
            }
            ids = (rangeBase ?? []).union(order[min(start, end)...max(start, end)])
            focusedID = id
        } else if command {
            if !ids.insert(id).inserted { ids.remove(id) }
            focusedID = ids.contains(id) ? id : order.first(where: { ids.contains($0) })
            anchorID = id
            rangeBase = nil
        } else {
            selectOnly(id)
        }
    }

    mutating func reconcile(with order: [UUID], fallback: UUID? = nil) {
        ids.formIntersection(order)
        rangeBase = rangeBase.map { $0.intersection(order) }
        if ids.isEmpty {
            selectOnly(fallback)
        } else {
            if focusedID.map({ ids.contains($0) }) != true {
                focusedID = order.first(where: { ids.contains($0) })
            }
            if anchorID.map({ order.contains($0) }) != true {
                anchorID = focusedID
                rangeBase = nil
            }
        }
    }
}
