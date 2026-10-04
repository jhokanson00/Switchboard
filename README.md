# Switchboard

A macOS menu bar panel of quick toggles. Each row shows the setting's real current
state, and every switch can be flipped back.

**Settings:** Dark Mode, Night Shift, Hide Desktop Icons, Hide Desktop Widgets, Autohide
Dock, Autohide Menu Bar, Show Recent Apps in Dock, Show Hidden Files, Show Library Folder,
Mute, Mute Microphone, Keep Awake (for a set time, or while an app is open), Bluetooth.
**Actions:** Start Screen Saver, Empty Trash (asks first), Eject (USB sticks, SD cards,
disk images and network drives; hard disks stay connected).
**Pomodoro:** 5, 25, 30, 45 or 60-minute focus, 5-minute breaks, a 15-minute break after
every fourth.
**At a glance:** CPU and GPU load, sampled only while the panel is open.
**Keyboard shortcuts:** any setting or action can have a global shortcut (Shortcuts… at
the bottom of the panel). With the panel closed, a brief on-screen confirmation shows
what changed. "Use Suggested" assigns ⌃⌥⌘ plus a letter to everything (⌃⌥⌘D Dark Mode,
⌃⌥⌘M Mute, and so on); macOS uses ⌃⌥⌘ only with digits and punctuation.

Requires macOS 15 or later.

## Build and run

```sh
make run     # build, install to /Applications, launch
make test    # unit tests (Pomodoro timing, original-settings record)
make debug   # debug build, run from ./build
```

`scripts/build-app.sh` signs with your Developer ID if one is installed, so macOS
remembers the permissions between builds.

## Permissions

- **Automation → System Events:** Dark Mode, Autohide Dock, Autohide Menu Bar.
- **Automation → Finder:** Empty Trash.
- **Bluetooth:** showing and switching Bluetooth.

macOS asks for each one the first time it's needed.

## How each setting works

| Setting | Changed with | How the row stays current |
|---|---|---|
| Dark Mode | System Events `dark mode` | Follows the app's appearance (notified) |
| Night Shift | CoreBrightness `CBBlueLightClient` (private) | Status callback (notified) |
| Hide Desktop Icons | `com.apple.finder CreateDesktop`, written while Finder is quit | Reread when the panel opens |
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

The two private APIs (Night Shift and switching Bluetooth) are looked up at run time.
If a future macOS removes them, the row says so instead of crashing.

## Undoing changes

The first time Switchboard changes a setting, it remembers the original value. When any
differ, **Restore original settings** appears at the bottom of the panel and puts them
back. Mute, Night Shift and Keep Awake are momentary, so they aren't included. Keep
Awake also ends if Switchboard quits.

Empty Trash is the one action that can't be undone, so it always shows how many items
will be deleted and asks first.
