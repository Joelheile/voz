# Releasing voz

Every push to `main` publishes a beta. Every tag `vMAJOR.MINOR.PATCH` publishes a stable release. Both are GitHub Releases. Beta releases are marked as prereleases.

Sparkle delivers updates. The appcast is `appcast.xml` in the repo root, served from `https://raw.githubusercontent.com/Joelheile/voz/main/appcast.xml`. The workflow commits to it after each release and keeps the last 10 entries per channel. Beta entries have `<sparkle:channel>beta</sparkle:channel>`, so only users who turn on "Beta updates" see them.

## Versions

- Stable: `CFBundleShortVersionString` is the tag without `v`.
- Beta: latest stable version plus `-beta.<build>`, for example `0.2.0-beta.41`.
- `CFBundleVersion` is the commit count on the checked-out commit. It only increases. Sparkle compares it.

## Secrets

Add these secrets under Settings, Secrets and variables, Actions.

| Secret | Value | How to create it |
| --- | --- | --- |
| `VOZ_SIGNING_P12` | Base64 p12 of the "voz Dev" identity | Run `scripts/export-signing-identity.sh`, paste the contents of `voz-signing.p12.b64`, delete the file. |
| `VOZ_SIGNING_P12_PASSWORD` | The password you typed into that script | Same run. |
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA private key | Run `.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private.key` and paste the file contents. Delete the file. |

The CI build must use the same signing identity as local builds. macOS keeps microphone and Accessibility permissions across updates only when the signing identity stays the same.

`SUPublicEDKey` in `Resources/Info.plist` is the public key for the private key in your login keychain. If you generate a new key pair, update `SUPublicEDKey`. Apps built with the old key cannot verify updates signed with the new key.

For notarization, add these optional secrets: `APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_TEAM_ID`, `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD`.

## Repository settings

- Give the workflow token read and write permission (Settings, Actions, General, Workflow permissions). The workflows request `contents: write` themselves.
- If `main` is protected, allow the `github-actions` bot to push to it. The workflow pushes the appcast commit directly.

## Cut a stable release

1. Confirm that `main` has the commit you want and that its beta build passes.
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

Then open voz and choose "Check for Updates…" from the menu bar icon.

## Add notarization later

The workflow has an optional "Notarize" step. It runs only when all five notarization secrets are set.

1. Join the Apple Developer Program and create a "Developer ID Application" certificate.
2. Export it as a p12 from Keychain Access and encode it with `base64 -i cert.p12`.
3. Create an app-specific password at appleid.apple.com.
4. Add `APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_TEAM_ID`, `DEVELOPER_ID_P12` and `DEVELOPER_ID_P12_PASSWORD`.

The step rebuilds the app with the Developer ID identity, submits it with `notarytool`, and staples the ticket. The signing identity changes, so macOS asks every user for microphone and Accessibility permissions again after the first notarized update. Remove `com.apple.security.cs.disable-library-validation` from `Resources/voz.entitlements` only if Sparkle and every other framework are signed with the Developer ID identity. Test before you remove it.

## Local build with a version

```
scripts/make-app.sh 0.1.0 1
```

The arguments are optional and override `CFBundleShortVersionString` and `CFBundleVersion`.

## Entitlements

`Resources/voz.entitlements` has two entitlements.

- `com.apple.security.device.audio-input` lets voz record from the microphone under the hardened runtime.
- `com.apple.security.cs.disable-library-validation` lets voz load `Sparkle.framework`. Library validation only accepts frameworks signed by Apple or by the same team ID as the app. The "voz Dev" identity is self-signed and has no team ID, so macOS rejects the framework without this entitlement. After you sign the app and Sparkle with a Developer ID certificate, remove this entitlement and test an update end to end.

## Launch agent

When "Launch at login" is on, voz registers `Contents/Library/LaunchAgents/com.joelheile.voz.relaunch.plist` with `SMAppService.agent`. launchd relaunches voz after a crash or a signal. "Quit voz" in the menu exits with code 0, so voz stays closed.

When the app has no team ID, launchd binds the agent to the signature of the registered binary. After an update with a self-signed identity, launchd can refuse to start the new binary. voz then runs unmanaged and logs "Launch agent did not start". A Developer ID certificate removes this limit. After the first Developer ID release, verify it with `kill -9`.
