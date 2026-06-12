import SwiftUI
import UIKit

/// One screen, mutually exclusive content states (spec §3.1/§3.2).
struct RootView: View {
    @Bindable var model: CompassViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            if showsQueryBar {
                QueryBar(model: model)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(uiColor: .systemBackground))
        .task { model.start() }
        .onChange(of: scenePhase) { _, newPhase in
            model.scenePhaseChanged(isActive: newPhase == .active)
        }
    }

    private var showsQueryBar: Bool {
        switch model.phase {
        case .setupRequired, .needsPermission, .permissionDenied:
            false
        default:
            true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .setupRequired:
            SetupRequiredView()
        case .needsPermission:
            PermissionView(requestAction: model.requestPermission)
        case .permissionDenied:
            PermissionDeniedView()
        case .locating:
            StatusMessageView(systemImage: "location.viewfinder", title: "Finding you…", showsProgress: true)
        case .idle:
            IdleView()
        case .searching:
            StatusMessageView(systemImage: "sparkle.magnifyingglass", title: "Looking for \(model.query)…", showsProgress: true)
        case .pointing, .arrived:
            CompassView(model: model)
        case .noResults:
            NoResultsView(query: model.query)
        case .error(let error):
            ErrorStateView(message: error.userMessage, retryAction: model.retry)
        }
    }
}

#Preview {
    RootView(model: .live())
}
