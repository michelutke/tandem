import AppKit
import Testing
@testable import TandemDesign

@MainActor
@Suite struct GlassDialogTests {
    private func makeHandle(_ calls: LockedCalls) -> GlassDialogHandle {
        GlassDialog.makeHandle(
            title: "Call",
            message: nil,
            actions: [GlassDialogAction("Answer", kind: .primary), GlassDialogAction("Decline")]
        ) { calls.values.append($0) }
    }

    @Test func choose_index_reportsOnce() {
        let calls = LockedCalls()
        let handle = makeHandle(calls)

        handle.choose(1)
        handle.choose(0)

        #expect(calls.values == [1])
    }

    @Test func choose_nilFromEscape_reportsNoChoice() {
        let calls = LockedCalls()
        let handle = makeHandle(calls)

        handle.choose(nil)

        #expect(calls.values == [nil])
    }

    @Test func close_beforeChoice_reportsNothing() {
        let calls = LockedCalls()
        let handle = makeHandle(calls)

        handle.close()
        handle.choose(0)

        #expect(calls.values.isEmpty)
    }
}

@MainActor
private final class LockedCalls {
    var values: [Int?] = []
}
