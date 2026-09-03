# 03 — 修正 direct-first Wake 流程並禁止 WOL 觸發 pairing

**What to build:** 使用者在 TV 未連線時按下 Wake，先嘗試 remembered Remote v2 direct connection；只有 direct path 失敗、local network 可用且 capability 已 VERIFIED 時才送 WOL，送完只做 pin-verified reconnect。

**Blocked by:** 01 — Restore Android WOL test gate; 02 — Add explicit WOL capability verification; 04 — Bind WOL to the active local network.

**Status:** ready-for-agent

- [ ] Connected 狀態仍只送一次 Remote v2 Power command，不先送 WOL。
- [ ] Disconnected/failed 狀態先嘗試 remembered 6466 direct path；沒有 MAC 時也不能跳過這一步。
- [ ] Direct path 成功後不再送 WOL 或第二次 Power，避免 toggle race。
- [ ] WOL 後的 reconnect 只接受既有 trust tuple；ClientIdentityRejected、TrustChanged 或 pairing-required 結果必須回報失敗，不能進入 pairing、discovery、Forget 或 identity replacement。
- [ ] WOL 失敗、重連失敗或取消時，回到可操作的 Failed/Disconnected 狀態，保留 paired record。
- [ ] Tests 覆蓋 direct success、direct failure then WOL、no MAC、unverified MAC、identity rejection、取消與重連失敗。

**Review evidence:** 6408a68 在沒有 connected session 時直接送 WOL；5be21c7 的 WOL retry loop 仍可能呼叫 pairing。

