# NovelReader starter

This is a minimal iOS speech/background-audio proof of concept. It contains a text editor, a reading-speed control, and native iOS speech. Background audio is enabled in `Info.plist`.

## Open and run

1. Open `NovelReader.xcodeproj` in Xcode.
2. In the project settings, select the **NovelReader** target, then **Signing & Capabilities**. Choose your Apple ID team and let Xcode create the development profile.
3. Connect your iPhone, select it as the run destination, and press **Run**. (The simulator can check the interface, but use a real iPhone to verify locked-screen audio.)
4. Paste several paragraphs, tap **Start Reading**, lock the phone, and listen for a few minutes.
5. Try the speed slider and confirm speech remains natural.

The first run is intended to prove continuous speech while locked. It does not yet download webpages or provide lock-screen play/pause/skip controls. The current voice selection uses the device's locale; a voice must be installed on the iPhone for that language.
