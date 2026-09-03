# 04 — 將 WOL 發送限制在 active local network

**What to build:** 讓 WOL sender 只透過手機目前可用的 Wi-Fi/Ethernet local network 發送有限次數的 magic packet，避免 VPN、cellular、錯誤介面或非預期網路收到封包。

**Blocked by:** 01 — Restore Android WOL test gate.

**Status:** ready-for-agent

- [ ] Sender 取得並使用 active local Network，且 socket 綁定該 Network/interface。
- [ ] Broadcast address 來自該 local subnet；不對所有 up interfaces 廣播，也不依賴 globally hard-coded limited broadcast。
- [ ] Remembered host 的 unicast fallback 只有在有明確、可驗證的設計理由時保留，否則移除。
- [ ] 沒有 Wi-Fi/Ethernet local path 時，不發送 packet 並快速回報 NETWORK_UNREACHABLE/local network unavailable。
- [ ] packet 次數、DNS/connection 等待與整體操作都有 bounded timeout；partial send 不會被誤報為 TV 已醒。
- [ ] 以 fake Network/broadcast provider 與 deterministic tests 驗證 interface selection、VPN/cellular exclusion、packet count 和 failure mapping。

**Review evidence:** 6408a68/5be21c7 的 sender 會列舉所有介面、加入 255.255.255.255，並使用未綁定的 DatagramSocket。

