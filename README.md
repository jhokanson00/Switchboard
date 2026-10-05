# Switchboard

A Mac menu bar panel of quick toggles: Dark Mode, Night Shift, hiding desktop icons, the
Dock or the menu bar, hidden files, mute, Bluetooth, keeping the Mac awake and more,
each showing its real current state. Plus a Pomodoro timer, CPU and GPU meters, and a
global keyboard shortcut for anything. Native Swift, very light on your Mac (it doesn't
poll), free and open source.

<p align="center"><img src="docs/screenshot-1.0.1.png" width="302" alt="The Switchboard panel"></p>

## Download

**[Download the latest Switchboard](https://github.com/jhokanson00/Switchboard/releases/latest)**:
open the `.dmg` and drag Switchboard to Applications, then open it. It lives in the menu
bar as a light switch; there's no Dock icon. Switchboard checks for updates once a day,
or choose **Check for Updates…** at the bottom of the panel.

- macOS 15 or later. Apple silicon and Intel.
- Signed with Developer ID and notarized by Apple.

## What's in it

**Settings**, each a switch that shows what macOS is set to right now:

- **Appearance:** Dark Mode, Night Shift.
- **Desktop & Dock:** Hide Desktop Icons, Hide Desktop Widgets, Autohide Dock, Autohide
  Menu Bar, Show Recent Apps in Dock.
- **Finder:** Show Hidden Files, Show Library Folder.
- **System:** Mute, Mute Microphone, Keep Awake, Bluetooth.

**Mute** and **Mute Microphone** work on whatever output and microphone your Mac is
using right now, and show its name. Some devices, like many USB audio interfaces, have
no mute switch; the row says so.

**Keep Awake** can run until you turn it off, for 1 to 8 hours, or while a particular app
is open (say, until Final Cut Pro finishes and quits). Use the clock button on its row.

**Actions:** Start Screen Saver; Empty Trash (always asks first, with the item count);
Eject, which ejects disk images, network drives, USB sticks and SD cards but leaves hard
disks connected. If something is holding a drive, Eject names the app.

**Pomodoro:** focus for 5, 25, 30, 45 or 60 minutes, then a 5-minute break, with a
15-minute break after every fourth session. While it runs, the minutes left show in the
menu bar. When each phase ends, a sound plays three times and a pop-up stays in the middle
of the screen until you answer it; Focus and Do Not Disturb don't hold either back. The
bell next to the focus lengths picks the sound, turns the pop-up off (a notification is
sent instead), or plays a test. While the timer runs, the Mac doesn't go to sleep on its own,
so the end isn't missed; the display still can.

**At a glance:** CPU and GPU load at the top of the panel.

**Launch at Login** is a checkbox at the bottom.

### Keyboard shortcuts

Any setting or action can have a global shortcut that works from any app: choose
**Shortcuts…** at the bottom of the panel. **Use Suggested** assigns ⌃⌥⌘ plus a letter to
everything (⌃⌥⌘D Dark Mode, ⌃⌥⌘M Mute, ⌃⌥⌘V Mute Microphone, and so on). macOS uses
⌃⌥⌘ only with digits and punctuation, and apps rarely use it at all. With the panel
closed, a brief on-screen confirmation shows what changed.

A Switchboard shortcut takes priority over the same shortcut inside another app. If one
gets in the way, record a different one.

### Undoing changes

The first time Switchboard changes a setting, it remembers what it was. When any differ,
**Restore original settings** appears at the bottom of the panel and puts them all back.
Mute, Night Shift and Keep Awake are momentary, so they aren't included. Keep Awake also
ends if Switchboard quits.

Empty Trash is the one action that can't be undone, so it always asks first.

## Privacy and permissions

Switchboard runs entirely on your Mac. It has no accounts, analytics or tracking. Its
only network request is the update check, which downloads a small file from this repo's
GitHub releases.

macOS asks for each permission the first time it's needed:

- **Automation → System Events:** Dark Mode, Autohide Dock, Autohide Menu Bar.
- **Automation → Finder:** Empty Trash, and reopening your Finder windows after a Finder
  setting changes.
- **Bluetooth:** showing and switching Bluetooth.

## How it works

| Setting | Changed with | How the row stays current |
|---|---|---|
| Dark Mode | System Events `dark mode` | Follows the app's appearance (notified) |
| Night Shift | CoreBrightness `CBBlueLightClient` (private) | Status callback (notified) |
| Hide Desktop Icons | `com.apple.WindowManager StandardHideDesktopIcons`; with Stage Manager on, `com.apple.finder CreateDesktop` written while Finder is quit | Reread when the panel opens |
| Hide Desktop Widgets | `com.apple.WindowManager StandardHideWidgets` | Reread when the panel opens |
| Autohide Dock | System Events `autohide` | Reread when the panel opens |
| Autohide Menu Bar | System Events `autohide menu bar` (`_HIHideMenuBar`) | Reread when the panel opens |
| Show Recent Apps | `com.apple.dock show-recents` + Dock restart | Reread when the panel opens |
| Show Hidden Files | `com.apple.finder AppleShowAllFiles`, written while Finder is quit | Reread when the panel opens |
| Show Library Folder | Hidden flag on `~/Library` (as `chflags`) | Reread when the panel opens |
| Mute, Mute Microphone | CoreAudio mute on the default output or input | CoreAudio listeners (notified) |
| Keep Awake | Power assertion (as `caffeinate -d`) | In-app; app quits are notified |
| Bluetooth | `IOBluetoothPreferenceSetControllerPowerState` (private) | CoreBluetooth state (notified) |

Finder writes its own settings back when it quits, so Finder settings are written while
it's closed: Finder quits, the change is written, and Finder reopens with the same
folders.

Nothing polls. Changes are noticed through system notifications where macOS offers
them, and everything else is reread when the panel opens. The Pomodoro timer wakes at
most once a minute while it runs, to update the menu bar countdown, and the CPU and GPU
meters sample every 2 seconds only while the panel is open.

Night Shift and switching Bluetooth have no public API. Switchboard uses the same
private ones Control Center and `blueutil` use, looked up at run time. If a future
macOS removes them, the row says so instead of crashing. Some audio devices (many USB
interfaces) have no mute control; the Mute row says so for those.

## Report a bug

Choose **Report a Bug…** at the bottom of the panel. It opens a GitHub issue with
your Switchboard and macOS versions filled in. Or
[open an issue](https://github.com/jhokanson00/Switchboard/issues/new/choose) directly.

## Building from source

```bash
make run     # build, install to /Applications, launch
make test    # unit tests (Pomodoro timing, shortcuts, original-settings record)
make debug   # debug build, run from ./build
```

You need Xcode 16 or later (Swift 6). `scripts/build-app.sh` signs with a Developer ID if one is
installed, else a local signing identity, so macOS remembers the permissions between
builds. `swift scripts/make-icon.swift` redraws the app icon.

### Releasing

Write the release notes first, in `docs/release-notes/<version>.md` (paragraphs and
`- ` bullets), and commit them. They appear in the app's update window and on the
GitHub release.

```bash
scripts/release.sh 1.0.0   # on a clean main: build, notarize, make the .dmg and the signed appcast.xml
git commit -am "Version 1.0.0 (build N)" && git push
scripts/publish.sh 1.0.0   # check everything again, then create the GitHub release
```

`release.sh` only builds committed source on `main`. It sets the version in
`Resources/Info.plist`, builds a universal app signed with the Developer ID certificate
in the keychain and the hardened runtime, notarizes and staples the app and the `.dmg`,
signs the `.dmg` and then the whole `appcast.xml` for Sparkle with the EdDSA key in the
keychain (`generate_keys --account Switchboard`; its public half is `SUPublicEDKey`),
and runs `scripts/check-app.sh`, which refuses any entitlement but Apple Events, any
library search path outside the app, and anything not notarized. Without a Developer ID
certificate it makes a test build that can't be published. `publish.sh` repeats the
checks on the app inside the `.dmg`, verifies both signatures, and only publishes from
the pushed commit that sets the version. Each release carries its own `appcast.xml`,
which the app reads from `releases/latest/download/appcast.xml`. Notarizing needs a
stored profile, made once:

```bash
xcrun notarytool store-credentials pane-notary --apple-id <your Apple ID> --team-id <team ID>
```

## License

MIT. See [LICENSE](LICENSE).
