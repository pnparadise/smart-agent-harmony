# Repository Guidelines

## Project Structure & Module Organization

This is a HarmonyOS/OpenHarmony WireGuard client. The main app module is `entry/`.
ArkTS UI and app logic live under `entry/src/main/ets`: `pages/` contains screens and browser UI, `wireguard/` contains config parsing and persistence, `vpnextension/` contains the VPN lifecycle, and `entryability/` contains ability startup code. Native WireGuard transport code lives in `native/wg_boringtun/` and builds the `libwg_boringtun.so` library copied into `entry/src/main/libs/arm64-v8a/`. App resources are in `entry/src/main/resources`, with media in `base/media` and localized strings in `en_US` and `zh_CN`.

## Build, Test, and Development Commands

The development environment is WSL, with the HarmonyOS SDK available at `/sdk/ohos-sdk`. Do not attempt ArkTS/HAP frontend builds from WSL unless the user explicitly asks for that exact command.

- `bash scripts/build_native.sh`: builds the Rust N-API library for arm64 and copies it into the entry module.
- `node scripts/build_native.js`: helper used by the Harmony build to run the native build, including WSL fallback handling.
- `hvigor --no-daemon --mode module -p module=entry assembleHap`: builds the entry HAP only in an environment with the HarmonyOS frontend SDK configured.

DevEco Studio or another SDK-equipped environment is required for signing, installing, and debugging the app. If Hvigor reports SDK configuration errors in WSL, verify `/sdk/ohos-sdk` and `DEVECO_SDK_HOME` before changing project files.

## Coding Style & Naming Conventions

Use the existing ArkTS style: two-space indentation, explicit types on function parameters and returns, `PascalCase` for components/classes/interfaces, and `camelCase` for functions, fields, and local variables. Keep UI code in `pages/`, storage and parsing helpers in `wireguard/`, and ability-specific code in `entryability/` or `vpnextension/`. Prefer small helper functions over duplicating URL, shortcut, or config parsing logic.

ArkTS limited throw rule: do not write `throw err` or rethrow arbitrary caught values. Convert caught values to `BusinessError` or a message and throw `new Error(...)` or another explicitly allowed error type.

ArkTS type strictness rules:

- Do not use inline object literal shapes as return types, parameter types, or local type declarations. Declare an explicit `interface` or `class` first, then reference that named type.
- Do not return or assign untyped object literals when ArkTS expects a declared structured type. Give the target variable or return value an explicit interface/class type such as `const result: XxxResult = { ... }`.
- For parsed JSON, prefer a dedicated `interface` like `XxxRaw` plus a normalized typed result like `XxxResult` instead of `Record<string, Object>` and anonymous object structures.

## Testing Guidelines

There is no dedicated automated test suite in this repository yet. In WSL, validate with source review and native-library rebuilds where relevant; HAP validation requires the `/sdk/ohos-sdk` setup or another HarmonyOS SDK-equipped environment. For VPN changes, verify wg-quick parsing, tunnel start/stop, DNS/routes, and socket protection. For browser/bookmark changes, test fresh install and persisted-state flows.

## Commit & Pull Request Guidelines

History uses concise messages such as `feat: add smart agent rules` and short Chinese summaries like `优化逻辑`. Use a short imperative subject, optionally with a conventional prefix (`feat:`, `fix:`). Do not run `git commit` or `git push` unless the user explicitly asks for that exact action. PRs should describe the behavior change, list manual validation steps, link issues when available, and include screenshots or screen recordings for UI changes.

## Security & Configuration Tips

Do not commit real WireGuard private keys, endpoints, signing files, SDK paths, or generated local IDE settings. Treat `local.properties`, SDK configuration, and device-specific signing material as local-only.

## Agent-Specific Instructions

Do not run `hvigor`, `ohrs`, or full HAP builds from WSL unless explicitly requested. Use `/sdk/ohos-sdk` when a requested HarmonyOS SDK command needs `DEVECO_SDK_HOME`. `bash scripts/build_native.sh` is allowed when native library verification or rebuild is needed. Do not run `git commit` or `git push` unless the user explicitly asks for that exact action.
