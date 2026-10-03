import SwiftUI

struct ReaderView: View {
    @StateObject private var playback = SpeechPlaybackManager()
    @StateObject private var wtrLabSession = WTRLabSession()
    @State private var text =
        "Paste a few paragraphs here, then tap Start Reading. Lock the iPhone to check that playback continues."
    @State private var urlString = ""
    @State private var currentChapter: Chapter?
    @State private var nextChapterURL: URL?
    @State private var isLoading = false
    @State private var loadingError: String?
    @State private var wtrLabCookieInput = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ChapterURLInput(
                        urlString: $urlString,
                        isLoading: isLoading,
                        loadingError: loadingError,
                        wtrLabCookieInput: $wtrLabCookieInput,
                        setWTRLabCookie: setWTRLabCookie,
                        loadChapter: loadChapter
                    )

                    SpeechControls(playback: playback)

                    ChapterContentEditor(
                        text: editableText,
                        chapter: currentChapter
                    )
                }
                .padding()
            }
            .navigationTitle("NovelReader")
            .onChange(of: playback.completedChapterID) { _, completedChapterID in
                guard let currentChapter,
                      completedChapterID == currentChapter.id,
                      let nextChapterURL else {
                    return
                }

                loadChapter(from: nextChapterURL.absoluteString, automaticallyStart: true)
            }
        }
    }

    private var editableText: Binding<String> {
        Binding(
            get: { text },
            set: { newValue in
                text = newValue
                currentChapter = nil
                nextChapterURL = nil
                playback.loadManualText(newValue)
            }
        )
    }

    private func loadChapter() {
        loadChapter(from: urlString, automaticallyStart: false)
    }

    private func loadChapter(from sourceURL: String, automaticallyStart: Bool) {
        guard !isLoading else {
            return
        }

        isLoading = true
        loadingError = nil

        Task {
            do {
                let trimmedURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
                let requestedURL = URL(string: trimmedURL)
                let pageURL: URL
                let article: ExtractedArticle

                if let requestedURL, WTRLabExtractor.supports(requestedURL) {
                    guard !wtrLabSession.cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw WTRLabError.missingCookie
                    }
                    pageURL = requestedURL
                    article = try await WTRLabExtractor().extract(
                        from: requestedURL,
                        cookie: wtrLabSession.cookie
                    )
                } else {
                    let page = try await WebPageLoader().loadPage(from: sourceURL)
                    pageURL = page.url
                    article = try await Task.detached(priority: .userInitiated) {
                        try ArticleExtractor.extract(from: page.html, pageURL: page.url)
                    }.value
                }

                guard !Task.isCancelled else {
                    return
                }

                let chapter = Chapter(
                    id: UUID(),
                    url: pageURL,
                    title: article.title,
                    text: article.text
                )
                currentChapter = chapter
                nextChapterURL = article.nextURL
                text = article.text
                playback.load(chapter: chapter)
                if automaticallyStart {
                    playback.start()
                }
            } catch is CancellationError {
                return
            } catch let error as LocalizedError {
                loadingError = error.errorDescription ?? "The chapter could not be loaded."
            } catch {
                loadingError = "The chapter could not be loaded."
            }

            isLoading = false
        }
    }

    private func setWTRLabCookie() {
        wtrLabSession.cookie = wtrLabCookieInput.trimmingCharacters(in: .whitespacesAndNewlines)
        wtrLabCookieInput = ""
    }
}

private struct ChapterURLInput: View {
    @Binding var urlString: String
    let isLoading: Bool
    let loadingError: String?
    @Binding var wtrLabCookieInput: String
    let setWTRLabCookie: () -> Void
    let loadChapter: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chapter URL")
                .font(.headline)

            TextField("https://example.com/chapter-1", text: $urlString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("WTR-LAB")
                    .font(.subheadline.weight(.semibold))

                SecureField("Cookie", text: $wtrLabCookieInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                Button("Set Cookie", action: setWTRLabCookie)
                    .buttonStyle(.bordered)
                    .disabled(wtrLabCookieInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Button(action: loadChapter) {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading Chapter")
                    }
                } else {
                    Text("Load Chapter")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            if let loadingError {
                Text(loadingError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

        }
    }
}

private struct ChapterContentEditor: View {
    @Binding var text: String
    let chapter: Chapter?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let chapter {
                Text(chapter.title)
                    .font(.headline)

                Text("Downloaded webpage")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Manual Text")
                    .font(.headline)

                Text("Paste text to read it without loading a webpage.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $text)
                .frame(minHeight: 280)
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.quaternary)
                )
        }
    }
}

private struct SpeechControls: View {
    @ObservedObject var playback: SpeechPlaybackManager

    var body: some View {
        VStack(spacing: 16) {
            Text(playback.currentChapter?.title ?? "Manual Text")
                .font(.headline)
                .lineLimit(2)

            Text(playback.progressDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Reading position \(playback.progressDescription)")

            ProgressView(value: playback.progress)
                .accessibilityLabel("Chapter progress")

            HStack(spacing: 16) {
                PlaybackButton("backward.end", label: "Previous chunk", action: playback.previous)
                PlaybackButton("gobackward.5", label: "Rewind approximately 5 seconds", action: playback.rewindApproximatelyFiveSeconds)
                PlaybackButton(
                    playback.playbackState == .playing ? "pause.fill" : "play.fill",
                    label: playback.playbackState == .playing ? "Pause" : "Play",
                    action: playback.playPause
                )
                PlaybackButton("goforward.5", label: "Forward approximately 5 seconds", action: playback.forwardApproximatelyFiveSeconds)
                PlaybackButton("forward.end", label: "Next chunk", action: playback.next)
            }
            .disabled(!playback.canPlay)

            Button(action: playback.stop) {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!playback.canPlay)
            .accessibilityLabel("Stop playback")

            HStack {
                Text("Speed")

                Slider(
                    value: Binding(
                        get: { playback.rate },
                        set: { playback.setRate($0) }
                    ),
                    in: 0.35...1.0,
                    step: 0.025
                )
                .accessibilityLabel("Playback speed")

                Text(String(format: "%.2fx", playback.rate / 0.5))
                    .monospacedDigit()
                    .frame(width: 48)
            }

            NavigationLink {
                VoicePickerView(playbackManager: playback)
            } label: {
                Label("Voice", systemImage: "waveform")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Choose voice")

            if let error = playback.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct PlaybackButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    init(_ systemImage: String, label: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(minWidth: 28, minHeight: 28)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
    }
}
