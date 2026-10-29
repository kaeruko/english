import SwiftUI

struct TranscriptView: View {
    let segments: [TranscriptSegment]
    let currentTime: TimeInterval
    let leadIn: TimeInterval
    let onSeek: (TimeInterval) -> Void

    @State private var followsPlayback = true
    @State private var activeSegmentID: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(segments) { segment in
                        TranscriptSegmentCard(
                            segment: segment,
                            currentTime: currentTime,
                            leadIn: leadIn,
                            onSeek: onSeek
                        )
                        .id(segment.id)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 6).onChanged { _ in
                    followsPlayback = false
                }
            )
            .overlay(alignment: .bottomTrailing) {
                if !followsPlayback {
                    Button {
                        followsPlayback = true
                        scrollToCurrent(using: proxy, animated: true)
                    } label: {
                        Label("再生位置", systemImage: "scope")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
            }
            .onChange(of: currentSegmentID) { _, newValue in
                activeSegmentID = newValue
                guard followsPlayback, let newValue else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private var currentSegmentID: UUID? {
        segments.first(where: { $0.contains(currentTime) })?.id
    }

    private func scrollToCurrent(using proxy: ScrollViewProxy, animated: Bool) {
        guard let target = currentSegmentID ?? activeSegmentID else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .center)
            }
        } else {
            proxy.scrollTo(target, anchor: .center)
        }
    }
}

private struct TranscriptSegmentCard: View {
    let segment: TranscriptSegment
    let currentTime: TimeInterval
    let leadIn: TimeInterval
    let onSeek: (TimeInterval) -> Void

    private var isActive: Bool {
        segment.contains(currentTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                onSeek(max(0, segment.startTime - leadIn))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text(segment.startTime.playbackTimestamp)
                }
                .font(.caption.monospacedDigit().weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isActive ? .mint : .secondary)

            WordWrapLayout(spacing: 5) {
                ForEach(segment.words) { word in
                    Button {
                        onSeek(max(0, word.startTime - leadIn))
                    } label: {
                        Text(word.text.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.body)
                            .fontWeight(isWordActive(word) ? .bold : .regular)
                            .foregroundStyle(isWordActive(word) ? Color.black : Color.primary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 3)
                            .background(
                                isWordActive(word) ? Color.mint : Color.clear,
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(word.text)、\(word.startTime.playbackTimestamp)から再生")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isActive ? Color.mint.opacity(0.10) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isActive ? Color.mint.opacity(0.6) : Color.clear, lineWidth: 1)
        }
    }

    private func isWordActive(_ word: TranscriptWord) -> Bool {
        currentTime >= word.startTime && currentTime < word.endTime
    }
}

private struct WordWrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > maxWidth {
                cursor.x = 0
                cursor.y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(cursor)
            cursor.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, cursor.x - spacing)
        }

        return (
            CGSize(width: min(usedWidth, maxWidth), height: cursor.y + rowHeight),
            points
        )
    }
}
