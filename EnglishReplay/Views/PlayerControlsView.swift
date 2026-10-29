import SwiftUI

struct PlayerControlsView: View {
    @ObservedObject var player: AudioPlayerController
    let segments: [TranscriptSegment]
    let leadIn: TimeInterval

    var body: some View {
        VStack(spacing: 12) {
            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0, playAfterSeeking: false) }
                ),
                in: 0...max(player.duration, 0.1)
            )
            .tint(.mint)

            HStack {
                Text(player.currentTime.playbackTimestamp)
                Spacer()
                Text(player.duration.playbackTimestamp)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack(spacing: 26) {
                Button {
                    moveToPreviousSegment()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "backward.end.fill")
                            .font(.title2)
                        Text("前の文")
                    }
                }

                Button {
                    replayCurrentSegment()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title2)
                        Text("もう一度")
                    }
                }

                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .bold))
                        .frame(width: 64, height: 64)
                        .background(Color.mint, in: Circle())
                        .foregroundStyle(.black)
                }
                .accessibilityLabel(player.isPlaying ? "一時停止" : "再生")

                Button {
                    moveToNextSegment()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "forward.end.fill")
                            .font(.title2)
                        Text("次の文")
                    }
                }

                Menu {
                    ForEach([0.7, 0.8, 1.0, 1.2, 1.5], id: \.self) { rate in
                        Button("\(rate, specifier: "%.1f")×") {
                            player.playbackRate = Float(rate)
                        }
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "speedometer")
                            .font(.title2)
                        Text("\(Double(player.playbackRate), specifier: "%.1f")×")
                    }
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var currentSegmentIndex: Int? {
        segments.firstIndex(where: { $0.contains(player.currentTime) })
            ?? segments.lastIndex(where: { $0.startTime <= player.currentTime })
    }

    private func replayCurrentSegment() {
        guard let index = currentSegmentIndex else {
            player.seek(to: 0)
            return
        }
        player.seek(to: max(0, segments[index].startTime - leadIn))
    }

    private func moveToPreviousSegment() {
        guard let index = currentSegmentIndex else {
            player.seek(to: 0)
            return
        }

        let current = segments[index]
        if player.currentTime - current.startTime > 1.5 || index == 0 {
            player.seek(to: max(0, current.startTime - leadIn))
        } else {
            player.seek(to: max(0, segments[index - 1].startTime - leadIn))
        }
    }

    private func moveToNextSegment() {
        guard let index = currentSegmentIndex, index + 1 < segments.count else { return }
        player.seek(to: max(0, segments[index + 1].startTime - leadIn))
    }
}
