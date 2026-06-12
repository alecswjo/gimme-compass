import MapKit
import SwiftUI
import UIKit

/// The product: an arrow, a distance, and the place it points at.
/// Covers both the `.pointing` and `.arrived` phases.
struct CompassView: View {
    let model: CompassViewModel

    private var isArrived: Bool { model.phase == .arrived }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            VStack(spacing: 20) {
                if isArrived {
                    arrivedBadge
                } else {
                    arrow
                }
                distanceBlock
                hints
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isArrived ? "You have arrived. \(model.accessibilitySummary)" : model.accessibilitySummary)

            Spacer(minLength: 0)

            if let target = model.target {
                PlaceCard(place: target, resolvedLabel: model.resolvedLabel, refreshAction: model.retry)
            }
        }
        .padding()
    }

    private var arrow: some View {
        ArrowShape()
            .fill(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .aspectRatio(0.78, contentMode: .fit)
            .frame(maxHeight: 230)
            .shadow(color: Color.accentColor.opacity(0.35), radius: 18, y: 8)
            .rotationEffect(.degrees(model.arrowRotation))
            .animation(.easeOut(duration: 0.25), value: model.arrowRotation)
            .opacity(model.isReducedAccuracy ? 0.55 : 1)
            .padding(.vertical, 8)
    }

    private var arrivedBadge: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 88))
                .foregroundStyle(Color.accentColor)
            Text("You're basically there")
                .font(.title2.weight(.semibold))
        }
        .padding(.vertical, 24)
    }

    private var distanceBlock: some View {
        VStack(spacing: 4) {
            if let distance = model.distanceText {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(distance)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if let cardinal = model.cardinalText {
                        Text(cardinal)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var hints: some View {
        VStack(spacing: 6) {
            if !model.isHeadingAvailable {
                hintLabel("N-up — compass unavailable on this device", systemImage: "safari")
            }
            if model.showCalibrationHint {
                hintLabel("Wave your phone in a figure-8 to calibrate", systemImage: "gyroscope")
            }
            if model.isReducedAccuracy {
                hintLabel("Approximate — turn on Precise Location for a better arrow", systemImage: "location.slash")
            }
        }
    }

    private func hintLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

/// Kite-style arrow pointing up (rotation 0 == straight ahead).
struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.86))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.64))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.86))
        path.closeSubpath()
        return path
    }
}

/// Name, address, open state, transparent category caption, Maps escape hatch.
struct PlaceCard: View {
    let place: Place
    let resolvedLabel: String?
    let refreshAction: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if let resolvedLabel {
                Text("→ \(resolvedLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Searched for \(resolvedLabel)")
            }
            HStack(spacing: 6) {
                Text(place.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button(action: refreshAction) {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Search again")
            }
            if let address = place.address {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let isOpen = place.isOpenNow {
                Text(isOpen ? "Open now" : "Closed")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isOpen ? Color.green : Color.red)
            }
            Text("Distance is as the crow flies")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)

            Button {
                openInMaps()
            } label: {
                Label("Open in Maps", systemImage: "map")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 6)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        item.name = place.name
        item.openInMaps()
    }
}
