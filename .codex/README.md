# Project Notes

- This workspace is accessed from WSL, but HarmonyOS builds are performed by the user on Windows/DevEco Studio.
- Do not run build or compile commands from WSL unless the user explicitly asks for it. That includes `hvigor`, `ohrs`, `bash scripts/build_native.sh`, and full HAP/native builds.
- ArkTS limited throw: do not write `throw err` or rethrow arbitrary caught values. Convert caught values to `BusinessError`/message and throw `new Error(...)` or another explicitly allowed error type.
