import SwiftUI
import UIKit
import OdomindCore

struct ServiceRecordDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let recordID: UUID

    @State private var showingEdit = false
    @State private var showingDeleteConfirmation = false
    @State private var previewAttachment: AttachmentPreview?

    private var record: ServiceRecord? {
        model.snapshot.serviceRecords.first { $0.id == recordID }
    }

    var body: some View {
        Group {
            if let record, let vehicle = model.snapshot.vehicle(id: record.vehicleID) {
                content(record: record, vehicle: vehicle)
            } else {
                ContentUnavailableView(
                    "Record not found",
                    systemImage: "questionmark.folder",
                    description: Text("This service record may have been deleted.")
                )
            }
        }
        .navigationTitle("Service")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(record: ServiceRecord, vehicle: Vehicle) -> some View {
        List {
            if record.isDemo {
                Section {
                    InlineNotice(kind: .caution, message: "This is fictional sample data, not a real service.")
                }
            }

            Section {
                ValueRow(label: "Date", value: Format.longDate(record.performedOn), symbolName: "calendar")
                if let odometer = record.odometer {
                    ValueRow(label: "Odometer", value: Format.distance(odometer), symbolName: "gauge.with.dots.needle.33percent")
                }
                ValueRow(label: "Performed by", value: record.performer.displayName, symbolName: "person")
                ValueRow(label: "Vehicle", value: vehicle.displayName, symbolName: "car.side")
            }

            Section {
                ForEach(record.items) { item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(item.action.verb) \(item.title)")
                        if let cost = item.itemCost {
                            Text(Format.money(cost))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Work done")
            } footer: {
                if record.items.count > 1, record.totalCost != nil {
                    Text("The cost below covers this whole visit. It is counted once, not once per task.")
                }
            }

            if let cost = record.totalCost {
                Section("Cost") {
                    ValueRow(label: "Total", value: Format.money(cost))
                }
            }

            if let notes = record.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes).fixedSize(horizontal: false, vertical: true)
                }
            }

            if !record.attachmentIDs.isEmpty {
                Section("Attachments") {
                    ForEach(record.attachmentIDs, id: \.self) { id in
                        if let metadata = model.snapshot.attachment(id: id) {
                            Button {
                                if let data = model.attachmentData(id) {
                                    previewAttachment = AttachmentPreview(data: data, metadata: metadata)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "paperclip")
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(metadata.caption ?? "Receipt")
                                            .foregroundStyle(.primary)
                                        Text("\(Format.byteCount(metadata.byteCount)) · added \(Format.date(metadata.createdAt))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Button("Edit this record") { showingEdit = true }
                Button("Delete this record", role: .destructive) { showingDeleteConfirmation = true }
            } footer: {
                Text("Editing or deleting a record recalculates every schedule it affects.")
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showingEdit) {
            LogServiceView(vehicle: vehicle, editingRecord: record)
        }
        .sheet(item: $previewAttachment) { preview in
            AttachmentPreviewView(preview: preview)
        }
        .confirmationDialog("Delete this record?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    await model.deleteService(id: recordID)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the record and any receipt attached to it, and recalculates the schedules it affected.")
        }
    }
}

struct AttachmentPreview: Identifiable {
    let id = UUID()
    let data: Data
    let metadata: AttachmentMetadata
}

struct AttachmentPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let preview: AttachmentPreview

    var body: some View {
        NavigationStack {
            Group {
                if preview.metadata.contentType.hasPrefix("image/"),
                   let image = UIImage(data: preview.data) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .accessibilityLabel(Text(preview.metadata.caption ?? "Receipt image"))
                    }
                } else {
                    ContentUnavailableView(
                        "Cannot preview this file",
                        systemImage: "doc",
                        description: Text("Odomind can show images here. The file is stored safely either way.")
                    )
                }
            }
            .navigationTitle(preview.metadata.caption ?? "Attachment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
