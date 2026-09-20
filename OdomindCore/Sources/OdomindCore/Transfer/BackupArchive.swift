import Foundation

/// A specification the owner recorded for one of their vehicles.
public struct VehicleSpecificationRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID { specification.id }
    public var vehicleID: UUID
    public var specification: Specification

    public init(vehicleID: UUID, specification: Specification) {
        self.vehicleID = vehicleID
        self.specification = specification
    }
}

/// An attachment carried inside a backup.
///
/// Files travel base64-encoded inside the archive so a backup is a single,
/// self-contained document that restores without any unzip support. `checksum`
/// and `byteCount` catch a truncated or edited file before anything is written.
public struct BackupAttachment: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var fileName: String
    public var contentType: String
    public var byteCount: Int
    public var checksum: String
    /// `nil` when the owner exported without attachments.
    public var base64Data: String?

    public init(
        id: UUID,
        fileName: String,
        contentType: String,
        byteCount: Int,
        checksum: String,
        base64Data: String?
    ) {
        self.id = id
        self.fileName = fileName
        self.contentType = contentType
        self.byteCount = byteCount
        self.checksum = checksum
        self.base64Data = base64Data
    }

    public static func make(id: UUID, fileName: String, contentType: String, data: Data) -> BackupAttachment {
        BackupAttachment(
            id: id,
            fileName: fileName,
            contentType: contentType,
            byteCount: data.count,
            checksum: Checksum.fnv1a(data),
            base64Data: data.base64EncodedString()
        )
    }

    /// Decodes and verifies the payload, returning `nil` when it does not match
    /// the recorded size and checksum.
    public func decodedData() -> Data? {
        guard let base64Data, let data = Data(base64Encoded: base64Data) else { return nil }
        guard data.count == byteCount, Checksum.fnv1a(data) == checksum else { return nil }
        return data
    }
}

/// A portable, dependency-free content hash.
///
/// Not a cryptographic digest and not presented as one: it exists to detect
/// accidental corruption in a backup file, and it works identically on every
/// platform the core is built for.
public enum Checksum {
    public static func fnv1a(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x1000_0000_01b3
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(hash, radix: 16)
    }
}

public struct BackupSettings: Codable, Hashable, Sendable {
    public var reminderSettings: ReminderSettings
    public var selectedVehicleID: UUID?
    public var catalogVersion: String?

    public init(
        reminderSettings: ReminderSettings = .default,
        selectedVehicleID: UUID? = nil,
        catalogVersion: String? = nil
    ) {
        self.reminderSettings = reminderSettings
        self.selectedVehicleID = selectedVehicleID
        self.catalogVersion = catalogVersion
    }
}

/// The versioned backup document.
public struct BackupArchive: Codable, Hashable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var generatedBy: String
    public var exportedOn: Date
    public var vehicles: [Vehicle]
    public var readings: [OdometerReading]
    public var planItems: [MaintenancePlanItem]
    public var serviceRecords: [ServiceRecord]
    public var specifications: [VehicleSpecificationRecord]
    public var attachments: [BackupAttachment]
    public var settings: BackupSettings

    public init(
        formatVersion: Int = BackupArchive.currentFormatVersion,
        generatedBy: String,
        exportedOn: Date,
        vehicles: [Vehicle],
        readings: [OdometerReading],
        planItems: [MaintenancePlanItem],
        serviceRecords: [ServiceRecord],
        specifications: [VehicleSpecificationRecord],
        attachments: [BackupAttachment],
        settings: BackupSettings
    ) {
        self.formatVersion = formatVersion
        self.generatedBy = generatedBy
        self.exportedOn = exportedOn
        self.vehicles = vehicles
        self.readings = readings
        self.planItems = planItems
        self.serviceRecords = serviceRecords
        self.specifications = specifications
        self.attachments = attachments
        self.settings = settings
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = DateCoding.encodingStrategy
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = DateCoding.decodingStrategy
        return decoder
    }

    public func encoded() throws -> Data {
        try BackupArchive.makeEncoder().encode(self)
    }

    public static func decode(_ data: Data) throws -> BackupArchive {
        try makeDecoder().decode(BackupArchive.self, from: data)
    }
}
