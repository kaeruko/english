import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase

    let documentID: UUID

    @StateObject private var player = AudioPlayerController()
    @StateObject private var transcriber = SpeechTranscriptionService()
    @State private var errorMessage: String?
    @State private var didLoadPlayer = false

    var body: some View {
        Group {
            if let document {
                VStack(spacing: 0) {
                    if document.hasTranscript {
                        TranscriptView(
                            segments: document.transcript,
                            currentTime: player.currentTime,
                            leadIn: document.leadIn,
                            onSeek: { player.seek(to: $0) }
                        )
                    } else {
                        transcriptionPlaceholder(document)
                    }

                    PlayerControlsView(
                        player: player,
                        segments: document.transcript,
                        leadIn: document.leadIn
                    )
                }
                .navigationTitle(document.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        leadInMenu(document)
                    }
                }
                .task {
                    loadPlayerIfNeeded(document)
                }
            } else {
                ContentUnavailableView("音声が見つかりません", systemImage: "exclamationmark.triangle")
            }
        }
        .onDisappear {
            player.pause()
            library.updatePlaybackTime(player.currentTime, for: documentID)
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .background || newValue == .inactive {
                library.updatePlaybackTime(player.currentTime, for: documentID)
            }
        }
        .alert("処理できませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "不明なエラー")
        }
    }

    private var document: AudioDocument? {
        library.document(id: documentID)
    }

    @ViewBuilder
    private func transcriptionPlaceholder(_ document: AudioDocument) -> some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "text.badge.plus")
                .font(.system(size: 54))
                .foregroundStyle(.mint)

            VStack(spacing: 8) {
                Text("タップできる字幕を作成")
                    .font(.title2.bold())
                Text("英語モデルを初回だけダウンロードし、\n端末内で音声を文字起こしします。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if transcriber.isWorking {
                VStack(spacing: 10) {
                    ProgressView(value: transcriber.progress)
                        .tint(.mint)
                        .frame(maxWidth: 260)
                    Text(transcriptionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("文字起こしを開始") {
                    beginTranscription(document)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.mint)
                .foregroundStyle(.black)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var transcriptionStatus: String {
        switch transcriber.state {
        case .preparingModel:
            return "英語モデルを準備しています…"
        case .transcribing:
            return "文字起こし中… \(Int(transcriber.progress * 100))%"
        default:
            return "準備しています…"
        }
    }

    private func loadPlayerIfNeeded(_ document: AudioDocument) {
        guard !didLoadPlayer else { return }
        didLoadPlayer = true
        player.load(
            url: library.audioURL(for: document),
            title: document.title,
            duration: document.duration,
            resumeAt: document.lastPlaybackTime
        )
    }

    private func beginTranscription(_ document: AudioDocument) {
        Task {
            do {
                let transcript = try await transcriber.transcribe(
                    audioURL: library.audioURL(for: document),
                    duration: document.duration
                )
                try library.updateTranscript(transcript, for: document.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func leadInMenu(_ document: AudioDocument) -> some View {
        Menu {
            Section("タップした位置より前から再生") {
                ForEach([0.0, 0.2, 0.4, 0.8], id: \.self) { value in
                    Button {
                        library.updateLeadIn(value, for: document.id)
                    } label: {
                        if document.leadIn == value {
                            Label("\(value, specifier: "%.1f")秒", systemImage: "checkmark")
                        } else {
                            Text("\(value, specifier: "%.1f")秒")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel("再生位置の設定")
    }
}
