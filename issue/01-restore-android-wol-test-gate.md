# 01 — 修正 Android WOL 測試編譯阻擋

**What to build:** 讓 WOL 取消流程的 unit test 在目前 Kotlin/coroutines 設定下能編譯並執行，恢復 Android CI 的綠燈。

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] 取消測試使用結構化 coroutine scope，不再呼叫無 scope 的 launch。
- [ ] 測試仍能證明取消 WOL send 會傳遞 CancellationException，而不是被吞掉。
- [ ] cd android && ./gradlew test 的 Debug 與 Release unit tests 都通過。
- [ ] 不改變 production WOL cancellation semantics。

**Review evidence:** 由 5be21c7 新增的 cancellation test 目前在 compile test source 時失敗；production assembleDebug 可通過。

