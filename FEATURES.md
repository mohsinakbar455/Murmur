# Murmur — Current Feature Log

Last checked: October 11, 2026 (macOS app, v1.1.0)

Murmur is a private, on-device push-to-talk dictation app. It records speech, transcribes and cleans the result locally, applies saved personalization rules, then inserts the finished text into the app that was already in focus.

## Core dictation

- **Push to talk:** Use a configurable keyboard shortcut to start dictating. Murmur supports both hold-to-talk and press-to-toggle modes.
- **Focused-app insertion:** After transcription, the cleaned text is inserted at the cursor in the app you were using.
- **Live voice HUD:** A floating, non-activating indicator shows recording, processing, audio level, and errors without taking focus away from the destination app.
- **Local processing:** Speech recognition and optional cleanup run on the Mac with the selected on-device model.
- **Personalized output:** Dictionary corrections and snippet expansions are applied before text is inserted.

## Dashboard

- Shows the current idle, recording, and transcribing state with a live signal display.
- Includes an in-app **Test Dictation** flow that records and transcribes without inserting text into another app.
- Tracks words dictated, spoken-audio duration, average processing latency, and estimated time saved.
- Stores recent dictations locally, with actions to copy or delete individual entries and clear the full history.

## Voice Models

- Displays the active transcription engine and its speed, language coverage, disk size, and compute type.
- Lets the user search, download, activate, remove, or inspect supported local models.
- Supports model families including Parakeet, Whisper, and Apple Speech, depending on installation and language needs.

## File Transcription

- Transcribes audio or video files locally through drag and drop or the file picker.
- Supports MP3, M4A, WAV, MP4, MOV, FLAC, and AAC files.
- Provides separate model, language, and cleanup choices for each transcription job.
- Shows loading, transcription, formatting, error, and cancellation states.
- Results can be selected, copied, or exported as plain text or JSON.
- Keeps a short list of recent file-transcription results for quick copying.

## Personalization

- **Snippets:** Map a memorable spoken shortcut, such as “slash intro,” to reusable saved text.
- **Dictionary terms:** Teach Murmur the preferred spelling of names, jargon, acronyms, and phrases.
- **Spelling corrections:** Map what Murmur commonly hears to the exact text it should write.
- Entries can be searched, edited, enabled or disabled, and deleted.

## Settings and controls

- Change the dictation shortcut and recording mode.
- Select and test the microphone, choose a transcription language, and enable recording sounds.
- Toggle automatic formatting and on-device smart cleanup.
- Set the Dashboard display name and choose System, Light, or Dark appearance.
- Control local history saving and clipboard restoration after text insertion.
- Advanced controls include typing-speed estimation and preference reset.

## Permissions and privacy

- **Microphone permission** is required to capture speech.
- **Accessibility permission** is required to detect the global shortcut and insert text into other apps.
- Dictation, personalization data, and saved history remain on the Mac.

## Writing Assistant (macOS)

- Enable or hide it in **Settings → Text cleanup → Writing Assistant**.
- A solid sparkle button appears beside supported text editors. Select text, click the button, then choose Proofread, Rewrite, Friendly, Professional, Concise, Summary, Key Points, List, Table, or a custom instruction.
- Each action runs through the selected, downloaded Qwen writing model on this Mac. Compose accepts an instruction with optional source text.
- Successful replacement closes the menu. Reopen it within 30 seconds for **Undo last edit**, available only while the inserted text and caret remain unchanged.
- The microphone fills the custom instruction field using the selected speech engine; submit the instruction to apply it. Instruction recordings are not inserted into the editor or saved as dictation history.
- Use the menu-bar **Writing Assistant…** entry to paste text when an editor does not expose a usable selection.
- Processing failures preserve the original. Changed selections and unconfirmed delivery retain a copyable result. Output is plain text; tables use Markdown and rich-text styling may change.
