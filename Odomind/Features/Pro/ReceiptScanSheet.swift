import SwiftUI
import PhotosUI
import OdomindCore

/// Reads a receipt and hands back what it thinks it found, for the owner to
/// check.
///
/// The review step is the feature. Odomind does not save anything it read
/// until a person has looked at it, and it never claims the line items are
/// confirmed parts for this vehicle — text on a receipt is text.
struct ReceiptScanSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Called with the fields the owner accepted, plus the stored image.
    let apply: (ReceiptReading, UUID?) -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var reading: ReceiptReading?
    @State private var attachmentID: UUID?
    @State private var isWorking = false
    @State private var failure: String?

    @State private var merchant = ""
    @State private var date = Date()
    @State private var totalText = ""
    @State private var useDate = false
    @State private var useTotal = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(reading == nil ? "Choose a receipt photo" : "Choose a different photo", systemImage: "doc.text.viewfinder")
                    }
                    .accessibilityIdentifier("receipt.choose")
                    if isWorking {
                        HStack { ProgressView(); Text("Reading…").foregroundStyle(Theme.Palette.secondaryText) }
                    }
                    if let failure {
                        Text(failure)
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.overdue)
                    }
                } footer: {
                    Text("Reading happens on this device. The photo, the text and the total are never uploaded.")
                }

                if let reading, !reading.isEmpty {
                    Section {
                        TextField("Shop", text: $merchant)
                            .accessibilityIdentifier("receipt.merchant")
                        Toggle("Use this date", isOn: $useDate)
                        if useDate {
                            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                        }
                        Toggle("Use this total", isOn: $useTotal)
                        if useTotal {
                            TextField("Total", text: $totalText)
                                .keyboardType(.decimalPad)
                                .accessibilityIdentifier("receipt.total")
                        }
                    } header: {
                        Text("Check what Odomind read")
                    } footer: {
                        Text("These are guesses from the text on the receipt. Correct anything that is wrong — nothing is saved until you tap Use.")
                    }

                    Section {
                        DisclosureGroup("All the text Odomind read") {
                            ForEach(Array(reading.lines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption)
                                    .foregroundStyle(Theme.Palette.secondaryText)
                            }
                        }
                    } footer: {
                        Text("Odomind does not work out which parts were bought. A product name is not proof of fit.")
                    }
                } else if reading != nil {
                    Section {
                        QuietNote(text: "Odomind could not find a shop, date or total on that receipt. You can still attach it and fill the details in yourself.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LuminousField(strength: 0.5))
            .navigationTitle("Scan a receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") { finish() }
                        .disabled(reading == nil)
                        .accessibilityIdentifier("receipt.use")
                }
            }
            .task(id: photoItem) { await scan() }
        }
    }

    private func scan() async {
        guard let photoItem else { return }
        isWorking = true
        failure = nil
        defer { isWorking = false }

        guard let data = try? await photoItem.loadTransferable(type: Data.self) else {
            failure = "Odomind could not open that photo."
            return
        }
        let prepared = ImageProcessing.prepare(data: data, contentType: "image/jpeg")
        attachmentID = model.addAttachment(data: prepared.data, contentType: prepared.contentType, caption: "Receipt")

        do {
            let result = try await ReceiptScanner.read(
                imageData: prepared.data,
                calendar: model.calendar,
                now: model.clock.now
            )
            reading = result
            merchant = result.merchant ?? ""
            if let found = result.date { date = found; useDate = true }
            if let total = result.total {
                totalText = NSDecimalNumber(decimal: total).stringValue
                useTotal = true
            }
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? "Odomind could not read that receipt."
            reading = ReceiptReading(lines: [])
        }
    }

    private func finish() {
        var accepted = ReceiptReading(lines: reading?.lines ?? [])
        accepted.merchant = merchant.isEmpty ? nil : merchant
        accepted.date = useDate ? date : nil
        accepted.total = useTotal ? Decimal(string: totalText.replacingOccurrences(of: ",", with: ".")) : nil
        accepted.currencyCode = reading?.currencyCode
        apply(accepted, attachmentID)
        dismiss()
    }
}
