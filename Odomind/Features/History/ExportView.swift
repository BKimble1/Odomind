import SwiftUI
import OdomindCore

/// Takes your records with you.
///
/// Three formats for three jobs: CSV for a spreadsheet, PDF for someone else,
/// and a backup for getting everything onto a new phone.
struct ExportView: View {
    @Environment(AppModel.self) private var model

    @State private var includeDemo = false
    @State private var includeVIN = false
    @State private var includeAttachments = true
    @State private var allVehicles = false
    @State private var exportedFile: ExportedFile?

    var body: some View {
        List {
            Section {
                Button {
                    exportedFile = model.exportHistoryCSV(
                        vehicleIDs: allVehicles ? nil : model.selectedVehicleID.map { [$0] },
                        includeDemoContent: includeDemo
                    )
                } label: {
                    Label("Service history (CSV)", systemImage: "tablecells")
                }

                if let vehicle = model.selectedVehicle {
                    Button {
                        exportedFile = model.exportHistoryPDF(
                            vehicleID: vehicle.id,
                            includeVIN: includeVIN,
                            includeDemoContent: includeDemo
                        )
                    } label: {
                        Label("Service history (PDF)", systemImage: "doc.richtext")
                    }
                }
            } header: {
                Text("Share")
            } footer: {
                Text("A CSV has one row per visit, so a receipt covering four jobs appears once with its real total.")
            }

            Section {
                if model.snapshot.vehicles.count > 1 {
                    Toggle("Include every vehicle", isOn: $allVehicles)
                }
                Toggle("Include the VIN in the PDF", isOn: $includeVIN)
                if model.hasDemoContent {
                    Toggle("Include sample data", isOn: $includeDemo)
                }
            } header: {
                Text("Options")
            } footer: {
                Text("The VIN is left out unless you ask for it. It identifies your vehicle, and a service history often changes hands.")
            }

            Section {
                Toggle("Include receipts and photos", isOn: $includeAttachments)
                Button {
                    exportedFile = model.exportBackup(
                        includeAttachments: includeAttachments,
                        includeDemoContent: includeDemo
                    )
                } label: {
                    Label("Create a backup", systemImage: "arrow.down.doc")
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("A backup is a single file containing everything: vehicles, mileage, tasks, history, settings and, if you include them, your receipts. Restore it from Garage → Settings → Backup.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportedFile) { file in
            ShareSheet(items: [file.url]) {
                exportedFile = nil
            }
        }
    }
}
