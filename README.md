# FocusGate

A personal Mac app that watches for browser time. If a browser is your frontmost app for 5 consecutive minutes, a window appears asking:

1. What task will you work on next?
2. What is your very next step?

The window stays on top until both fields are filled in. Each answer is logged to `~/focus-log.txt`.

It runs from the menu bar (🎯 when active, 💤 when off or paused) and has no Dock icon.

## Requirements

- macOS with the Xcode command line tools:

  ```
  xcode-select --install
  ```

## Build

From the folder containing `FocusGate.swift`:

```
swiftc FocusGate.swift -o focusgate
```

The first build prints a `remark` about a prebuilt standard library. That is normal and only happens once.

## Quick test (10-second timer)

Use a short timer so you don't wait 5 minutes.

```
sed -i '' 's/thresholdSeconds = 300/thresholdSeconds = 10/' FocusGate.swift
swiftc FocusGate.swift -o focusgate
./focusgate &
```

1. Confirm 🎯 appears in the menu bar.
2. Stay in a browser for 10 seconds. The prompt should appear.
3. Confirm Submit stays disabled until both fields have text.
4. Submit, then check `cat ~/focus-log.txt`.

Stop the test:

```
pkill focusgate
```

Restore the real 5-minute timer:

```
sed -i '' 's/thresholdSeconds = 10/thresholdSeconds = 300/' FocusGate.swift
```

## Install

```
swiftc FocusGate.swift -o focusgate
mkdir -p ~/bin
mv focusgate ~/bin/focusgate
```

Run it manually any time with:

```
~/bin/focusgate &
```

## Start automatically at login

Create a LaunchAgent and load it:

```
mkdir -p ~/Library/LaunchAgents
cat > ~/Library/LaunchAgents/com.me.focusgate.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.me.focusgate</string>
  <key>ProgramArguments</key><array><string>$HOME/bin/focusgate</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
</dict></plist>
EOF
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.me.focusgate.plist
```

It starts immediately and on every login after that.

`KeepAlive` is `false` so that **Quit** in the menu actually quits. Set it to `true` if you want the app to relaunch whenever it is closed (this also makes it harder to dodge).

## Daily use

Click the menu bar icon:

- **Enabled**: permanent on/off switch (remembered across restarts)
- **Pause 30 minutes / 1 hour / 2 hours**: temporary break, resumes automatically
- **Resume now**: ends a pause early
- **Quit**: closes the app (it will start again at next login)

Turning it off or pausing resets the 5-minute counter.

## Updating after you edit the code

```
swiftc FocusGate.swift -o focusgate
mv focusgate ~/bin/focusgate
launchctl kickstart -k gui/$(id -u)/com.me.focusgate
```

## Configuration

Edit the top of `FocusGate.swift`:

- `browserIDs`: browsers to watch. Find a bundle ID with `osascript -e 'id of app "Browser Name"'`.
- `thresholdSeconds`: time in a browser before the prompt (default 300).
- Pause lengths: the `("Pause 2 hours", 120)` list in `updateMenu()`; the number is minutes.

## Uninstall

```
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.me.focusgate.plist
rm ~/Library/LaunchAgents/com.me.focusgate.plist ~/bin/focusgate
```

Optionally delete `~/focus-log.txt`.

## Troubleshooting

- **No 🎯 in the menu bar**: run `pgrep focusgate`. If a number prints, it is running and the icon may be hidden behind the notch or a crowded menu bar.
- **Prompt never appears**: your browser's bundle ID may not be in `browserIDs`, or the app is not running.
- **`launchctl bootstrap` says it's already loaded**: run `launchctl kickstart -k gui/$(id -u)/com.me.focusgate` instead.
- **Prompt is stuck and won't close**: press Cmd+Option+Esc and force quit it, or run `pkill focusgate` from another device. If `KeepAlive` is `true`, run `launchctl bootout` first so it does not relaunch.

## Privacy

FocusGate makes no network connections. It only reads which app is frontmost and whatever you type into its two fields. The log file is plain text; restrict it with `chmod 600 ~/focus-log.txt` if needed.
