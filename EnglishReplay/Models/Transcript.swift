import Foundation

struct TranscriptWord: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
}

struct TranscriptSegment: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var words: [TranscriptWord]

    func contains(_ time: TimeInterval) -> Bool {
        time >= startTime && time < endTime
    }
}
