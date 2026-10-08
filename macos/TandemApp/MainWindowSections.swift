import FeatureCalls
import FeatureFiles
import FeatureMessaging
import SwiftUI
import TandemCrypto
import TandemDesign
import TandemDevices
import TandemProtocol
import TandemStore

/// Everything the main window's sections read from the running listener's session features. `nil`
/// in scenario hosts, which keep the placeholder content.
struct MainWindowServices {
    let live: LiveSessionState
    let messaging: MessagingStores?
    let photos: any PhotoService
    let transferProgress: TransferProgressCenter
    let sendEntryHandler: SendEntryHandler
    let activeCall: ActiveCallAlert
    let pairedPeer: PairedPeerState
    let pairedDevices: PairedDevicesViewModel?
    let rotation: MacRotationSettingsViewModel?
    let errorBanner: ErrorBannerViewModel
}

/// The Messages section over the cached stores: threads stay visible offline, the composer does not.
struct MessagesSectionHost: View {
    let services: MainWindowServices
    let viewModel: MainWindowViewModel

    var body: some View {
        if let messaging = services.messaging,
           let peer = services.live.peer ?? services.pairedPeer.record?.fingerprint {
            MessagesSectionContent(
                live: services.live,
                messaging: messaging,
                peer: peer,
                isOffline: viewModel.isOffline,
                deviceName: viewModel.deviceName
            )
            .id(services.live.generation)
        } else {
            SectionPlaceholder(text: "Messages unavailable.", identifier: "messagesUnavailable")
        }
    }
}

private struct MessagesSectionContent: View {
    let live: LiveSessionState
    let messaging: MessagingStores
    let peer: SpkiFingerprint
    let isOffline: Bool
    let deviceName: String

    @State private var threadList: ThreadListViewModel
    @State private var refreshTick = 0

    init(
        live: LiveSessionState,
        messaging: MessagingStores,
        peer: SpkiFingerprint,
        isOffline: Bool,
        deviceName: String
    ) {
        self.live = live
        self.messaging = messaging
        self.peer = peer
        self.isOffline = isOffline
        self.deviceName = deviceName
        _threadList = State(initialValue: ThreadListViewModel(
            peer: peer,
            smsStore: messaging.smsStore,
            contactsStore: messaging.contactsStore,
            syncStatus: LiveMessagingSync(live: live)
        ))
    }

    var body: some View {
        MessagesSplitView(
            viewModel: threadList,
            makeConversation: { row in
                ConversationViewModel(
                    peer: peer,
                    threadId: row.id,
                    title: row.title,
                    smsStore: messaging.smsStore,
                    session: live.session,
                    syncSource: LiveMessagingSync(live: live),
                    now: { Date() }
                )
            },
            headerAccessory: live.session.map {
                ConversationCallHost.headerAccessory(session: $0, syncSource: LiveMessagingSync(live: live))
            },
            offlineComposerText: isOffline ? "Sends when \(deviceName) is back" : nil,
            refreshTick: refreshTick
        )
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                refreshTick &+= 1
            }
        }
    }
}

/// The Calls section over the attached session; built only while connected.
struct CallsSectionHost: View {
    let services: MainWindowServices

    var body: some View {
        if let session = services.live.session,
           let messaging = services.messaging,
           let peer = services.live.peer {
            CallsSectionContent(
                session: session,
                contacts: messaging.contactsStore,
                peer: peer,
                sync: LiveMessagingSync(live: services.live),
                callAlert: services.activeCall.viewModel
            )
            .id(services.live.generation)
        } else {
            SectionPlaceholder(text: "Reconnecting…", identifier: "callsReconnecting")
        }
    }
}

private struct CallsSectionContent: View {
    let callAlert: CallAlertViewModel?

    @State private var section: CallsSectionViewModel
    @State private var placeCall: PlaceCallViewModel

    init(
        session: any TandemSession,
        contacts: any ContactsStore,
        peer: SpkiFingerprint,
        sync: LiveMessagingSync,
        callAlert: CallAlertViewModel?
    ) {
        self.callAlert = callAlert
        _section = State(initialValue: CallsSectionViewModel(peer: peer, contacts: contacts))
        _placeCall = State(initialValue: PlaceCallViewModel(session: session, simSource: SyncPlaceCallSims(sync: sync)))
    }

    var body: some View {
        CallsSectionView(viewModel: section, placeCall: placeCall, callAlert: callAlert)
    }
}

private struct SyncPlaceCallSims: PlaceCallSimSource {
    let sync: LiveMessagingSync

    func sims() async -> [PlaceCallSim] {
        await sync.simOptions().map { PlaceCallSim(id: $0.id, name: $0.name) }
    }
}

struct TransfersSectionHost: View {
    let services: MainWindowServices

    var body: some View {
        TransfersSectionView(
            center: services.transferProgress,
            onSendFile: {
                let handler = services.sendEntryHandler
                Task { _ = await handler.sendFileQuickAction() }
            }
        )
    }
}

struct DevicesSectionHost: View {
    let services: MainWindowServices
    let viewModel: MainWindowViewModel
    let onPairPhone: () -> Void

    var body: some View {
        if let devices = services.pairedDevices {
            DevicesSectionView(
                devices: devices,
                rotation: services.rotation,
                statusText: { _ in
                    viewModel.isOffline ? viewModel.connectionStateText : "Connected · last seen now"
                },
                onPairPhone: onPairPhone
            )
        } else {
            SectionPlaceholder(text: "Devices unavailable.", identifier: "devicesUnavailable")
        }
    }
}

/// Shown instead of every section but Devices while no phone is paired (ui-spec §8: not paired).
struct NotPairedSectionState: View {
    let onPairPhone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TandemSpacing.large) {
            TitleBlock(subject: "Tandem.", state: "No phone yet.", size: 26)
            Text("Scan a code with the Tandem app on your Android phone. Stays on your local network.")
                .tandemTextStyle(TandemTypography.body())
                .foregroundStyle(TandemColor.ink2)
            PillButton("Pair phone", action: onPairPhone)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("pairPhoneButton")
        }
        .padding(TandemSpacing.windowPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("notPairedEmptyState")
    }
}

private struct SectionPlaceholder: View {
    let text: String
    let identifier: String

    var body: some View {
        Text(text)
            .tandemTextStyle(TandemTypography.body())
            .foregroundStyle(TandemColor.ink2)
            .accessibilityIdentifier(identifier)
            .padding(TandemSpacing.windowPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
