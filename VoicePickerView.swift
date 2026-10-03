import SwiftUI
import AVFoundation

struct VoicePickerView: View {
    @ObservedObject var playbackManager: SpeechPlaybackManager

    var body: some View {
        List {
            Section {
                Button {
                    playbackManager.useSpeakScreenVoice()
                } label: {
                    HStack {
                        Text("Use Speak Screen Voice")

                        Spacer()

                        if playbackManager.selectedVoiceIdentifier == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            ForEach(playbackManager.availableVoices, id: \.identifier) { voice in
                Button {
                    playbackManager.setVoice(voice)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(voice.name)
                                .foregroundStyle(.primary)

                            Text(voice.language)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if playbackManager.selectedVoiceIdentifier == voice.identifier {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        .navigationTitle("Voice")
    }
}
