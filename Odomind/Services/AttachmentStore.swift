import Foundation
import OdomindCore

/// Manages receipt and photo files on disk.
///
/// Files live in a directory Odomind owns, named by identifier so nothing about
/// the vehicle or the service leaks into a filename. Deleting a record deletes
/// its files; the sweep catches anything a crash left behind.
final class AttachmentStore {
    let directory: URL
    private let fileManager: FileManager

    init(directory: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.directory = support.appendingPathComponent("Odomind/Attachments", isDirectory: true)
        }
        try fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func url(forFileName fileName: String) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Writes `data` and returns the metadata to record alongside it.
    ///
    /// The write is atomic, so a failure part-way through never leaves a partial
    /// receipt that later fails its checksum.
    func store(data: Data, contentType: String, caption: String? = nil, id: UUID = UUID()) throws -> AttachmentMetadata {
        let fileName = "\(id.uuidString).\(Self.fileExtension(for: contentType))"
        let destination = url(forFileName: fileName)
        try data.write(to: destination, options: [.atomic])
        return AttachmentMetadata(
            id: id,
            fileName: fileName,
            contentType: contentType,
            byteCount: data.count,
            createdAt: Date(),
            caption: caption
        )
    }

    func data(for metadata: AttachmentMetadata) throws -> Data {
        try Data(contentsOf: url(forFileName: metadata.fileName))
    }

    func exists(_ metadata: AttachmentMetadata) -> Bool {
        fileManager.fileExists(atPath: url(forFileName: metadata.fileName).path)
    }

    func delete(fileName: String) {
        try? fileManager.removeItem(at: url(forFileName: fileName))
    }

    func delete(_ metadataList: [AttachmentMetadata]) {
        for metadata in metadataList { delete(fileName: metadata.fileName) }
    }

    /// Removes files no record refers to any more.
    ///
    /// Called after deletes and on launch. Returns how many it removed so the
    /// diagnostics screen can show that cleanup is actually happening.
    @discardableResult
    func removeOrphans(keepingFileNames known: Set<String>) -> Int {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return 0 }

        var removed = 0
        for file in contents where !known.contains(file.lastPathComponent) {
            do {
                try fileManager.removeItem(at: file)
                removed += 1
            } catch {
                continue
            }
        }
        return removed
    }

    func deleteEverything() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in contents {
            try? fileManager.removeItem(at: file)
        }
    }

    static func fileExtension(for contentType: String) -> String {
        switch contentType.lowercased() {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "image/heic": return "heic"
        case "application/pdf": return "pdf"
        default: return "bin"
        }
    }
}
