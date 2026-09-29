import FeatureNotifications
import Foundation
import Testing
@preconcurrency import UserNotifications

@Suite struct CategoryRegistryTests {
    @Test func categoryRegistry_postedWithTwoActions_categoryActionsMatchTitlesInOrder() async throws {
        let presenter = RecordingNotificationPresenter()
        let registry = CategoryRegistry(presenter: presenter)
        let actions = [
            NotificationActionSpec(title: "Archive", isRemoteInput: false),
            NotificationActionSpec(title: "Mark as read", isRemoteInput: false)
        ]

        let identifier = await registry.categoryIdentifier(for: actions)

        let categories = await presenter.categories
        let category = try #require(categories.first { $0.identifier == identifier })
        #expect(category.actions.map(\.title) == ["Archive", "Mark as read"])
    }

    @Test func categoryRegistry_remoteInputAction_registersTextInputAction() async throws {
        let presenter = RecordingNotificationPresenter()
        let registry = CategoryRegistry(presenter: presenter)
        let actions = [NotificationActionSpec(title: "Reply", isRemoteInput: true)]

        let identifier = await registry.categoryIdentifier(for: actions)

        let categories = await presenter.categories
        let category = try #require(categories.first { $0.identifier == identifier })
        #expect(category.actions.count == 1)
        #expect(category.actions.first is UNTextInputNotificationAction)
    }

    @Test func categoryRegistry_postedWithoutActions_assignsDismissOnlyCategory() async throws {
        let presenter = RecordingNotificationPresenter()
        let registry = CategoryRegistry(presenter: presenter)

        let identifier = await registry.categoryIdentifier(for: [])

        #expect(identifier == CategoryRegistry.dismissOnlyCategoryIdentifier)
        let categories = await presenter.categories
        let category = try #require(categories.first { $0.identifier == identifier })
        #expect(category.actions.isEmpty)
    }

    @Test func categoryRegistry_anyCategory_includesCustomDismissActionOption() async throws {
        let presenter = RecordingNotificationPresenter()
        let registry = CategoryRegistry(presenter: presenter)

        _ = await registry.categoryIdentifier(for: [])
        _ = await registry.categoryIdentifier(for: [NotificationActionSpec(title: "Reply", isRemoteInput: true)])

        let categories = await presenter.categories
        #expect(!categories.isEmpty)
        for category in categories {
            #expect(category.options.contains(.customDismissAction))
        }
    }

    @Test func categoryRegistry_identicalActionSets_shareCategoryIdentifier() async throws {
        let presenter = RecordingNotificationPresenter()
        let registry = CategoryRegistry(presenter: presenter)
        let actions = [
            NotificationActionSpec(title: "Reply", isRemoteInput: true),
            NotificationActionSpec(title: "Dismiss", isRemoteInput: false)
        ]

        let first = await registry.categoryIdentifier(for: actions)
        let second = await registry.categoryIdentifier(for: actions)

        #expect(first == second)
        let categories = await presenter.categories
        #expect(categories.count == 1)
    }
}
