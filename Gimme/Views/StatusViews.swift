import SwiftUI
import UIKit

/// Shared scaffold for the non-compass states.
struct StatusMessageView: View {
    let systemImage: String
    let title: String
    var subtitle: String?
    var showsProgress = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if showsProgress {
                ProgressView()
                    .padding(.top, 4)
            }
        }
        .padding(32)
    }
}

/// Dev-facing state: the Places key is missing from the build (spec §3.2).
struct SetupRequiredView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Setup required", systemImage: "key.slash")
                .font(.title2.weight(.semibold))
            Text("Gimme needs a Google Places API key to search.")
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig`")
                Text("2. Set `GOOGLE_PLACES_API_KEY` to a key with Places API (New) enabled")
                Text("3. Rebuild")
            }
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            Text("See the README for key-restriction instructions.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(28)
    }
}

struct PermissionView: View {
    let requestAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            StatusMessageView(
                systemImage: "location.circle",
                title: "Gimme needs your location",
                subtitle: "That's the whole trick: we point an arrow from where you are to the nearest thing you want. Location stays on your device and is only used to search nearby."
            )
            Button("Allow location", action: requestAction)
                .buttonStyle(.borderedProminent)
                .font(.body.weight(.semibold))
        }
        .padding(.bottom, 40)
    }
}

struct PermissionDeniedView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 18) {
            StatusMessageView(
                systemImage: "location.slash",
                title: "Location is off",
                subtitle: "Gimme can't point anywhere without it. You can turn it on in Settings."
            )
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .font(.body.weight(.semibold))
        }
        .padding(.bottom, 40)
    }
}

struct IdleView: View {
    var body: some View {
        StatusMessageView(
            systemImage: "hand.point.up.left",
            title: "What do you want?",
            subtitle: "Type it above, or tap a suggestion. Zyns, gas, ice cream — anything."
        )
    }
}

struct NoResultsView: View {
    let query: String

    var body: some View {
        StatusMessageView(
            systemImage: "binoculars",
            title: "Couldn't find “\(query)” nearby",
            subtitle: "Try a different word for it — or the kind of store that sells it."
        )
    }
}

struct ErrorStateView: View {
    let message: String
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            StatusMessageView(
                systemImage: "exclamationmark.triangle",
                title: "Hmm.",
                subtitle: message
            )
            Button("Retry", action: retryAction)
                .buttonStyle(.borderedProminent)
                .font(.body.weight(.semibold))
        }
        .padding(.bottom, 40)
    }
}
