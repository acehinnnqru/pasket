import Foundation
import Testing
@testable import PasketCore

struct ClipboardSelectionTests {
    @Test func tabMarksSurviveNavigationAndCanBeRemovedWithoutLosingFocus() {
        let ids = (0..<4).map { _ in UUID() }
        var selection = ClipboardSelection()
        selection.selectOnly(ids[0])
        selection.toggleMark()
        #expect(selection.ids == [ids[0]])
        #expect(selection.focusedID == ids[0])
        selection.move(to: ids[1], in: ids)
        selection.toggleMark()
        selection.move(to: ids[2], in: ids)
        #expect(selection.ids == Set(ids[0...2]))
        selection.move(to: ids[1], in: ids)
        selection.toggleMark()
        selection.move(to: ids[3], in: ids)
        #expect(selection.ids == [ids[0], ids[3]])
        #expect(selection.focusedID == ids[3])
        selection.select(ids[2], in: ids)
        selection.move(to: ids[3], in: ids)
        #expect(selection.ids == [ids[3]])
    }

    @Test func hiddenMarksDoNotReturnAfterReconciliation() {
        let ids = (0..<3).map { _ in UUID() }
        var selection = ClipboardSelection()
        selection.selectOnly(ids[0])
        selection.toggleMark()
        selection.move(to: ids[1], in: ids)
        selection.reconcile(with: Array(ids[1...2]), fallback: ids[1])
        selection.move(to: ids[2], in: ids)
        #expect(selection.ids == [ids[2]])
    }

    @Test func commandTogglesIndividualItemsAndPlainClickReplacesSelection() {
        let ids = (0..<5).map { _ in UUID() }
        var selection = ClipboardSelection()
        selection.select(ids[0], in: ids)
        selection.select(ids[3], in: ids, command: true)
        #expect(selection.ids == [ids[0], ids[3]])
        selection.select(ids[0], in: ids, command: true)
        #expect(selection.ids == [ids[3]])
        selection.select(ids[2], in: ids)
        #expect(selection.ids == [ids[2]])
        selection.select(ids[2], in: ids, command: true)
        #expect(selection.ids.isEmpty)
        #expect(selection.focusedID == nil)
    }

    @Test func shiftUsesAFixedAnchorAndCanShrinkInEitherDirection() {
        let ids = (0..<6).map { _ in UUID() }
        var selection = ClipboardSelection()
        selection.select(ids[2], in: ids)
        selection.select(ids[5], in: ids, shift: true)
        #expect(selection.ids == Set(ids[2...5]))
        selection.select(ids[3], in: ids, shift: true)
        #expect(selection.ids == Set(ids[2...3]))
        selection.select(ids[0], in: ids, shift: true)
        #expect(selection.ids == Set(ids[0...2]))
        #expect(selection.anchorID == ids[2])
    }

    @Test func commandShiftAddsARangeWithoutLosingDisjointItems() {
        let ids = (0..<7).map { _ in UUID() }
        var selection = ClipboardSelection()
        selection.select(ids[0], in: ids)
        selection.select(ids[3], in: ids, command: true)
        selection.select(ids[6], in: ids, command: true, shift: true)
        #expect(selection.ids == Set([ids[0]] + Array(ids[3...6])))
        selection.select(ids[4], in: ids, command: true, shift: true)
        #expect(selection.ids == [ids[0], ids[3], ids[4]])
    }

    @Test func reconciliationRemovesHiddenItemsAndRepairsTheAnchor() {
        let ids = (0..<4).map { _ in UUID() }
        var selection = ClipboardSelection()
        selection.select(ids[0], in: ids)
        selection.select(ids[3], in: ids, command: true)
        selection.reconcile(with: Array(ids[0...2]), fallback: ids[1])
        #expect(selection.ids == [ids[0]])
        #expect(selection.focusedID == ids[0])
        #expect(selection.anchorID == ids[0])
        selection.reconcile(with: [ids[2]], fallback: ids[2])
        #expect(selection.ids == [ids[2]])
    }
}
