# Google TV Remote

Google TV Remote is a simple app that turns an Android phone or iPhone into a remote control for Google TV.

The Android version is ready to download. The iOS 18+ version is experimental, source-only, and is not built on GitHub.

## Get the app

Download the Android app from the [Releases](https://github.com/oskuhsiu/google-tv-remote/releases) page.

For iOS, generate the project with XcodeGen and build and sign the app using your own Apple provisioning.

## Platform features

### Android floating remote

After connecting to a TV, enable **Floating remote** in the app and grant the **Display over other apps** permission. Leaving the app turns it into a movable bubble:

- Tap the bubble to show compact direction, OK, Back, Home, volume, and mute controls.
- Drag the bubble to reposition it, or long-press it to return to the full app.
- Use **Exit floating remote** to disconnect and disable the floating feature completely.

The floating remote only appears while a TV is connected. Android keeps it running as a foreground connected-device service, so an ongoing notification is shown. Device-specific battery restrictions may still stop the service.

### iOS Widget and Control Center

The iOS 18+ target includes:

- Small, medium, and large **TV Remote** Home Screen Widgets with Up, Down, Left, Right, OK, Back, and Home buttons. Resize the Widget in Home Screen edit mode; the large layout provides larger keypad buttons.
- A Control Center **Remote** item that opens the compact remote in the app.
- An optional **Keep Ready** setting that attempts to retain the authenticated TV connection in the background for faster Widget commands.

Build and open the app once before adding the Widget. Then long-press the Home Screen, choose **Add Widget**, and search for **TV Remote**.

Widget commands require an already paired and reachable TV session; the Widget does not perform discovery or pairing. Its buttons are disabled when the connection is unavailable, and iOS may suspend or terminate the app at any time. **Keep Ready** uses silent background audio, which can use more battery, is not guaranteed to keep the connection alive, and may be rejected during App Store review. A `NoKeepAlive` Xcode configuration is provided without this background-audio behavior.

### Network Wake (WOL)

Both phone apps provide **Network Wake** settings and a guide for finding the TV's MAC address. iOS uses manual MAC entry; Android also attempts a best-effort lookup after pairing.

1. Turn on the TV and open its **Settings** or **Help** menu with the TV remote.
2. Find the MAC address. Google TV Streamer and Chromecast use **Settings > System > About > Status**. TCL Google TV commonly shows it under **Network & Internet > the connected network**. Sony models may show it under **Help > Status & Diagnostics > Network status**. Menus vary by model.
3. Enter the MAC for the TV's current connection: Wi-Fi MAC for Wi-Fi, or Ethernet/wired MAC for a cable. Keep the phone and TV on the same local network. If offered, enable **Network Standby** or **Remote Start**, and leave the TV plugged in.

Use the settings' explicit wake-packet test after putting the TV in standby. Saving a MAC or successfully sending a packet does not confirm that the TV supports network wake or has woken up. Support varies by model and by Wi-Fi versus Ethernet.

iOS device builds require Apple approval for the **Multicast Networking** capability and a provisioning profile that authorizes `com.apple.developer.networking.multicast`. The app declares this entitlement for WOL broadcasts. Allow **Local Network** access when prompted. Simulator UI checks do not verify physical-TV wake behavior or device provisioning.

## How to use on Android

1. Connect your phone and Google TV to the same Wi-Fi network.
2. Open the app and choose your TV.
3. Enter the six-character code shown on the TV.
4. Use the on-screen buttons to control the TV.

If your TV does not appear, enter its IP address from the TV's network settings.

Android first reconnects to the last successful IP. If that address is unreachable and the TV's discovery name was saved, it resolves that specific TV again and verifies the original TV certificate before saving the new IP. It does not browse for other TVs. TVs paired only by manual IP without a saved discovery name still need their current IP entered manually. If the same TV no longer accepts the phone's certificate, Connect opens the pairing-code screen again.

New Android and iOS pairings use a unique certificate CN and matching client name, retained across reconnects. Existing working pairings are preserved. When the original TV rejects an older fixed-name certificate, the app stages a unique-CN replacement using the same private key and asks for the TV code again; it saves the replacement only after pairing and the authenticated remote connection succeed. Certificate import and export are deferred.

The current iOS target is still experimental: it can discover nearby Google TVs, but pairing a newly discovered TV is not complete. Both Android and iOS include hold-to-talk voice search for a connected TV. TV text input is not implemented yet. Both phone apps are portrait-only.

## Build from source

Android requires JDK 17 and an Android SDK. Build and run its local checks with:

```bash
cd android
./gradlew test :app:assembleDebug
```

iOS requires Xcode with the iOS 18 SDK and XcodeGen. `ios/project.yml` is the source of truth for the generated Xcode project:

```bash
cd ios
xcodegen generate
open AndroidTVRemote.xcodeproj
```

Select the `AndroidTVRemote` scheme for the experimental Keep Ready mode, or `AndroidTVRemote-NoKeepAlive` to build without background audio. Signing must be configured with your own Apple developer account.

## Developer

Developed by Codex using a Sol model.

## License

The original work is released under the very permissive [0BSD license](LICENSE). Third-party parts keep their own licenses.

Google TV is a trademark of Google LLC. This independent project is not affiliated with or endorsed by Google.
