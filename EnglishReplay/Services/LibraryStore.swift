import AVFoundation
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var documents: [AudioDocument] = []

    private let fileManager = FileManager.default
    private let rootDirectory: URL
    private let audioDirectory: URL
    private let metadataURL: URL

    init() {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        rootDirectory = applicationSupport.appendingPathComponent("EnglishReplay", isDirectory: true)
        audioDirectory = rootDirectory.appendingPathComponent("Audio", isDirectory: true)
        metadataURL = rootDirectory.appendingPathComponent("library.json")

        do {
            try fileManager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
            try load()
        } catch {
            assertionFailure("ライブラリを準備できませんでした: \(error)")
        }
    }

    func audioURL(for document: AudioDocument) -> URL {
        audioDirectory.appendingPathComponent(document.fileName)
    }

    func document(id: UUID) -> AudioDocument? {
        documents.first { $0.id == id }
    }

    @discardableResult
    func importAudio(from sourceURL: URL) async throws -> UUID {
        let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let id = UUID()
        let fileExtension = sourceURL.pathExtension.isEmpty ? "mp3" : sourceURL.pathExtension
        let fileName = "\(id.uuidString).\(fileExtension.lowercased())"
        let destinationURL = audioDirectory.appendingPathComponent(fileName)

        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        do {
            let asset = AVURLAsset(url: destinationURL)
            let duration = try await asset.load(.duration).seconds
            let title = sourceURL.deletingPathExtension().lastPathComponent
            let document = AudioDocument(
                id: id,
                title: title,
                fileName: fileName,
                duration: duration.isFinite ? duration : 0
            )
            documents.insert(document, at: 0)
            try save()
            return id
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    func updateTranscript(_ transcript: [TranscriptSegment], for id: UUID) throws {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].transcript = transcript
        documents[index].transcribedAt = Date()
        try save()
    }

    func updatePlaybackTime(_ time: TimeInterval, for id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].lastPlaybackTime = max(0, time)
        try? save()
    }

    func updateLeadIn(_ leadIn: TimeInterval, for id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].leadIn = leadIn
        try? save()
    }

    func delete(_ document: AudioDocument) {
        try? fileManager.removeItem(at: audioURL(for: document))
        documents.removeAll { $0.id == document.id }
        try? save()
    }

    private func load() throws {
        guard fileManager.fileExists(atPath: metadataURL.path) else { return }
        let data = try Data(contentsOf: metadataURL)
        documents = try JSONDecoder.englishReplay.decode([AudioDocument].self, from: data)
    }

    private func save() throws {
        let data = try JSONEncoder.englishReplay.encode(documents)
        try data.write(to: metadataURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var englishReplay: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var englishReplay: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
