# Releasing voz

Every push to `main` publishes a beta. Every tag `vMAJOR.MINOR.PATCH` publishes a stable release. Both are GitHub Releases. Beta releases are marked as prereleases.

Updates reach users through Sparkle. The appcast is `appcast.xml` in the repo root, served from `https://raw.githubusercontent.com/Joelheile/voz/main/appcast.xml`. The workflow commits to it after each release and keeps the last 10 entries per channel. Beta entries carry `<sparkle:channel>beta</sparkle:channel>`, so only users with "Receive beta updates" turned on see them.

## Versions

- Stable: `CFBundleShortVersionString` is the tag without `v`.
- Beta: latest stable version plus `-beta.<build>`, for example `0.2.0-beta.41`.
- `CFBundleVersion` is the commit count on the checked-out commit. It only grows, and Sparkle compares it.

## Secrets

Add these under Settings, Secrets and variables, Actions.

| Secret | Value | How to create it |
| --- | --- | --- |
| `VOZ_SIGNING_P12` | Base64 p12 of the "voz Dev" identity | Run `scripts/export-signing-identity.sh`, paste the contents of `voz-signing.p12.b64`, delete the file. |
| `VOZ_SIGNING_P12_PASSWORD` | The password you typed into that script | Same run. |
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA private key | Run `.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private.key` and paste the file contents. Delete the file. |

The CI build must use the same signing identity as local builds. macOS keeps microphone and accessibility permissions across updates only when the signing identity stays the same.

The public key in `Resources/Info.plist` (`SUPublicEDKey`) belongs to the key in your login keychain. If you generate a new key pair, update `SUPublicEDKey`. Apps built with the old key cannot verify updates signed with the new one.

Optional, for notarization: `APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_TEAM_ID`, `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD`.

## Repository settings

- Actions need read and write permission for the workflow token (Settings, Actions, General, Workflow permissions). The workflows request `contents: write` themselves.
- If `main` is protected, allow the `github-actions` bot to push to it. The workflow pushes the appcast commit directly.

## Cut a stable release

1. Make sure `main` has the commit you want and its beta build is green.
2. Tag and push:

   ```
   git tag v0.2.0
   git push origin v0.2.0
   ```

3. The `Release stable` workflow tests, builds, signs, creates the GitHub Release and updates `appcast.xml`.

## Check a release by hand

```
curl -s https://raw.githubusercontent.com/Joelheile/voz/main/appcast.xml
```

Open voz, choose "Check for Updates…" from the menu bar icon.

## Add notarization later

The workflow already has an optional "Notarize" step. It runs only when all five notarization secrets are set.

1. Join the Apple Developer Program and create a "Developer ID Application" certificate.
2. Export it as a p12 from Keychain Access and encode it with `base64 -i cert.p12`.
3. Create an app-specific password at appleid.apple.com.
4. Add `APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_TEAM_ID`, `DEVELOPER_ID_P12` and `DEVELOPER_ID_P12_PASSWORD`.

The step rebuilds the app with the Developer ID identity, submits it with `notarytool`, and staples the ticket. The signing identity changes at that point, so every user is asked for microphone and accessibility permissions once more after the first notarized update. After that, remove `com.apple.security.cs.disable-library-validation` from `Resources/voz.entitlements` only if Sparkle and every other framework are signed with the Developer ID identity. Test before you remove it.

## Local build with a version

```
scripts/make-app.sh 0.1.0 1
```

The arguments are optional and override `CFBundleShortVersionString` and `CFBundleVersion`.

## Entitlements

`Resources/voz.entitlements` has two entries.

- `com.apple.security.device.audio-input` lets voz record from the microphone under the hardened runtime.
- `com.apple.security.cs.disable-library-validation` lets voz load `Sparkle.framework`. Library validation only accepts frameworks signed by Apple or by the same team ID as the app. The "voz Dev" identity is self-signed and has no team ID, so macOS rejects the framework without this entitlement. Remove it after the app and Sparkle are signed with a Developer ID certificate, then test an update end to end.

## Launch agent

voz registers `Contents/Library/LaunchAgents/com.joelheile.voz.relaunch.plist` with `SMAppService.agent` when "Launch at login" is on. launchd relaunches voz after a crash or a signal. A Quit from the menu exits with code 0, so voz stays quit.

launchd binds the agent to the signature of the registered binary when the app has no team ID. After an update with a self-signed identity, launchd can refuse to start the new binary. voz then keeps running unmanaged and logs "Launch agent did not start". Signing with a Developer ID certificate removes this limit. Verify it with `kill -9` after the first Developer ID release.
