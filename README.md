# Do Not Miss

Do Not Miss is a macOS menu bar app built to help you join meetings on time. It watches your upcoming Google Calendar events, detects video call links, and shows a full-screen reminder shortly before a meeting starts.

## Current Release

The current GitHub release is an alpha build for macOS.

Release page:
- [v1.0.0-alpha.2](https://github.com/noesauze/do-not-miss-public/releases/tag/v1.0.0-alpha.2)

What this means:
- core flows are already usable
- the app is still under active iteration
- the release may require manual confirmation from macOS Gatekeeper because it is currently distributed outside the Mac App Store and may not be notarized for public distribution

## What the App Does

- Lives in the macOS menu bar instead of the Dock.
- Connects to your Google account securely with OAuth.
- Reads upcoming events from your Google Calendar.
- Extracts Google Meet, Zoom, and Microsoft Teams links when present.
- Shows a fullscreen reminder shortly before the meeting starts.
- Lets you open the meeting link directly from the reminder.
- Can launch automatically at login.

## Who It Is For

Do Not Miss is for people who:
- live in Google Calendar
- jump between multiple meeting providers
- often miss the exact moment a call starts
- want a stronger reminder than a passive notification

## Installation

1. Download the latest `.dmg` from GitHub Releases:
   [v1.0.0-alpha.2](https://github.com/noesauze/do-not-miss-public/releases/tag/v1.0.0-alpha.2)
2. Open the DMG.
3. Drag `Do Not Miss.app` into `Applications`.
4. Launch the app.
5. If macOS blocks the first launch:
- right-click the app and choose `Open`
- or allow it from `System Settings > Privacy & Security`

## First Run

After launch:
- sign in with Google
- grant calendar access through the Google OAuth flow
- open Settings if you want to enable launch at login
- leave the app running in the menu bar

Once connected, the app starts monitoring upcoming meetings and will show the overlay when a supported event is about to begin.

## What To Validate In The Alpha

The alpha release is mainly intended to validate these user-facing flows:
- menu bar app launches and stays available
- Google OAuth completes successfully
- calendar events are detected correctly
- meeting links are extracted correctly
- fullscreen overlay appears at the right time
- launch at login behaves correctly across restarts

## Known Release Constraints

- This is a macOS-only app.
- A Google account and calendar access are required.
- The current public build may show Gatekeeper warnings on first launch.
- Some development-oriented behavior may still exist while the product is being hardened for production release.

## Privacy

Do Not Miss uses your Google Calendar data to identify upcoming meetings and their join links. Session information is stored locally in the macOS Keychain.

## Feedback

If something breaks, the most useful bug reports include:
- your macOS version
- what type of meeting link was expected
- whether OAuth succeeded
- whether the overlay appeared
- whether launch at login worked after a reboot

## For Developers

If you want to build the app from source or work on distribution tooling, start here:
- [README_Distribution.md](/Users/noesauzede/Repos/do-not-miss/Do%20Not%20Miss/README_Distribution.md)
