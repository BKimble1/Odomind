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
    @Environment(AppModel.self) private var model
    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            HStack(spacing: Theme.Spacing.tight) {
                Image(systemName: symbolName)
                    .font(.caption)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.Palette.accent)
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.small)
            .background(Theme.Palette.raised, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Shopping area: \(label)"))
        .accessibilityHint(Text("Choose a different area"))
        .accessibilityIdentifier("shopping.location")
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
                    Text("Used only to list shops near you, and only when you ask.")
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
                    Text("An area you pick stays selected until you change it.")
                }
            }
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
