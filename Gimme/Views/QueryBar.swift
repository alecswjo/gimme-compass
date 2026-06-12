import SwiftUI
import UIKit

/// Text field + suggestion/recents chips. Search runs on explicit submit only
/// (spec §3.5 — calmer UX and Places bills per request).
struct QueryBar: View {
    @Bindable var model: CompassViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("I want…", text: $model.query)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        isFocused = false
                        model.submit()
                    }
                    .accessibilityLabel("What do you want?")
                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                        isFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.chips, id: \.self) { chip in
                        Button {
                            isFocused = false
                            model.submitQuery(chip)
                        } label: {
                            Text(chip)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                                .foregroundStyle(Color.accentColor)
                        }
                        .accessibilityLabel("Search for \(chip)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
