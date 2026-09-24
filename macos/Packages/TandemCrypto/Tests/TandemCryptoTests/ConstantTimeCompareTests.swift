import Foundation
import Testing
@testable import TandemCrypto

@Test func constantTimeEquals_equalArrays_returnsTrue() {
    let lhs = Data([1, 2, 3, 4, 5])
    let rhs = Data([1, 2, 3, 4, 5])

    #expect(constantTimeEquals(lhs, rhs))
}

@Test func constantTimeEquals_mismatchAtFirstByte_returnsFalseAfterFullScan() {
    let lhs = Data([9, 2, 3, 4, 5])
    let rhs = Data([1, 2, 3, 4, 5])
    let counter = ByteAccessCounter()

    let result = constantTimeEquals(lhs, rhs, counter: counter)

    #expect(result == false)
    #expect(counter.accessCount == 2 * lhs.count)
}

@Test func constantTimeEquals_mismatchAtLastByte_sameAccessCountAsFirstByte() {
    let firstByteMismatchCounter = ByteAccessCounter()
    _ = constantTimeEquals(Data([9, 2, 3, 4, 5]), Data([1, 2, 3, 4, 5]), counter: firstByteMismatchCounter)

    let lastByteMismatchCounter = ByteAccessCounter()
    _ = constantTimeEquals(Data([1, 2, 3, 4, 9]), Data([1, 2, 3, 4, 5]), counter: lastByteMismatchCounter)

    #expect(firstByteMismatchCounter.accessCount == lastByteMismatchCounter.accessCount)
}

@Test func constantTimeEquals_differentLengths_returnsFalseWithoutThrowing() {
    let lhs = Data([1, 2, 3])
    let rhs = Data([1, 2, 3, 4])

    #expect(constantTimeEquals(lhs, rhs) == false)
}
