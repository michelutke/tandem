import Testing
import TandemProtocol

@testable import TandemApp

struct ErrorPresenterTests {
    // MARK: - errorPresenter_everyFailureReason_distinctNonEmptyText

    @Test func everyFailureReasonMapsToDistinctNonEmptyText() throws {
        let testCases: [(code: String, name: String)] = [
            ("malformedFrame", "malformedFrame"),
            ("creditViolation", "creditViolation"),
            ("versionMismatch", "versionMismatch"),
            ("protocolTimeout", "protocolTimeout"),
            ("limitExceeded", "limitExceeded")
        ]

        var titles = Set<String>()
        var texts = Set<String>()

        for testCase in testCases {
            let presenter = ErrorPresenter(reasonName: testCase.code)

            let title = presenter.title
            #expect(!title.isEmpty, "title should not be empty for \(testCase.name)")
            #expect(!titles.contains(title), "title should be distinct for each code, but \(title) is duplicate")
            titles.insert(title)

            let text = presenter.localizedTitle
            #expect(!text.isEmpty, "localizedTitle should not be empty for \(testCase.name)")
            #expect(!texts.contains(text), "localizedTitle should be distinct for each code, but \(text) is duplicate")
            texts.insert(text)
        }

        #expect(titles.count == testCases.count, "all codes should map to distinct titles")
        #expect(texts.count == testCases.count, "all codes should map to distinct localized texts")
    }

    // MARK: - errorPresenter_failedState_neverRendersConnectingOrBlank

    @Test func failedStateNeverRendersConnectingOrBlank() throws {
        let reasonNames = [
            "malformedFrame",
            "creditViolation",
            "versionMismatch",
            "protocolTimeout",
            "limitExceeded"
        ]

        for reasonName in reasonNames {
            let presenter = ErrorPresenter(reasonName: reasonName)

            let title = presenter.localizedTitle
            #expect(!title.contains("Connecting"), "title should not contain 'Connecting' for \(reasonName)")
            #expect(!title.isEmpty, "title should not be blank for \(reasonName)")

            let detail = presenter.detail
            #expect(detail != nil, "detail should not be nil for \(reasonName)")
        }
    }

    // MARK: - failureLog_versionMismatch_containsCategoryButNoCertOrSecretBytes

    @Test func versionMismatchPresenterMapsCorrectly() throws {
        let presenter = ErrorPresenter(reasonName: "versionMismatch")

        #expect(presenter.title == "error.versionMismatch")
        #expect(presenter.localizedTitle == "Version mismatch.")
        #expect(!presenter.localizedTitle.contains("cert"), "should not contain cert info")
        #expect(!presenter.localizedTitle.contains("secret"), "should not contain secret info")
        #expect(!presenter.localizedTitle.contains("key"), "should not contain key info")
    }
}
