# 05 — 補強 WOL 重連的 lifecycle race 與 cancellation

**What to build:** 讓 Wake 操作在取消、背景切換、Disconnect、Forget 或舊 session 關閉時，都不能留下 spinner、復活已關閉的連線，或覆寫更新後的 controller state。

**Blocked by:** 03 — Enforce direct-first Wake without pairing.

**Status:** ready-for-agent

- [ ] WOL send、等待、direct reconnect、TLS open 任一階段取消，都能留下穩定且可操作的 state。
- [ ] Wake 與 Disconnect/Forget 並行時，舊 Wake 不會重新送 packet、重連或改回 Connecting。
- [ ] stale session 的成功或 onLost callback 不會覆寫新 session 的 state。
- [ ] pairing/trust record 在取消與失敗時維持既有 Disconnect/Forget 語意。
- [ ] 以 controllable fake sender/session 加入 deterministic race tests；若仍需實機才能證明的部分，明確列為 device-test case。

**Review classification:** 這是 review 發現的 runtime risk；WOL send/delay 的取消清理已在 5be21c7 改善，但 connection-attempt cancellation 與並行 teardown 尚未被完整證明。

