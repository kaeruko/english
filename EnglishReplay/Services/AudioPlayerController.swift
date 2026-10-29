import AVFoundation
import Combine
import MediaPlayer

@MainActor
final class AudioPlayerController: ObservableObject {
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isReady = false
    @Published var playbackRate: Float = 1.0 {
        didSet {
            if isPlaying {
                player?.playImmediately(atRate: playbackRate)
            }
            updateNowPlaying()
        }
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var remoteCommandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var nowPlayingTitle = ""

    init() {
        configureAudioSession()
        configureRemoteCommands()
    }

    deinit {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        for item in remoteCommandTargets {
            item.command.removeTarget(item.target)
        }
    }

    func load(url: URL, title: String, duration knownDuration: TimeInterval, resumeAt: TimeInterval) {
        removeObservers()

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player
        nowPlayingTitle = title
        duration = knownDuration
        isReady = true
        addObservers(to: player, item: item)

        if resumeAt > 0 {
            seek(to: resumeAt, playAfterSeeking: false)
        } else {
            updateNowPlaying()
        }
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard isReady else { return }
        player?.playImmediately(atRate: playbackRate)
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func seek(to seconds: TimeInterval, playAfterSeeking: Bool = true) {
        guard let player else { return }
        let target = min(max(0, seconds), max(duration, 0))
        let time = CMTime(seconds: target, preferredTimescale: 600)
        currentTime = target

        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished, playAfterSeeking else { return }
            Task { @MainActor in
                self?.play()
            }
        }
        updateNowPlaying()
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds, playAfterSeeking: isPlaying)
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    private func addObservers(to player: AVPlayer, item: AVPlayerItem) {
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite {
                    self.currentTime = seconds
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.updateNowPlaying()
            }
        }
    }

    private func removeObservers() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        let playTarget = commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        remoteCommandTargets.append((commands.playCommand, playTarget))

        let pauseTarget = commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        remoteCommandTargets.append((commands.pauseCommand, pauseTarget))

        commands.skipBackwardCommand.preferredIntervals = [10]
        let backwardTarget = commands.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: -10) }
            return .success
        }
        remoteCommandTargets.append((commands.skipBackwardCommand, backwardTarget))

        commands.skipForwardCommand.preferredIntervals = [10]
        let forwardTarget = commands.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: 10) }
            return .success
        }
        remoteCommandTargets.append((commands.skipForwardCommand, forwardTarget))
    }

    private func updateNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: nowPlayingTitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0
        ]
    }
}
