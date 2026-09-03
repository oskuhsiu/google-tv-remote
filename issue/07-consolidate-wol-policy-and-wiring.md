# 07 — 收斂 WOL policy、重連 state machine 與 UI wiring

**What to build:** 在 Wake 行為穩定後，收斂重複的 controller retry/connection state machine、WOL action plumbing 與 MAC invariant，降低後續 Android/TV-platform 擴充的維護成本。

**Blocked by:** 03 — Enforce direct-first Wake without pairing; 04 — Bind WOL to the active local network.

**Status:** ready-for-agent

- [ ] Wake/reconnect 的連線、持久化、錯誤映射與 state transition 只有一個可重用 policy path。
- [ ] Device screen 與 Remote screen 共用 WOL actions/dialog 行為，不再重複維護相同流程。
- [ ] MAC normalization/validation 的 invariant 有單一 owner，避免 device record 與 remembered record 分別持有可分歧的 primitive string。
- [ ] Refactor 不改變 direct-first、verified-only、no-pairing、Disconnect/Forget 與 cancellation semantics。
- [ ] 保留並擴充 deterministic tests，且 ./gradlew test 通過。

**Review classification:** 這是低優先度的 under-factoring/design issue，不是已確認的 runtime blocker。

