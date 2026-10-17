# Extension security and marketplaces

Research for the voz extension system, October 2026. voz extensions have full access by design. This page records what other platforms do and which parts voz uses.

## What other platforms do

| Platform   | Isolation                                   | Review                                                                         | Notes                                                                                                                                                                   |
| ---------- | ------------------------------------------- | ------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| pi         | None                                        | None                                                                           | Security warning in the docs. Packages on npm and git. Gallery lists npm packages with the `pi-package` keyword. Versioned specs are pinned and skipped by `pi update`. |
| Raycast    | Node worker per extension, memory limit     | Pull request to one open-source repo, reviewed by staff                        | Only registered messages cross the boundary. Sandboxing was rejected as too expensive.                                                                                  |
| Obsidian   | None, plugins get full app access           | Automated scan on every version, manual review for popular plugins             | Restricted Mode blocks third-party code by default. Policy bans obfuscated code, self-updating and client telemetry.                                                    |
| VS Code    | None at runtime                             | Malware scan on publish and rescans, secret scanning, sandboxed behavior check | Verified publisher badge proves domain ownership, not safety. Malicious extensions still got through in 2025.                                                           |
| Chrome MV3 | Per-extension permissions, host permissions | Store review                                                                   | Bans remotely hosted code, so review covers everything the extension runs.                                                                                              |
| Figma      | QuickJS compiled to WebAssembly             | Review                                                                         | Moved from Realms to QuickJS after a sandbox escape. Plugin UI runs in a separate iframe.                                                                               |
| Zed        | WebAssembly through Wasmtime                | Pull request to an extensions repo                                             | Capabilities through WIT interfaces. Cannot modify UI.                                                                                                                  |
| Deno       | Deny by default, `--allow-*` flags          | n/a                                                                            | Per-process permissions, scoped to paths and hosts.                                                                                                                     |

## Supply chain

- Shai-Hulud (2025) spread through npm `postinstall` and later `preinstall` scripts. It stole npm and GitHub tokens and republished itself. Updates were the infection point.
- Bun does not run dependency lifecycle scripts unless the package is in `trustedDependencies`. `--ignore-scripts` turns them all off.
- npm provenance links a package to its source repo and CI build through Sigstore. It proves where a package was built, not that it is safe.

## What voz does

- No sandbox. Sandboxing would block the extensions voz wants (UI, audio, files) and the platforms that tried it either limit what extensions can do (Zed, Figma) or spent years on it (Chrome).
- `--ignore-scripts` on every install and update. Installing a package does not run its code.
- Exact versions on install. Packages change only on `voz update`, never in the background.
- Pinned specs (`npm:x@1.2.0`, `git:...@v1`) are skipped by `voz update`.
- A warning on every install.
- The host only accepts registered messages from extensions, as in Raycast.
- A crash or hang in an extension does not affect dictation: timeouts, a ping watchdog and restarts.
- Recordings reach disk only when an extension listens for them, and voz deletes each file afterwards.

## Later, for a marketplace

- A gallery that lists npm packages with the `voz-package` keyword, like pi.
- Show npm provenance in the gallery and in `voz install`.
- A safe mode that starts voz without extensions, like Obsidian's Restricted Mode.

## Sources

- [pi packages and extensions docs](https://www.npmjs.com/package/@mariozechner/pi-coding-agent)
- [How the Raycast API and extensions work](https://www.raycast.com/blog/how-raycast-api-extensions-work)
- [Raycast security](https://developers.raycast.com/information/security)
- [Raycast publish an extension](https://developers.raycast.com/basics/publish-an-extension)
- [Obsidian plugin security](https://obsidian.md/help/plugin-security)
- [Obsidian developer policies](https://docs.obsidian.md/Developer+policies)
- [Security and trust in Visual Studio Marketplace](https://developer.microsoft.com/blog/security-and-trust-in-visual-studio-marketplace/)
- [VS Code extension runtime security](https://code.visualstudio.com/docs/configure/extensions/extension-runtime-security)
- [Chrome Web Store troubleshooting: remote code](https://developer.chrome.com/docs/webstore/troubleshooting)
- [Figma plugins, Tom MacWright](https://macwright.com/2024/03/29/figma-plugins)
- [Zed: developing extensions](https://zed.dev/docs/extensions/developing-extensions)
- [Deno security and permissions](https://docs.deno.com/runtime/fundamentals/security.md)
- [Bun lifecycle scripts](https://bun.com/docs/pm/lifecycle)
- [npm provenance GA](https://blog.sigstore.dev/npm-provenance-ga/)
- [Shai-Hulud npm worm](https://javapro.io/2025/10/02/the-shai-hulud-npm-worm-when-supply-chains-bite-back/)
