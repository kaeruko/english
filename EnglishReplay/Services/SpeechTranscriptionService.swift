import AVFoundation
import Foundation
import Speech

enum TranscriptionFailure: LocalizedError {
    case permissionDenied
    case unavailable
    case englishNotSupported
    case noTimedText

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "音声認識の使用が許可されていません。設定アプリから許可してください。"
        case .unavailable:
            return "この端末では端末内文字起こしを利用できません。"
        case .englishNotSupported:
            return "この端末では英語の文字起こしモデルを利用できません。"
        case .noTimedText:
            return "時間情報付きの字幕を生成できませんでした。"
        }
    }
}

@MainActor
final class SpeechTranscriptionService: ObservableObject {
    enum State: Equatable {
        case idle
        case preparingModel
        case transcribing
        case finished
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var progress: Double = 0

    var isWorking: Bool {
        state == .preparingModel || state == .transcribing
    }

    func transcribe(audioURL: URL, duration: TimeInterval) async throws -> [TranscriptSegment] {
        progress = 0
        state = .preparingModel

        do {
            try await requestAuthorization()

            guard SpeechTranscriber.isAvailable else {
                throw TranscriptionFailure.unavailable
            }

            guard let english = await SpeechTranscriber.supportedLocale(
                equivalentTo: Locale(identifier: "en-US")
            ) else {
                throw TranscriptionFailure.englishNotSupported
            }

            let transcriber = SpeechTranscriber(
                locale: english,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: [.audioTimeRange]
            )

            if let installation = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]
            ) {
                try await installation.downloadAndInstall()
            }

            state = .transcribing
            let audioFile = try AVAudioFile(forReading: audioURL)
            let analyzer = SpeechAnalyzer(modules: [transcriber])

            let resultTask = Task { @MainActor [weak self] in
                var segments: [TranscriptSegment] = []
                for try await result in transcriber.results {
                    guard result.isFinal else { continue }
                    segments.append(contentsOf: Self.makeSegments(from: result))

                    let end = result.range.end.seconds
                    if duration > 0, end.isFinite {
                        self?.progress = min(max(end / duration, 0), 0.99)
                    }
                }
                return segments
            }
            defer { resultTask.cancel() }

            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }

            let segments = try await resultTask.value
            guard !segments.isEmpty else {
                throw TranscriptionFailure.noTimedText
            }

            progress = 1
            state = .finished
            return segments.sorted { $0.startTime < $1.startTime }
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    private func requestAuthorization() async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard status == .authorized else {
            throw TranscriptionFailure.permissionDenied
        }
    }

    private static func makeSegments(
        from result: SpeechTranscriber.Result
    ) -> [TranscriptSegment] {
        var timedWords: [TranscriptWord] = []
        var untimedPrefix = ""

        for run in result.text.runs {
            let rawText = String(result.text[run.range].characters)
            guard let timeRange = run.audioTimeRange else {
                if timedWords.isEmpty {
                    untimedPrefix += rawText
                } else {
                    timedWords[timedWords.count - 1].text += rawText
                }
                continue
            }

            let start = timeRange.start.seconds
            let end = timeRange.end.seconds
            guard start.isFinite, end.isFinite, !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            timedWords.append(
                TranscriptWord(
                    text: untimedPrefix + rawText,
                    startTime: max(0, start),
                    endTime: max(start, end)
                )
            )
            untimedPrefix = ""
        }

        if !untimedPrefix.isEmpty, !timedWords.isEmpty {
            timedWords[timedWords.count - 1].text += untimedPrefix
        }

        if timedWords.isEmpty {
            let text = String(result.text.characters).collapsedWhitespace
            let start = result.range.start.seconds
            let end = result.range.end.seconds
            guard !text.isEmpty, start.isFinite, end.isFinite else { return [] }
            timedWords = [
                TranscriptWord(text: text, startTime: max(0, start), endTime: max(start, end))
            ]
        }

        return groupIntoReadableSegments(timedWords)
    }

    private static func groupIntoReadableSegments(
        _ words: [TranscriptWord]
    ) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var group: [TranscriptWord] = []

        func flush() {
            guard let first = group.first, let last = group.last else { return }
            let rawText = group.map(\.text).joined()
            let fallbackText = group
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: " ")
            let text = rawText.contains(where: { $0.isWhitespace })
                ? rawText.collapsedWhitespace
                : fallbackText
            segments.append(
                TranscriptSegment(
                    text: text,
                    startTime: first.startTime,
                    endTime: last.endTime,
                    words: group
                )
            )
            group.removeAll(keepingCapacity: true)
        }

        for word in words {
            group.append(word)
            let text = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let endsSentence = text.last.map { ".!?".contains($0) } ?? false
            let duration = (group.last?.endTime ?? 0) - (group.first?.startTime ?? 0)
            let longEnough = group.count >= 16 || duration >= 8
            let pauseAfterWord: Bool

            if let index = words.firstIndex(where: { $0.id == word.id }), index + 1 < words.count {
                pauseAfterWord = words[index + 1].startTime - word.endTime >= 0.7
            } else {
                pauseAfterWord = true
            }

            if endsSentence || longEnough || (pauseAfterWord && duration >= 2) {
                flush()
            }
        }
        flush()
        return segments
    }
}
