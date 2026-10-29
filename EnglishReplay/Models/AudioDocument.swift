import Foundation

struct AudioDocument: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var fileName: String
    var importedAt = Date()
    var duration: TimeInterval
    var transcript: [TranscriptSegment] = []
    var transcribedAt: Date?
    var lastPlaybackTime: TimeInterval = 0
    var leadIn: TimeInterval = 0.4

    var hasTranscript: Bool {
        !transcript.isEmpty
    }
}
