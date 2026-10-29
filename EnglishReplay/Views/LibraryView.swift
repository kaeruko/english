import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var navigationPath = NavigationPath()
    @State private var isImporterPresented = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if library.documents.isEmpty {
                    ContentUnavailableView {
                        Label("音声を追加", systemImage: "waveform.badge.plus")
                    } description: {
                        Text("MP3などの英語音声を「ファイル」から読み込みます。")
                    } actions: {
                        Button("音声ファイルを選ぶ") {
                            isImporterPresented = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(library.documents) { document in
                            NavigationLink(value: document.id) {
                                AudioDocumentRow(document: document)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    library.delete(document)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("English Replay")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label("音声を追加", systemImage: "plus")
                    }
                    .disabled(isImporting)
                }
            }
            .overlay {
                if isImporting {
                    ProgressView("音声を読み込み中…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .navigationDestination(for: UUID.self) { documentID in
                PlayerView(documentID: documentID)
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                if case .failure(let error) = result {
                    errorMessage = error.localizedDescription
                }
                return
            }

            isImporting = true
            Task {
                do {
                    let id = try await library.importAudio(from: url)
                    isImporting = false
                    navigationPath.append(id)
                } catch {
                    isImporting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
        .alert("読み込めませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "不明なエラー")
        }
    }
}

private struct AudioDocumentRow: View {
    let document: AudioDocument

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: document.hasTranscript ? "text.word.spacing" : "waveform")
                .font(.title2)
                .foregroundStyle(document.hasTranscript ? .mint : .secondary)
                .frame(width: 38, height: 38)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(document.duration.playbackTimestamp)
                    Text(document.hasTranscript ? "字幕あり" : "未文字起こし")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
