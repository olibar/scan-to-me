# Scan to Me (iOS)

iPhone/iPad app that registers the device as a "Scan to Computer" destination
on network all-in-ones (today HP inkjets via LEDM on port 8080/80, or eSCL
walkup subscriptions (announced port, else 80) for models that dropped LEDM), receives
the pages when the user presses Scan on the printer and saves them as PDF or
JPEG. Standalone project: the Go client `hpscan` (github.com/olibar/hpscan)
was the protocol reference, nothing is shared with it. Names are brand-neutral
(app ScanToMe, package ScanKit) because other printer brands may follow; keep
brand names out of identifiers, UI strings and App Store metadata.

## Layout

- `Packages/ScanKit` -- SwiftPM package, zero dependencies, iOS 17 /
  macOS 14. All protocol, session state machine, PDF writing, discovery and
  file output. Builds and tests on a Mac with Command Line Tools only.
  - `Sources/ScanKit/{XML,LEDM,ESCL,Session,Output,Discovery}`. The session
    tries LEDM first and falls back to eSCL (`PrinterSession+ESCL.swift`);
    eSCL event polling runs in its own task and must never pause during a
    scan, or the panel reports the file could not be saved.
  - `Sources/scankit-cli` -- macOS harness (`discover`, `serve`) to validate
    the protocol against a real printer without Xcode.
  - `Tests/ScanKitTests` -- Swift Testing (`import Testing`, `#expect`), fake
    printer transport (`FakePrinter` actor behind `HTTPTransport`), XML fixtures.
- `ScanToMe/` -- the iOS app target (SwiftUI + UIKit glue only). Opened via
  `ScanToMe.xcodeproj`, which is generated from `project.yml` with XcodeGen.
  Edit `project.yml`, never the target settings in Xcode; regenerate with
  `xcodegen generate` and commit both.
- `design/make-icon.swift` -- generator of the app icon (`swift
  design/make-icon.swift` from the repo root rewrites AppIcon.png and the
  iOS 18 dark and tinted variants). Change the icon there, never by editing
  the PNGs.

## Commands

```sh
cd Packages/ScanKit && swift build && swift test      # core, works with CLT alone
swift run scankit-cli discover                          # list _scanner._tcp on the LAN
swift run scankit-cli serve 192.168.1.20:8080 --out ~/Scans --name "My iPhone"
xcodegen generate                                       # after changing project.yml
xcodebuild -scheme ScanToMe -destination 'generic/platform=iOS Simulator' build
```

## Conventions

- Swift 6 language mode, strict concurrency. Sessions are actors, UI state is
  `@MainActor @Observable`, cross-task data is `Sendable` value types.
- Debug logging with `os.Logger(subsystem: "com.obarlier.scantome", category:)`
  at operation start/end and decision points, prefixed with the component
  (`ledm:`, `session:`, `discover:`, `sink:`). Never log full page payloads.
- Every network call has an explicit per-request timeout
  (`URLRequest.timeoutInterval`); the event long-poll is `wait + 30 s`.
- Errors carry context (`LEDMError.status(method, path, status, body)`).
- ASCII only in code, comments, docs and commit messages.
- New settings: update `ScanPreferences`, its `validate()`, the SettingsView
  form and the README table in the same commit.
- iOS runs the listener in the foreground only. Do not add background modes
  or audio hacks without an explicit request.

## Release (App Store)

- Product name `ScanToMe`, bundle id `com.obarlier.scantome`, home-screen
  name "Scan to Me". Published from Olivier's individual developer account
  (obarlier@gmail.com, team QUQFF7KH2L, set in project.yml), not SiniMed.
  Xcode also holds the SiniMed Apple ID (company team 2E9B65SZ35 and its free
  personal team RXKYE6K3M8): never sign this app with either. The 1.0 submission under SiniMed
  (`com.sinimed.hpscan`, "Scan to Me for HP printers") was rejected for naming
  HP hardware without authorization and is abandoned.
- App Review: no printer brand in the name, subtitle, keywords, description,
  screenshots or in-app text. Store texts and review notes are kept in
  `appstore/metadata.md`; update it with every submission. The supported-printer list lives on the website
  (`docs/`, GitHub Pages), used as the Support URL.
- To ship: bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION` for every
  upload) in `project.yml`, run `xcodegen generate`, commit, tag `vX.Y.Z`,
  then in Xcode select "Any iOS Device", Product > Archive, Distribute App >
  App Store Connect. Attach the processed build to the version in App Store
  Connect and fill "What's New".
- `ScanToMe/Info.plist` carries `ITSAppUsesNonExemptEncryption = NO` (plain
  HTTP only) and `ScanToMe/PrivacyInfo.xcprivacy` declares no tracking and no
  collected data; keep both true if networking or analytics ever change.
- The website is `docs/` (GitHub Pages, https://olibar.github.io/scan-to-me/):
  supported printers, support, privacy policy (`docs/privacy.md`), linked from App Store
  Connect. Reviewers have no compatible printer: the review notes explain the
  requirement; attach a screen recording of a real scan.
- Screenshots: 6.9" iPhone (iPhone 17 Pro Max simulator, 1320x2868) and 13"
  iPad (2064x2752); use the Manual add with the printer's IP from a simulator.

## Git

Feature branches (`feature/<name>`, `bugfix/<name>`), merge to `main`.
