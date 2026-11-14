import Testing
@testable import TandemDesign

@Test func dotMatrix_value82of30Dots_lightsTwentyFiveDots() {
    #expect(DotMatrix(value: 0.82, columns: 10, rows: 3).litCount == 25)
}

@Test func dotMatrix_value82_fillsBottomRowsFirstWithCurrentDotOnTopRow() {
    let matrix = DotMatrix(value: 0.82, columns: 10, rows: 3)

    #expect((0..<10).allSatisfy { matrix.dotState(row: 2, column: $0) == .lit })
    #expect((0..<10).allSatisfy { matrix.dotState(row: 1, column: $0) == .lit })
    #expect(matrix.dotState(row: 0, column: 3) == .lit)
    #expect(matrix.dotState(row: 0, column: 4) == .current)
    #expect(matrix.dotState(row: 0, column: 5) == .unlit)
}

@Test func dotMatrix_value0_hasNoLitOrCurrentDot() {
    let matrix = DotMatrix(value: 0, columns: 10, rows: 3)

    #expect((0..<3).allSatisfy { row in (0..<10).allSatisfy { matrix.dotState(row: row, column: $0) == .unlit } })
}

@Test func dotMatrix_valueAboveOne_clampsToFull() {
    #expect(DotMatrix(value: 3, columns: 10, rows: 3).litCount == 30)
}
