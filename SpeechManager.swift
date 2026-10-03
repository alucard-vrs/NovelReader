@preconcurrency import AVFoundation
import MediaPlayer
import SwiftUI

@MainActor
final class SpeechPlaybackManager: NSObject, ObservableObject {
    enum PlaybackState: Sendable {
        case stopped
        case playing
        case paused
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let remoteCommandCenter = MPRemoteCommandCenter.shared()
    private var pendingSpeechRequestID: UUID?
    private var speechStartTask: Task<Void, Never>?
    private var activeUtterance: AVSpeechUtterance?
    private var chunkStartedAt: Date?
    private var mustRestartCurrentChunk = false

    private(set) var currentChapter: Chapter?
    private var chunks: [String] = []

    @Published private(set) var playbackState: PlaybackState = .stopped
    @Published private(set) var completedChapterID: UUID?
    @Published private(set) var currentChunkIndex = 0
    @Published private(set) var chunkCount = 0
    @Published var selectedVoiceIdentifier: String?
    @Published var rate: Float = 0.5
    @Published private(set) var errorMessage: String?

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
        loadSettings()
        configureRemoteCommands()
    }

    var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .sorted {
                let lhs = "\($0.language) \($0.name)"
                let rhs = "\($1.language) \($1.name)"
                return lhs < rhs
            }
    }

    var progressDescription: String {
        guard chunkCount > 0 else {
            return "No chapter loaded"
        }
        return "\(min(currentChunkIndex + 1, chunkCount)) / \(chunkCount)"
    }

    var progress: Double {
        guard chunkCount > 0 else {
            return 0
        }
        return Double(currentChunkIndex + 1) / Double(chunkCount)
    }

    var canPlay: Bool {
        !chunks.isEmpty
    }

    func load(chapter: Chapter) {
        stop()
        completedChapterID = nil
        currentChapter = chapter
        chunks = makeSpeechChunks(from: chapter.text)
        chunkCount = chunks.count
        currentChunkIndex = 0
        updateNowPlayingInfo()
    }

    func loadManualText(_ text: String) {
        stop()
        completedChapterID = nil
        currentChapter = nil
        chunks = makeSpeechChunks(from: text)
        chunkCount = chunks.count
        currentChunkIndex = 0
        updateNowPlayingInfo(title: "Manual Text")
    }

    func playPause() {
        switch playbackState {
        case .stopped:
            start()
        case .playing:
            pause()
        case .paused:
            resume()
        }
    }

    func start() {
        switch playbackState {
        case .stopped:
            playCurrentChunk()
        case .paused:
            resume()
        case .playing:
            break
        }
    }

    func stop() {
        speechStartTask?.cancel()
        speechStartTask = nil
        pendingSpeechRequestID = nil
        chunkStartedAt = nil
        mustRestartCurrentChunk = false
        synthesizer.stopSpeaking(at: .immediate)
        activeUtterance = nil
        playbackState = .stopped
        currentChunkIndex = 0
        updateNowPlayingInfo()
    }

    func next() {
        guard !chunks.isEmpty else {
            return
        }

        let nextIndex = min(currentChunkIndex + 1, chunks.count - 1)
        guard nextIndex != currentChunkIndex else {
            return
        }
        moveToChunk(at: nextIndex)
    }

    func previous() {
        guard !chunks.isEmpty else {
            return
        }

        let hasJustStarted = chunkStartedAt.map { Date().timeIntervalSince($0) < 3 } ?? true
        let previousIndex = hasJustStarted ? max(currentChunkIndex - 1, 0) : currentChunkIndex
        moveToChunk(at: previousIndex)
    }

    // AVSpeechSynthesizer does not expose exact time seeking, so these move by a chunk.
    func rewindApproximatelyFiveSeconds() {
        guard !chunks.isEmpty else {
            return
        }
        moveToChunk(at: max(currentChunkIndex - 1, 0))
    }

    // AVSpeechSynthesizer does not expose exact time seeking, so these move by a chunk.
    func forwardApproximatelyFiveSeconds() {
        next()
    }

    func setVoice(_ voice: AVSpeechSynthesisVoice) {
        selectedVoiceIdentifier = voice.identifier
        UserDefaults.standard.set(voice.identifier, forKey: "selectedVoiceIdentifier")
        restartCurrentChunkIfNeeded()
    }

    func useSpeakScreenVoice() {
        selectedVoiceIdentifier = nil
        UserDefaults.standard.removeObject(forKey: "selectedVoiceIdentifier")
        restartCurrentChunkIfNeeded()
    }

    func setRate(_ rate: Float) {
        self.rate = rate
        UserDefaults.standard.set(rate, forKey: "speechRate")
        restartCurrentChunkIfNeeded()
    }

    private func pause() {
        guard playbackState == .playing else {
            return
        }

        speechStartTask?.cancel()
        speechStartTask = nil
        pendingSpeechRequestID = nil
        playbackState = .paused
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
        }
        updateNowPlayingInfo()
    }

    private func resume() {
        guard !chunks.isEmpty else {
            playbackState = .stopped
            return
        }

        playbackState = .playing
        if mustRestartCurrentChunk {
            mustRestartCurrentChunk = false
            playCurrentChunk()
            updateNowPlayingInfo()
            return
        }
        if synthesizer.isPaused {
            if !synthesizer.continueSpeaking() {
                playCurrentChunk()
            }
        } else {
            playCurrentChunk()
        }
        updateNowPlayingInfo()
    }

    private func moveToChunk(at index: Int) {
        guard chunks.indices.contains(index) else {
            return
        }

        let shouldPlay = playbackState == .playing
        speechStartTask?.cancel()
        speechStartTask = nil
        pendingSpeechRequestID = nil
        chunkStartedAt = nil
        synthesizer.stopSpeaking(at: .immediate)
        activeUtterance = nil
        currentChunkIndex = index

        if shouldPlay {
            playCurrentChunk()
        } else {
            updateNowPlayingInfo()
        }
    }

    private func restartCurrentChunkIfNeeded() {
        switch playbackState {
        case .playing:
            moveToChunk(at: currentChunkIndex)
        case .paused:
            // A paused utterance cannot adopt a new rate or voice. Resume starts this chunk anew.
            speechStartTask?.cancel()
            speechStartTask = nil
            pendingSpeechRequestID = nil
            mustRestartCurrentChunk = true
            synthesizer.stopSpeaking(at: .immediate)
            activeUtterance = nil
            chunkStartedAt = nil
            updateNowPlayingInfo()
        case .stopped:
            updateNowPlayingInfo()
        }
    }

    private func playCurrentChunk() {
        guard chunks.indices.contains(currentChunkIndex) else {
            playbackState = .stopped
            updateNowPlayingInfo()
            return
        }

        errorMessage = nil
        playbackState = .playing

        // Invalidate any older asynchronous speech-start operation first.
        speechStartTask?.cancel()

        let requestID = UUID()
        pendingSpeechRequestID = requestID
        let chunk = chunks[currentChunkIndex]

        speechStartTask = Task { [weak self] in
            await self?.beginSpeaking(chunk, requestID: requestID)
        }

        updateNowPlayingInfo()
    }

    private func beginSpeaking(_ chunk: String, requestID: UUID) async {
        do {
            try await configureAudioSession()
        } catch {
            guard !Task.isCancelled,
                  pendingSpeechRequestID == requestID,
                  playbackState == .playing else {
                return
            }

            errorMessage = "Unable to start audio playback: \(error.localizedDescription)"
            playbackState = .stopped
            speechStartTask = nil
            updateNowPlayingInfo()
            return
        }

        // The audio-session activation is asynchronous. A newer request may
        // have replaced this one while activation was in progress.
        guard !Task.isCancelled,
              pendingSpeechRequestID == requestID,
              playbackState == .playing else {
            return
        }

        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        activeUtterance = nil

        guard !Task.isCancelled,
              pendingSpeechRequestID == requestID,
              playbackState == .playing else {
            return
        }

        let utterance = AVSpeechUtterance(string: chunk)

        if let identifier = selectedVoiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        } else {
            utterance.prefersAssistiveTechnologySettings = true
        }

        // This remains the only source of the actual speech rate.
        utterance.rate = rate

        guard !Task.isCancelled,
              pendingSpeechRequestID == requestID,
              playbackState == .playing else {
            return
        }

        // Keep the exact utterance identity so delayed delegate callbacks
        // from a previous chunk cannot advance the current chapter.
        activeUtterance = utterance
        synthesizer.speak(utterance)
        speechStartTask = nil
    }

    private func makeSpeechChunks(from text: String) -> [String] {
        let paragraphs = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return paragraphs.flatMap(splitLongParagraph)
    }

    private func splitLongParagraph(_ paragraph: String) -> [String] {
        let maximumChunkLength = 900
        guard paragraph.count > maximumChunkLength else {
            return [paragraph]
        }

        let sentences = paragraph.split(whereSeparator: { ".!?".contains($0) })
        var chunks: [String] = []
        var currentChunk = ""

        for sentence in sentences {
            let next = currentChunk.isEmpty ? String(sentence) : "\(currentChunk). \(sentence)"
            if next.count > maximumChunkLength, !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = String(sentence)
            } else {
                currentChunk = next
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        return chunks
    }

    private func configureAudioSession() async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let audioSession = AVAudioSession.sharedInstance()
                do {
                    try audioSession.setCategory(.playback, mode: .spokenAudio)
                    if #available(iOS 27.0, *) {
                        audioSession.activate(options: []) { success, error in
                            if success {
                                continuation.resume()
                            } else {
                                continuation.resume(
                                    throwing: error ?? SpeechPlaybackError.audioSessionActivationFailed
                                )
                            }
                        }
                    } else {
                        try audioSession.setActive(true)
                        continuation.resume()
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

    }

    private func loadSettings() {
        selectedVoiceIdentifier = UserDefaults.standard.string(forKey: "selectedVoiceIdentifier")
        if UserDefaults.standard.object(forKey: "speechRate") != nil {
            rate = UserDefaults.standard.float(forKey: "speechRate")
        }
    }

    private func configureRemoteCommands() {
        remoteCommandCenter.playCommand.isEnabled = true
        remoteCommandCenter.pauseCommand.isEnabled = true
        remoteCommandCenter.nextTrackCommand.isEnabled = true
        remoteCommandCenter.previousTrackCommand.isEnabled = true
        remoteCommandCenter.skipBackwardCommand.isEnabled = true
        remoteCommandCenter.skipForwardCommand.isEnabled = true
        remoteCommandCenter.skipBackwardCommand.preferredIntervals = [5]
        remoteCommandCenter.skipForwardCommand.preferredIntervals = [5]

        _ = [
            remoteCommandCenter.playCommand.addTarget { [weak self] _ in
                Task { @MainActor in self?.resume() }
                return .success
            },
            remoteCommandCenter.pauseCommand.addTarget { [weak self] _ in
                Task { @MainActor in self?.pause() }
                return .success
            },
            remoteCommandCenter.nextTrackCommand.addTarget { [weak self] _ in
                Task { @MainActor in self?.next() }
                return .success
            },
            remoteCommandCenter.previousTrackCommand.addTarget { [weak self] _ in
                Task { @MainActor in self?.previous() }
                return .success
            },
            remoteCommandCenter.skipBackwardCommand.addTarget { [weak self] _ in
                Task { @MainActor in self?.rewindApproximatelyFiveSeconds() }
                return .success
            },
            remoteCommandCenter.skipForwardCommand.addTarget { [weak self] _ in
                Task { @MainActor in self?.forwardApproximatelyFiveSeconds() }
                return .success
            }
        ]
    }

    private func updateNowPlayingInfo(title: String? = nil) {
        let chapterTitle = title ?? currentChapter?.title ?? "NovelReader"
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "NovelReader"
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: chapterTitle,
            MPMediaItemPropertyArtist: appName,
            MPNowPlayingInfoPropertyPlaybackRate: playbackState == .playing ? Double(rate / 0.5) : 0,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: currentChunkIndex,
            MPNowPlayingInfoPropertyPlaybackQueueCount: chunkCount
        ]
    }

    private func handleDidStart(_ utterance: AVSpeechUtterance) {
        guard playbackState == .playing,
              let activeUtterance,
              activeUtterance === utterance else {
            return
        }

        chunkStartedAt = Date()
        updateNowPlayingInfo()
    }

    private func handleDidFinish(_ utterance: AVSpeechUtterance) {
        // AVSpeechSynthesizer can deliver a delayed finish callback for an
        // utterance that we already stopped. Ignore callbacks for old chunks.
        guard playbackState == .playing,
              let activeUtterance,
              activeUtterance === utterance else {
            return
        }

        self.activeUtterance = nil

        if currentChunkIndex + 1 < chunks.count {
            currentChunkIndex += 1
            playCurrentChunk()
        } else {
            playbackState = .stopped
            chunkStartedAt = nil
            completedChapterID = currentChapter?.id
            updateNowPlayingInfo()
        }
    }

    private func handleDidCancel(_ utterance: AVSpeechUtterance) {
        // Cancellation is expected when changing speed, voice, chunk, or
        // stopping. Do not let a delayed cancellation affect playback state.
        guard let activeUtterance,
              activeUtterance === utterance else {
            return
        }
    }
}

extension SpeechPlaybackManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.handleDidStart(utterance)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.handleDidFinish(utterance)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.handleDidCancel(utterance)
        }
    }
}

private enum SpeechPlaybackError: LocalizedError {
    case audioSessionActivationFailed

    var errorDescription: String? {
        "The audio session could not be activated."
    }
}
