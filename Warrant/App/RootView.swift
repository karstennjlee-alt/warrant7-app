import SwiftUI
import WarrantKit

struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if state.isSignedIn {
                signedIn
            } else {
                SignInView()
            }
        }
        .background(Ink.canvas)
    }

    @ViewBuilder
    private var signedIn: some View {
        @Bindable var state = state

        if sizeClass == .regular {
            // On iPad the queue is a sidebar, not a phone layout stretched across a slab.
            NavigationSplitView {
                InboxView(isSidebar: true)
            } detail: {
                NavigationStack {
                    if let id = state.presentedApprovalID ?? state.approvals.first?.id,
                       let approval = state.approval(id: id) {
                        ApprovalCardView(approval: approval)
                    } else {
                        MissingApprovalView()
                    }
                }
            }
        } else {
            TabView(selection: $state.selectedTab) {
                NavigationStack(path: $state.route) {
                    InboxView()
                }
                .tabItem { Label("Queue", systemImage: "tray") }
                .badge(state.approvals.count)
                .tag(AppState.Tab.inbox)

                NavigationStack { LedgerView() }
                    .tabItem { Label("Receipts", systemImage: "list.bullet.rectangle") }
                    .tag(AppState.Tab.receipts)

                NavigationStack { VerifyView() }
                    .tabItem { Label("Verify", systemImage: "checkmark.shield") }
                    .tag(AppState.Tab.verify)

                NavigationStack { PolicyView() }
                    .tabItem { Label("Limits", systemImage: "slider.horizontal.3") }
                    .tag(AppState.Tab.policy)

                NavigationStack { TamperLabView() }
                    .tabItem { Label("Lab", systemImage: "flask") }
                    .tag(AppState.Tab.lab)
            }
            .tint(Ink.blue)
        }
    }
}

/// Activity and Settings live behind the queue's header rather than eating two tab slots —
/// the tab bar is for the things a person reaches for while deciding.
struct OverflowLinks: View {
    var body: some View {
        Menu {
            NavigationLink("Activity") { ActivityView() }
            NavigationLink("Settings") { SettingsView() }
        } label: {
            Text("···")
                .warrantType(.title)
                .foregroundStyle(Ink.blue)
                .frame(width: 44, height: 30, alignment: .trailing)
        }
        .accessibilityLabel("More")
    }
}
