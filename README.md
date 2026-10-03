# NovelReader

NovelReader is an iOS app for reading webpages and listening to novels using Apple's native text-to-speech system.

The app is designed for long-form reading and supports background audio, so you can start reading and lock your iPhone while the speech continues.

## Features

- Read text directly inside the app
- Load chapters from webpages
- Automatic article/chapter text extraction
- WTR-LAB chapter support
- WTR-LAB authenticated access
- Automatic loading of the next chapter
- Apple system speech voices
- Voice selection
- Adjustable reading speed
- Play / pause
- Next and previous chunks
- Rewind / forward by approximately one chunk
- Background audio
- Lock-screen playback
- Works with the downloaded chapter while the app is running
- No permanent chapter library

## Requirements

- macOS
- Xcode
- An Apple ID for signing the application
- iPhone running a supported version of iOS
- Internet connection when downloading a webpage or WTR-LAB chapter

A real iPhone is recommended for testing because background and lock-screen audio should be tested on an actual device.

## Building the app

### 1. Clone the repository

Clone the GitHub repository:

```bash
git clone https://github.com/YOUR_USERNAME/NovelReader.git
cd NovelReader
```

Replace the URL with the actual repository URL.

### 2. Open the project

Open `NovelReader.xcodeproj` in Xcode.

### 3. Configure signing

In Xcode:

1. Select the NovelReader project.
2. Select the NovelReader target.
3. Open **Signing & Capabilities**.
4. Select your Apple Developer team under **Team**.
5. Let Xcode create the development signing profile.

You do not need to modify the source code to add your Apple ID.

### 4. Connect an iPhone

Connect your iPhone to the Mac and select it as the run destination in Xcode.

Then press **Run ▶**.

The first installation may require you to trust the developer profile on the iPhone.

## Using the app

### Reading text manually

You can paste text directly into the text editor.

1. Paste the text into the editor.
2. Use the playback controls.
3. Press **Play**.
4. Adjust the reading speed if needed.
5. Select a different voice from **Voice**.

### Loading a webpage

Enter a chapter URL in the **Chapter URL** field.

For supported webpages:

1. Enter the chapter URL.
2. Tap **Load Chapter**.
3. NovelReader downloads the webpage.
4. The article extractor removes unnecessary webpage content.
5. The extracted chapter is loaded into the reader.
6. Press **Play**.

The chapter is kept in memory while the app is running.

### WTR-LAB

WTR-LAB chapters require an authenticated WTR-LAB session.

Use the WTR-LAB sign-in option in the app and log into your WTR-LAB account.

After authentication, NovelReader obtains the WTR-LAB session cookies and uses them for chapter requests.

You do not need to manually copy cookies from a browser.

Once authenticated:

1. Enter a WTR-LAB chapter URL.
2. Tap **Load Chapter**.
3. NovelReader requests the chapter through the WTR-LAB API.
4. The chapter is extracted and prepared for speech.
5. Start playback.

### Automatic next chapters

For supported chapter formats, NovelReader determines the next chapter URL.

When the current chapter finishes, the next chapter can automatically load and playback can continue.

This allows long reading sessions without manually loading every chapter.

## Speech controls

The player provides:

- Previous chunk
- Rewind
- Play / Pause
- Forward
- Next chunk
- Stop
- Reading speed
- Voice selection

The speech rate is adjustable from the player.

## Voice selection

Open **Voice** to choose an installed Apple speech voice.

You can also choose **Use Speak Screen Voice** to let iOS use the system accessibility speech settings.

Some voices or languages may need to be downloaded on the iPhone first.

## Lock-screen playback

NovelReader uses the iOS audio session configured for spoken audio.

To test:

1. Load a chapter.
2. Start playback.
3. Lock the iPhone.
4. Wait several minutes.
5. Confirm that playback continues.

The app also provides media controls for supported lock-screen controls.

## Internet requirement

Internet is required to download a webpage or WTR-LAB chapter.

After a chapter has been loaded into NovelReader, the extracted chapter text is available in memory and speech playback does not require an additional internet connection.

The app does not intentionally maintain a permanent chapter library.

## Privacy

NovelReader does not require the user to provide a WTR-LAB password directly to the app.

Authentication is performed through the WTR-LAB login webpage.

Authentication cookies are used to make authenticated WTR-LAB API requests.

Chapter content is kept in memory while the app is running rather than being added to a permanent chapter library.

Do not commit authentication cookies, passwords, API keys, or other credentials to GitHub.

## Project structure

```text
NovelReader/
│
├── NovelReaderApp.swift
├── ReaderView.swift
├── Chapter.swift
├── SpeechManager.swift
├── VoicePickerView.swift
├── WebPageLoader.swift
├── ArticleExtractor.swift
├── WTRLabModels.swift
├── WTRLabAPIClient.swift
├── WTRLabExtractor.swift
├── WTRLabAuthManager.swift
└── WTRLabLoginView.swift
```

## Main components

### ReaderView.swift

Main application interface and chapter loading logic.

### SpeechManager.swift

Controls Apple's `AVSpeechSynthesizer`, playback state, speech rate, voices, background audio, and media controls.

### WebPageLoader.swift

Downloads webpages without maintaining a persistent webpage cache.

### ArticleExtractor.swift

Extracts readable text from supported webpages.

### WTRLabAPIClient.swift

Communicates with the WTR-LAB API and retrieves chapter content.

### WTRLabExtractor.swift

Processes WTR-LAB chapter data, including glossary replacement and next-chapter handling.

### WTRLabAuthManager.swift

Manages the authenticated WTR-LAB WebKit session.

### WTRLabLoginView.swift

Provides the in-app WTR-LAB login interface.

## Development

After making changes:

```bash
git status
git add .
git commit -m "Describe your changes"
git push
```

For example:

```bash
git add .
git commit -m "Improve WTR-LAB authentication"
git push
```

## Troubleshooting

### The app cannot be installed

Check:

- Your iPhone is selected as the run destination.
- Your Apple ID is selected under **Signing & Capabilities**.
- The device trusts the development profile.
- Xcode can communicate with the iPhone.

### WTR-LAB chapters do not load

Check:

- You are signed into WTR-LAB.
- The WTR-LAB session is still valid.
- The chapter URL is correct.
- The iPhone has an internet connection.

### Speech stops when the phone is locked

Make sure the app is running on a real iPhone and that background audio capability is enabled for the target.

### A voice is missing

Install the required speech voice/language through the iPhone's speech accessibility settings.

## Status

NovelReader is currently an experimental project under active development.

The architecture and supported websites may change as development continues.
