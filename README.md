# Smarty

Smarty is a HarmonyOS/OpenHarmony WireGuard client with an integrated browser workflow. This repository is no longer just a VPN skeleton. It currently combines:

- WireGuard tunnel management
- Smart Agent rule-based tunnel selection
- App split tunneling
- DNS over HTTPS for tunnel endpoint resolution
- Built-in ArkWeb browser, bookmarks, history, and desktop shortcuts
- A Rust + BoringTun native data plane

The main application module lives in `entry/`, and the native transport implementation lives in `native/wg_boringtun/`.

## Features

### WireGuard / VPN

- Import and store multiple WireGuard tunnel configurations
- Select the active tunnel and start or stop the VPN
- Use `VpnExtensionAbility` for the VPN lifecycle
- Parse single-peer `wg-quick` style configuration fields:
  - `[Interface] PrivateKey`
  - `Address`
  - `DNS`
  - `MTU`
  - `[Peer] PublicKey`
  - `PresharedKey`
  - `AllowedIPs`
  - `Endpoint`
  - `PersistentKeepalive`
- Run the encrypted data plane in Rust with `boringtun`
- Protect the UDP socket before creating the Harmony VPN vNIC to avoid routing the tunnel socket back into the VPN itself

### Smart Agent

- Enable or disable Smart Agent
- Match rules in order and switch to the selected tunnel automatically
- Support the following rule types:
  - `wifiSsid`
  - `wifiGateway`
  - `ipv4Available`
  - `ipv6Available`
- Allow rules to resolve to direct connection instead of VPN

### Split Tunneling / DNS

- App-based split tunneling
- DNS over HTTPS for resolving tunnel endpoints
- Current default DoH provider: `https://dns.alidns.com/dns-query`

### Built-in Browser

- ArkWeb-based browser
- Address bar, back/forward, pull to refresh, and load error retry
- Browsing history
- Bookmark home and bookmark add/delete flows
- Web icon capture for bookmarks and shortcuts, with fallback to a default icon
- Desktop shortcuts via `WebShortcutAbility`
- Basic page state restore, cookie persistence, and PWA metadata detection

## Project Layout

```text
entry/
  src/main/ets/
    entryability/      app entry, web shortcut entry, window helpers
    pages/             ArkTS pages and browser UI
    vpnextension/      VPN extension lifecycle
    wireguard/         config parsing, persistence, strategy, native bridge
  src/main/resources/  resources, localization, shortcut/vpn profiles

native/wg_boringtun/   Rust N-API WireGuard implementation
scripts/               native build helpers
```

Key files:

- `entry/src/main/ets/pages/Index.ets`
  Main control surface for tunnels, Smart Agent, split tunneling, and browser entry points
- `entry/src/main/ets/pages/WebBrowserPage.ets`
  Main built-in browser page
- `entry/src/main/ets/vpnextension/WgVpnExtensionAbility.ets`
  VPN lifecycle and tunnel startup
- `entry/src/main/ets/wireguard/WireGuardConfig.ets`
  `wg-quick` config parsing
- `entry/src/main/ets/wireguard/SmartAgentStrategy.ets`
  Smart Agent rule resolution
- `entry/src/main/ets/wireguard/NativeTunnel.ets`
  ArkTS to Rust native bridge
- `native/wg_boringtun/src/lib.rs`
  BoringTun-based native data plane

## Native Library Build

The Rust build produces:

- `entry/libs/arm64-v8a/libwg_boringtun.so`

Manual build:

```sh
bash scripts/build_native.sh
```

The script will:

1. Find a usable OpenHarmony NDK
2. Run `ohrs build --release --arch aarch`
3. Copy the generated `libwg_boringtun.so` into `entry/libs/arm64-v8a/`

You can also use the Node helper:

```sh
node scripts/build_native.js
```

It includes fallback behavior for:

- Missing `ohrs` in the current environment
- Windows hosts that need to invoke the WSL build
- Reusing an existing `.so` when one is already present

### NDK Requirements

`scripts/build_native.sh` expects `OHOS_NDK_HOME` to point to a valid OpenHarmony SDK root containing at least:

- `native/build/cmake/ohos.toolchain.cmake`
- `native/llvm/bin/clang`

The script also tries a few common locations automatically, including:

- `/sdk/ohos-sdk/6.1-Release/openharmony`
- `/tmp/ohos-sdk/6.1-Release/openharmony`
- `DevEco Studio/sdk/default/openharmony`

If `ohrs` is not installed, install and configure `ohos-rs` first.

## HarmonyOS Build

Build the entry HAP only in an environment that already has the HarmonyOS frontend SDK configured:

```sh
hvigor --no-daemon --mode module -p module=entry assembleHap
```

This repository is commonly edited from WSL, but full frontend/HAP builds should not be run from WSL unless that is explicitly what you want to do.

If Hvigor reports SDK configuration issues, check:

- `/sdk/ohos-sdk`
- `DEVECO_SDK_HOME`
- the SDK mapping in DevEco Studio

## Configuration Example

The app accepts a standard single-peer `wg-quick` style configuration such as:

```ini
[Interface]
PrivateKey = CLIENT_PRIVATE_KEY_BASE64
Address = 10.7.0.2/32
DNS = 1.1.1.1, 8.8.8.8
MTU = 1280

[Peer]
PublicKey = SERVER_PUBLIC_KEY_BASE64
PresharedKey =
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = vpn.example.com:51820
PersistentKeepalive = 25
```

Notes:

- If `PersistentKeepalive` is omitted, the app applies its own default handling
- `AllowedIPs`, `DNS`, and `Address` are used to configure the Harmony VPN vNIC and routes
- This repository implements the client side only

## Abilities and Permissions

The module currently declares:

- `EntryAbility`
- `WebShortcutAbility`
- `WgVpnExtensionAbility` with type `vpn`

The module requests:

- `ohos.permission.INTERNET`
- `ohos.permission.GET_NETWORK_INFO`
- `ohos.permission.KEEP_BACKGROUND_RUNNING`

## Validation

There is no dedicated automated test suite in this repository yet. Validation is currently manual and source-review driven.

Typical checks:

- ArkTS logic changes:
  - source review
  - manual UI verification on affected pages
- WireGuard / VPN changes:
  - config parsing
  - VPN start/stop
  - DNS and route setup
  - socket protection
  - handshake and packet flow
- Browser / bookmark changes:
  - fresh install behavior
  - persisted state behavior
  - icon fallback behavior
  - shortcut creation and restore flows
- Native changes:
  - rerun `bash scripts/build_native.sh`

## Known Limits

- The app is focused on a local device workflow, not multi-device sync
- It depends on HarmonyOS/OpenHarmony VPN, WebView, and shortcut capabilities
- HAP build, signing, installation, and runtime debugging require a complete SDK and device environment
- There is no automated regression suite yet

## Security Notes

Do not commit:

- real WireGuard private keys
- real endpoints or internal addresses
- signing material
- local SDK paths
- machine-specific local settings

Pay particular attention to:

- `local.properties`
- local DevEco Studio settings
- test configuration files with real secrets

## Dependencies

The native data plane depends on:

- [BoringTun](https://github.com/cloudflare/boringtun)
- `napi-ohos`
- `napi-derive-ohos`

See upstream projects for their individual licenses. Add a repository-level license file separately if you intend to publish this project.
