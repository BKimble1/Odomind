import SwiftUI
import UniformTypeIdentifiers
import OdomindCore

/// Backup and restore.
///
/// Restoring shows exactly what it would do before it does any of it, and
/// applies as a single unit — a half-restored garage is not a state Odomind can
/// end up in.
struct BackupView: View {
    @Environment(AppModel.self) private var model

    @State private var includeAttachments = true
    @State private var exportedFile: ExportedFile?
    @State private var showingImporter = false
    @State private var strategy: BackupMergeStrategy = .addMissingOnly
    @State private var preview: ImportPreview?
    @State private var isApplying = false

    struct ImportPreview: Identifiable {
        let id = UUID()
        let archive: BackupArchive
        let plan: BackupImportPlan
    }

    var body: some View {
        List {
            Section {
                Toggle("Include receipts and photos", isOn: $includeAttachments)
                Button {
                    exportedFile = model.exportBackup(
                        includeAttachments: includeAttachments,
                        includeDemoContent: false
                    )
                } label: {
                    Label("Create a backup", systemImage: "arrow.down.doc")
                }
            } header: {
                Text("Back up")
            } footer: {
                Text("One file with everything, receipts included if you want them. Keep it somewhere this phone is not.")
            }

            Section {
                Picker("When restoring", selection: $strategy) {
                    ForEach(BackupMergeStrategy.allCases, id: \.self) { value in
                        Text(value.displayName).tag(value)
                    }
                }
                .pickerStyle(.inline)
                Text(strategy.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showingImporter = true
                } label: {
                    Label("Choose a backup file", systemImage: "arrow.up.doc")
                }
            } header: {
                Text("Restore")
            } footer: {
                Text("Odomind shows you what a restore would do before anything changes.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LuminousField(strength: 0.5))
        .navigationTitle("Backup and restore")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportedFile) { file in
            ShareSheet(items: [file.url]) { exportedFile = nil }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if let outcome = model.previewImport(from: url, strategy: strategy) {
                    preview = ImportPreview(archive: outcome.archive, plan: outcome.plan)
                }
            case .failure(let error):
                model.alert = AppAlert(
                    title: "Could not open that file",
                    message: error.localizedDescription
                )
            }
        }
        .sheet(item: $preview) { item in
            ImportPreviewSheet(preview: item, isApplying: $isApplying) {
                Task {
                    isApplying = true
                    let applied = await model.applyImport(archive: item.archive, strategy: item.plan.strategy)
                    isApplying = false
                    if applied { preview = nil }
                }
            }
        }
    }
}

/// The confirmation screen for a restore.
struct ImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let preview: BackupView.ImportPreview
    @Binding var isApplying: Bool
    let apply: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ValueRow(label: "Created", value: Format.dateAndTime(preview.plan.exportedOn))
                    ValueRow(label: "Vehicles to add", value: "\(preview.plan.vehiclesToAdd.count)")
                    if !preview.plan.vehiclesAlreadyPresent.isEmpty {
                        ValueRow(label: "Already in your garage", value: "\(preview.plan.vehiclesAlreadyPresent.count)")
                    }
                    ValueRow(label: "Mileage readings", value: "\(preview.plan.readingCount)")
                    ValueRow(label: "Tasks", value: "\(preview.plan.planItemCount)")
                    ValueRow(label: "Service records", value: "\(preview.plan.serviceRecordCount)")
                    ValueRow(label: "Specifications", value: "\(preview.plan.specificationCount)")
                    ValueRow(label: "Attachments", value: "\(preview.plan.attachmentCount)")
                } header: {
                    Text("What this backup contains")
                }

                Section {
                    Text(preview.plan.strategy.explanation)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text(preview.plan.strategy.displayName)
                }

                if !preview.plan.blockingIssues.isEmpty {
                    Section {
                        ForEach(Array(preview.plan.blockingIssues.enumerated()), id: \.offset) { _, issue in
                            InlineNotice(kind: .caution, message: issue.message)
                        }
                    } header: {
                        Text("Cannot restore")
                    }
                }

                if !preview.plan.warnings.isEmpty {
                    Section {
                        ForEach(Array(preview.plan.warnings.enumerated()), id: \.offset) { _, issue in
                            InlineNotice(message: issue.message)
                        }
                    } header: {
                        Text("Worth knowing")
                    }
                }

                if preview.plan.strategy == .replaceEverything {
                    Section {
                        InlineNotice(
                            kind: .caution,
                            message: "This deletes everything currently in Odomind on this device first, including receipts."
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LuminousField(strength: 0.5))
            .navigationTitle("Restore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore") { apply() }
                        .disabled(!preview.plan.canApply || isApplying)
                }
            }
            .overlay {
                if isApplying {
                    ProgressView("Restoring…")
                        .padding(Theme.Spacing.section)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                }
            }
        }
    }
}
