# Smarty

HarmonyOS/OpenHarmony WireGuard client skeleton powered by Cloudflare BoringTun.

## What Is Implemented

- Stage-model HarmonyOS app module.
- `VpnExtensionAbility` registered as `type: "vpn"`.
- Editable wg-quick style configuration UI.
- VPN startup through `vpnExtension.startVpnExtensionAbility`.
- UDP socket creation in Rust, then `VpnConnection.protect(socketFd)` before vNIC creation.
- vNIC/TUN creation from `[Interface] Address`, `[Peer] AllowedIPs`, DNS and MTU.
- Rust N-API bridge using `napi-ohos` and BoringTun `noise::Tunn`.
- Worker threads for TUN to UDP, UDP to TUN, and WireGuard timers/keepalive.

## Project Layout

- `entry/src/main/ets/pages/Index.ets`: configuration editor and start/stop buttons.
- `entry/src/main/ets/vpnextension/WgVpnExtensionAbility.ets`: VPN lifecycle.
- `entry/src/main/ets/wireguard/WireGuardConfig.ets`: wg-quick config parsing.
- `native/wg_boringtun`: Rust N-API module backed by `boringtun`.
- `scripts/build_native.sh` / `scripts/build_native.js`: builds and copies `libwg_boringtun.so` to `entry/libs/arm64-v8a`.

## Build

1. Install DevEco Studio / HarmonyOS SDK with Network Kit API 11+ support.
2. Install Rust and configure `ohos-rs`/`ohrs`.
3. Build the arm64 native library. DevEco/Hvigor also runs this automatically before `ProcessLibs`, but this command can be used manually:

```sh
bash scripts/build_native.sh
```

4. Open the project in DevEco Studio, sync dependencies, sign the app, and build/install the `entry` HAP.

If DevEco reports that `extensionAbilities.type = "vpn"` is unknown, follow the OpenHarmony VPN documentation note and add `vpn` to the SDK module checker enum, then clear build cache and restart DevEco Studio.

## Configuration

Paste a standard single-peer WireGuard config:

```ini
[Interface]
PrivateKey = CLIENT_PRIVATE_KEY_BASE64
Address = 10.7.0.2/32
DNS = 1.1.1.1, 8.8.8.8
MTU = 1280

[Peer]
PublicKey = SERVER_PUBLIC_KEY_BASE64
PresharedKey =
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.example.com:51820
PersistentKeepalive = 25
```

If `PersistentKeepalive` is omitted, Smarty uses `25` seconds by default. Set it to `0` to disable persistent keepalive.
`PersistentKeepalive` sends empty encrypted data packets; it does not refresh the latest-handshake timestamp every 25 seconds.

## Notes

- HarmonyOS supplies the VPN vNIC and routes only. WireGuard protocol traffic is handled by this app through BoringTun.
- The UDP socket must be protected before calling `VpnConnection.create`, otherwise WireGuard UDP traffic can loop back into the VPN route.
- This implementation is a focused single-peer client. Multi-peer routing, notifications, key generation, QR import, and live status callbacks can be added on top of the same native bridge.
