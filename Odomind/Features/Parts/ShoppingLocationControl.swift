import UIKit
import SwiftUI

/// The compact "where am I shopping" control, shown at the upper right of
/// Home and Parts.
///
/// Small on purpose. It is a standing choice rather than a step: most of the
/// time it says a town name and nobody touches it, and the one time somebody
/// is buying a part in a different city they change it once and it stays
/// changed.
struct ShoppingLocationControl: View {
    /// How much room the control is asking for.
    enum Style {
        /// The standing chip in a toolbar: a town name most of the time.
        case chip
        /// The one place there is nothing to show yet, where the control has
        /// to read as the thing to do rather than as a label.
        case prominent
    }

    @Environment(AppModel.self) private var model
    var style: Style = .chip
    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            HStack(spacing: Theme.Spacing.tight + 2) {
                Image(systemName: symbolName)
                    .font(.caption)
                    .accessibilityHidden(true)
                Text(style == .prominent ? "Choose your area" : label)
                    .font(.subheadline.weight(style == .prominent ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(style == .prominent ? Theme.Palette.onAccent : Theme.Palette.accent)
            .padding(.horizontal, style == .prominent ? Theme.Spacing.large : Theme.Spacing.medium)
            .padding(.vertical, style == .prominent ? Theme.Spacing.medium - 1 : Theme.Spacing.small)
            .background(
                style == .prominent ? Theme.Palette.accent : Theme.Palette.raised,
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Shopping area: \(label)"))
        .accessibilityHint(Text("Choose a different area"))
        .accessibilityIdentifier(style == .prominent ? "shopping.chooseArea" : "shopping.location")
        .sheet(isPresented: $showingPicker) {
            ShoppingLocationPicker()
        }
    }

    private var symbolName: String {
        switch model.shoppingLocation.resolution {
        case .ready where model.shoppingLocation.area.isCurrentLocation: return "location.fill"
        case .ready: return "mappin"
        case .resolving: return "location"
        case .denied: return "location.slash"
        default: return "mappin.and.ellipse"
        }
    }

    private var label: String {
        switch model.shoppingLocation.resolution {
        case .ready(_, _, let name): return name
        case .resolving: return "Finding…"
        case .denied: return "Set area"
        case .failed: return "Set area"
        case .none: return "Set area"
        }
    }
}

/// Current location, or somewhere the owner types.
struct ShoppingLocationPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var query = ""
    @State private var suggestions: [PlaceSuggestion] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task {
                            if model.shoppingLocation.authorizationStatus == .notDetermined {
                                _ = await model.shoppingLocation.requestPermission()
                            } else {
                                model.shoppingLocation.useCurrentLocation()
                            }
                            dismiss()
                        }
                    } label: {
                        Label("Use current location", systemImage: "location.fill")
                    }
                    .accessibilityIdentifier("shopping.useCurrent")
                    .disabled(model.shoppingLocation.resolution == .denied)

                    if model.shoppingLocation.resolution == .denied {
                        // A denial is not a failure to retry. The only way
                        // back is Settings, and saying so beats a button that
                        // does nothing.
                        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                            Text("Location is off for Odomind.")
                                .font(.footnote)
                                .foregroundStyle(Theme.Palette.secondaryText)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    openURL(url)
                                }
                            }
                            .font(.footnote)
                            .buttonStyle(.tappableText)
                        }
                    }
                } footer: {
                    Text("Only to list shops near you.")
                }

                Section {
                    TextField("Town or postal code", text: $query)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("shopping.areaSearch")
                        .onChange(of: query) { _, text in search(text) }

                    if isSearching {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Looking…").foregroundStyle(Theme.Palette.secondaryText)
                        }
                    }

                    ForEach(suggestions) { place in
                        Button {
                            model.shoppingLocation.choose(place)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .foregroundStyle(Theme.Palette.primaryText)
                                // There is more than one Springfield, so the
                                // region is shown rather than left to guess.
                                if let detail = place.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(Theme.Palette.secondaryText)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("shopping.areaResult")
                    }
                } header: {
                    Text("Somewhere else")
                } footer: {
                    Text("Stays set until you change it.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(LuminousField(strength: 0.5))
            .navigationTitle("Shopping area")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    private func search(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            if Task.isCancelled { return }
            let found = await model.shoppingLocation.places(matching: trimmed)
            if Task.isCancelled { return }
            suggestions = found
            isSearching = false
        }
    }
}
