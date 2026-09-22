import SwiftUI
import UIKit
import VisionKit
import OdomindCore

/// Enter or scan a VIN, then look it up.
///
/// Three things happen in a deliberate order: the owner sees exactly what will
/// be sent and where, they get to correct scanned text before it goes anywhere,
/// and the lookup is optional — every failure path leads back to typing the
/// vehicle in by hand.
struct VINEntryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let onDecoded: (VehicleDecodeResult) -> Void

    @State private var vinText = ""
    @State private var modelYearText = ""
    @State private var hasAcknowledgedDisclosure = false
    @State private var isLooking = false
    @State private var lookupError: String?
    @State private var showingScanner = false
    @State private var scannedText: String?

    private var normalized: String { VIN.normalize(vinText) }
    private var problems: [VIN.Problem] { normalized.isEmpty ? [] : VIN.problems(in: normalized) }
    private var blocking: [VIN.Problem] { problems.filter(\.isBlocking) }
    private var cautions: [VIN.Problem] { problems.filter { !$0.isBlocking } }
    private var canLookUp: Bool { normalized.count == VIN.length && blocking.isEmpty && !isLooking }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("17 characters", text: $vinText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .accessibilityLabel(Text("Vehicle identification number"))
                    if DataScannerViewController.isSupported {
                        Button {
                            showingScanner = true
                        } label: {
                            Label("Scan with the camera", systemImage: "camera.viewfinder")
                        }
                    }
                } header: {
                    Text("VIN")
                } footer: {
                    Text("Usually on a plate at the base of the windshield, on the driver's door jamb, or on your registration and insurance documents.")
                }

                if !normalized.isEmpty {
                    Section {
                        ValueRow(label: "Characters entered", value: "\(normalized.count) of \(VIN.length)")
                        if let year = VIN.modelYear(from: normalized, notAfter: currentYear + 1) {
                            ValueRow(label: "Model year in the VIN", value: String(year))
                        }
                    }
                }

                if !blocking.isEmpty || !cautions.isEmpty {
                    Section("Check this") {
                        ForEach(Array((blocking + cautions).enumerated()), id: \.offset) { _, problem in
                            InlineNotice(kind: .caution, message: problem.message)
                        }
                    }
                }

                Section {
                    TextField("Model year (optional)", text: $modelYearText)
                        .keyboardType(.numberPad)
                } footer: {
                    Text("Supplying the model year makes the lookup more accurate for vehicles built before 1981.")
                }

                Section {
                    Toggle(isOn: $hasAcknowledgedDisclosure) {
                        Text("Send this VIN to \(model.identificationProvider.contactedHost)")
                    }
                } header: {
                    Text("Before Odomind looks it up")
                } footer: {
                    Text("""
                    This is the only request Odomind makes. The VIN goes to \(model.identificationProvider.displayName), \
                    the U.S. government's public vehicle catalog, and comes back with the year, make, model and engine. \
                    Nothing else is sent: no name, no account, no other vehicle details. You can skip this entirely and \
                    type the vehicle in by hand.
                    """)
                }

                if let lookupError {
                    Section {
                        InlineNotice(kind: .caution, message: lookupError)
                        Button("Enter the vehicle by hand instead") { dismiss() }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LuminousField(strength: 0.5))
            .navigationTitle("Look up a VIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLooking {
                        ProgressView()
                    } else {
                        Button("Look up") { Task { await lookUp() } }
                            .disabled(!canLookUp || !hasAcknowledgedDisclosure)
                    }
                }
            }
            .sheet(isPresented: $showingScanner) {
                VINScannerView { text in
                    showingScanner = false
                    // Recognised text is offered for correction, never submitted
                    // straight to a provider: a misread character would look up
                    // somebody else's vehicle.
                    vinText = VIN.normalize(text)
                }
            }
        }
    }

    private var currentYear: Int {
        model.calendar.component(.year, from: model.clock.now)
    }

    private func lookUp() async {
        isLooking = true
        lookupError = nil
        defer { isLooking = false }

        let year = Int(modelYearText.filter(\.isNumber))
        do {
            let result = try await model.identificationProvider.decode(vin: normalized, modelYear: year)
            onDecoded(result)
            dismiss()
        } catch let error as ProviderError {
            lookupError = error.errorDescription
        } catch {
            lookupError = "The lookup did not complete. You can add this vehicle by hand."
        }
    }
}

/// On-device text recognition for a VIN plate.
///
/// Camera access is requested here, at the moment it is needed, and never at
/// launch. If the device or the permission will not support it, the owner types
/// the VIN instead and nothing is lost.
struct VINScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onRecognized: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
                    DataScannerRepresentable(onRecognized: onRecognized)
                        .ignoresSafeArea(edges: .bottom)
                        .overlay(alignment: .bottom) {
                            Text("Point the camera at the VIN plate. You can correct what it reads before anything is sent.")
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .padding()
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                                .padding()
                        }
                } else if DataScannerViewController.isSupported {
                    // The device can scan; something else is in the way, and
                    // camera access being off is much the most likely. Offer
                    // the way back as well as the way around.
                    ContentUnavailableView {
                        Label("Scanning is unavailable", systemImage: "camera.badge.ellipsis")
                    } description: {
                        Text("Camera access may be off. Typing works just as well — 17 characters off the door jamb.")
                    } actions: {
                        Button("Type it instead") { dismiss() }
                            .buttonStyle(.borderedProminent)
                        if let settings = URL(string: UIApplication.openSettingsURLString) {
                            Link("Open Odomind's settings", destination: settings)
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("This device cannot scan text", systemImage: "camera.badge.ellipsis")
                    } description: {
                        Text("Typing the VIN works just as well — it is 17 characters off the dashboard or door jamb.")
                    } actions: {
                        Button("Type it instead") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Scan a VIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onRecognized: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        guard !uiViewController.isScanning else { return }
        try? uiViewController.startScanning()
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onRecognized: onRecognized)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onRecognized: (String) -> Void

        init(onRecognized: @escaping (String) -> Void) {
            self.onRecognized = onRecognized
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didTapOn item: RecognizedItem
        ) {
            guard case .text(let text) = item else { return }
            onRecognized(text.transcript)
        }

        /// Picks up a candidate automatically only when it already looks like a
        /// VIN, which avoids grabbing the first piece of text in frame.
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                guard case .text(let text) = item else { continue }
                let candidate = VIN.normalize(text.transcript)
                if candidate.count == VIN.length, VIN.isStructurallyValid(candidate) {
                    onRecognized(candidate)
                    return
                }
            }
        }
    }
}
