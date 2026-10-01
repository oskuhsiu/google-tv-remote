# 02 — 建立明確的 WOL capability 與驗證狀態

**What to build:** 讓 remembered TV 的 network-wake 資料能區分「沒有資料、已有候選但未驗證、已驗證、明確不支援」，只有已驗證的 network MAC 與 WOL/WoWLAN capability 才能進入實際 Wake 流程。

**Blocked by:** 01 — Restore Android WOL test gate.

**Status:** deferred

**Current decision:** 本次最小修正保留 best-effort WOL：有效 MAC 可供正常 Wake 嘗試使用，不新增 VERIFIED 門檻。UI 只表示 MAC 已儲存，並明確說明儲存 MAC 與送出封包不代表喚醒能力或結果已驗證。此決策也適用於 issue 03 的 verified-only 條件；下列完整驗證流程仍是後續工作，不能視為已完成。

**Reason:** VERIFIED 需要可信的實際 TV 喚醒確認流程；單純新增狀態欄位不會提高喚醒成功率。沒有 MAC 時維持點選 remembered TV 卡片直接重連，暫不擴大 Wake 入口。

- [ ] MAC 來源與 capability 狀態被持久化，且 MAC 維持 normalized representation。
- [ ] 手動輸入或 best-effort ARP 候選只會成為未驗證資料；輸入格式正確不等於 WOL 已驗證。
- [ ] 明確的驗證流程才能把 capability 變成 VERIFIED；單純送出 packet 不得把 TV 視為已喚醒或已連線。
- [ ] 沒有 MAC 或未驗證時，正常 remembered-TV direct reconnect 仍可使用，WOL 不會發送。
- [ ] Forget、trust mismatch 或換成另一台 TV 時，不會沿用舊 TV 的 wake MAC/capability。
- [ ] 加入 model/storage/controller/UI 的 deterministic tests，覆蓋 legacy record、未驗證候選與已驗證資料。

**Review evidence:** 6408a68 只保存 nullable MAC，並以 MAC 存在與否顯示 WOL configured；5be21c7 沒有補上 capability gate。
