# 06 — 完成 WOL 實機驗證並維持未驗證 release gate

**What to build:** 以真實 Google TV 與 Android phone 驗證 direct wake/WOL 的條件邊界；在沒有證據前，產品保持未驗證或 feature-flag 狀態，不把 packet sent 當成 TV 已醒。

**Blocked by:** 02 — Add explicit WOL capability verification; 03 — Enforce direct-first Wake without pairing; 04 — Bind WOL to the active local network; 05 — Harden WOL lifecycle races and cancellation.

**Status:** ready-for-agent

- [ ] 至少一個明確 TV model、firmware、network type 與 Android phone/OS 完成記錄。
- [ ] 同一 model/transport 至少完成三次 cold attempt，分別記錄 direct 6466 結果、WOL 結果與實際螢幕狀態。
- [ ] 覆蓋 short/long standby、Ethernet/Wi-Fi（若有）、reboot、DHCP/IP change、wrong MAC、WOL disabled、guest/VLAN isolation 與 phone VPN/cellular。
- [ ] 只有實際 network MAC 與穩定硬體結果才能標成 VERIFIED；其他狀態維持 best effort/not verified。
- [ ] failure 不會清除 paired record，也不會啟動 pairing 或背景常駐服務。
- [ ] 公開測試輸出不包含 MAC、certificate、pairing code、private key 或其他長期 credential。

**Review evidence:** 兩個 commit 只有 packet/JVM coverage，沒有 direct-first、capability gate、active-network 或真機冷啟動證據。

