# GRAVITY Comment Reader Implementation Plan

> Use superpowers:executing-plans for inline execution. User explicitly requests autonomous choices and no intermediate design approvals.

Goal: A native Mac OCR/TTS application with bounded latency and separate PRIVATE/ROOM audio routes.
Architecture: Pure Swift/Foundation detector and queue; Mac-only capture, OCR, output and AppKit adapter.
Tech Stack: macOS14+, Swift5 language mode, Apple system frameworks, no runtime third-party dependency.
Spec: docs/design.md

## Constraints / review focus
- Preserve the existing music files. Work under gravity-reader only, no worktrees.
- Never announce an untested Mac API or iPhone room transmission as verified.
- Repeated text, OCR jitter, rapid scroll, pauses and device removal must not cause unbounded or old speech.
- Screen selection across multiple monitors must use display-relative coordinates.
- Queue callbacks after stop must be invalidated by session generation.

## Task 1: detector and queue
Files: Sources/CommentCore.swift, Tests/main.swift, scripts/test-core.sh.
Interfaces: OCRLine(text, confidence, x, y, width, height), CommentDetector.ingest(lines)->[String]; FreshSpeechQueue.enqueue/pop/clear.
- [x] Write and run tests: startup baseline, stable new comments, repeated occurrence, transient OCR, systems, screen reset, queue overflow/staleness, age boundary, normalization.
- [x] Implement pure Swift core and run all tests.

## Task 2: Mac adapters and UI
Files: Sources/CaptureOCR.swift, Sources/SpeechOutput.swift, Sources/App.swift.
Interfaces: CaptureOCR.selectRegion/capture()->[OCRLine]; SpeechOutput.devices/configure/speak/stop.
- [x] Add Mac-specific tests for image OCR and audio-route enumeration, runnable on Mac only.
- [x] Implement region selection, non-overlapping background OCR and AppKit control panel.
- [x] Implement PCM speech synthesis routed through AVAudioEngine selected CoreAudio output.
- [x] Add simulated replay using the same detector/queue, independent of Mac capture.
- [x] Parse Swift source on Linux; label typecheck/permissions/audio integration pending Mac.

## Task 3: launcher and delivery
Files: 起動.command, scripts/build-mac.sh, scripts/test-mac.sh, README.md, docs/verification.md.
- [x] First-run toolchain detection, version check, app bundle/plist creation, incremental rebuild and ad-hoc signing.
- [x] Run shell validation, core tests and replay; archive source and launcher, check ZIP integrity.
- [x] Whole-application review and fixes; deliver download link with clear validation boundaries.

Native Mac compilation/runtime remain explicitly unverified; checked steps mean implementation and environment-appropriate checks, not native runtime completion.
