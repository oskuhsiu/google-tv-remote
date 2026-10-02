# iOS WOL 重建計畫與移除前實作紀錄

> 日期：2026-10-02。用途：在移除 iOS WOL 後，保留足夠資訊供未來重新實作。
> **歷史實作基準：`37851e9`（移除前 HEAD）**；首次加入 WOL 的提交為 `1e187f6`。
> 本文件以該版本的 Swift、測試、plist、entitlements 與 `ios/project.yml` 為證據；不是宣稱移除後仍有此功能，也不是承諾所有 TV 都能被喚醒。

## 1. 目標、範圍與真實完成狀態

要重建的第一階段是主 app 裡的 **MAC 手動設定與前景 Test Wake**，不是自動喚醒流程。使用者先以正常 Google TV 流程建立完整配對，開啟 Network Wake，輸入 TV 目前使用的 Wi-Fi／Ethernet MAC 並儲存，再把 TV 用實體遙控器切到待機，按 Test Wake。App 嘗試從目前本地 IPv4 介面發送 UDP magic packet，回報本機傳送結果。

| 項目 | `37851e9` 已實作 | 不可推論／尚未實作 |
|---|---|---|
| MAC | 手動輸入、驗證、正規化、儲存、編輯、清除 | 自動 IP→MAC、ARP、router/vendor API |
| 傳送 | 本地介面 subnet-directed broadcast、UDP port 9 | 單播、全域 broadcast fallback、IPv6 WOL、遠端網際網路喚醒 |
| 觸發 | 主 app 的手動 Test Wake，啟動時檢查 sceneIsActive | cold launch／foreground reconnect／Power／Widget 自動 WOL |
| 結果 | 本機 socket 接受完整 datagram；顯示明確限制 | TV 已收到、TV 已醒、authenticated reconnect 成功 |
| capability | 儲存 `unverified`／`verified`／`unsupported`；UI 顯示狀態 | Test Wake 自動 promotion、使用者確認支援／不支援的操作 |
| 測試 | 存在 18 個 deterministic XCTest，sender 用替身 | socket 實際 broadcast、實機 entitlement、真 TV 喚醒證明 |

`plan/google-tv-power-wake-plan.md` 的「Remote v2 先嘗試，失敗且 MAC/能力已驗證才 WOL，接著 reconnect」是產品方向。它不是此版本的程式行為，必須另立後續設計／實機 gate。`plan/research-data/lan-wake-feasibility.md` 是可行性研究，也不能當作硬體驗收紀錄。

`ARCHITECTURE.md` 與 `plan/done/ios.md`／`plan/done/ios/control-center-compact-remote.md` 部分舊 checkpoint 說 discovery/pairing 仍是 placeholder；本基準的 production composition 已注入 `BonjourDiscoveryService()` 與 `AndroidTVRemoteAdapter`，故重建要依當時及未來實際 source，不照舊 checkpoint 回退功能。

## 2. 平台與產品邊界

- 一次只記住一台 TV、一個 active remote session；WOL metadata 附在這台 TV 的 record，不建立第二個 controller 或 session。
- 有 valid trust record 時，冷啟動與 foreground resume 仍直接連 remembered TV；保留 Cancel、bounded retry、TLS pinning 及既有 IP recovery。
- **Disconnect 留配對與 MAC；Forget 移除記憶 record（連帶 MAC）與 identity。** 清除 MAC 不刪 Keychain、不 Forget、不 disconnect。
- 普通 Power 維持 authenticated Remote v2 key command。WOL 是獨立 UDP datagram，不是 port 6466/6467 的 TCP/TLS/protobuf 訊息。
- Widget／Control Center 不 discover、不 pair、不發 WOL。Widget command 只走主 app 既有 authenticated session；Control Center 開 compact in-app remote。
- Keep Ready 是既有實驗性背景 silent audio；WOL 不藉此在背景傳送，不增加 Background Mode。保留 `NoKeepAlive` configuration。
- 只用 TV **目前網路介面的 MAC**：Wi-Fi 用 Wi-Fi MAC，網路線用 Ethernet MAC；不可把 Remote v2 certificate 裡看似 MAC 的值視為網路 MAC（可能是 Bluetooth），不可由一個 MAC 猜另一個。
- TV 拔電、真正關掉網卡、未啟用 network standby/WoWLAN、guest Wi-Fi/AP isolation、跨 VLAN 等都可能不支援；「格式有效」也不表示 MAC 屬於這台 TV。
- 不記錄 pairing code、private key、certificate 內容、long-term credential、token 或 TV text；實機診斷以非秘密錯誤碼／測試 fixture 與明確同意的 packet capture 為限。

## 3. 檔案與 symbol 對照

以下所有路徑相對 repo root，內容均可由 `git show 37851e9:<path>` 取回。

| 舊檔案 | 需要還原／整合的責任與 symbol |
|---|---|
| `ios/AndroidTVRemote/NetworkWakeSettings.swift` | `NetworkWakeSettings`，`Source.manual`，`Capability`，failable init、自訂 decode |
| `ios/AndroidTVRemote/WolPacket.swift` | `WolPacket.normalizedMAC(_:)`、`make(macAddress:)`、private `macBytes(_:)` |
| `ios/AndroidTVRemote/WolSender.swift` | `WolSending`、`WolSendError`、`LocalNetworkWolSender.send(macAddress:)`、private `ActiveWolInterface.resolve()`、`WolPathRequest.start/finish`、`sendDatagram` |
| `ios/AndroidTVRemote/RemoteContract.swift` | `LastTvRecord.networkWake`、init default、CodingKeys、tolerant optional decode；保留 `hasSameTrust`／`isComplete` |
| `ios/AndroidTVRemote/LastTvStore.swift` | 既有 JSONEncoder/Decoder UserDefaults record；沒有獨立 WOL key／store |
| `ios/AndroidTVRemote/RememberedTvResolver.swift` | `LastTvRecord.replacingHost(_:connectedAt:)` 建新 record 時傳遞 `networkWake` |
| `ios/AndroidTVRemote/AppModel.swift` | sender injection、published feedback/busy、save/clear/persist/test/cancel、lifecycle cancellation、pairing completion merge、retry 使用最新 record |
| `ios/AndroidTVRemote/AndroidTVRemoteAdapter.swift` | `handleFirstRemote` 建 `LastTvRecord` 時沿用 `pairingExpectedRecord?.networkWake` |
| `ios/AndroidTVRemote/UI/NetworkWakeSettingsView.swift` | `NetworkWakeSettingsView`、`NetworkWakeGuideView`、private `wakeCard()`；整個設定 sheet |
| `ios/AndroidTVRemote/UI/RootView.swift` | `showsNetworkWake`、sheet、`openNetworkWake()`、trust／route 改變時 dismiss、向 caller 傳 closure |
| `ios/AndroidTVRemote/UI/DeviceView.swift` | remembered TV 下的入口、`openNetworkWake` closure |
| `ios/AndroidTVRemote/UI/RemoteView.swift` | connected/reconnecting full remote 的入口、`openNetworkWake` closure |
| `ios/AndroidTVRemote/AndroidTVRemoteApp.swift` | production 透過 AppModel default sender；DEBUG WOL preview flags、preview fake sender、accessibility3 |
| `ios/AndroidTVRemote/DebugCompactPreview.swift` | fake `WolSender`，所有 preview composition 都注入，避免意外真實 UDP |
| `ios/AndroidTVRemote/Resources/Localizable.xcstrings` | WOL 專屬英文 key 與 `zh-Hant` 翻譯；保留其他字串 |
| `ios/AndroidTVRemoteTests/NetworkWakeTests.swift` | packet/storage/model 三個 test class、fixture、recording/suspended sender、retry gate |
| `ios/project.yml` | 主 app multicast entitlement、Local Network 文案、source folder inclusion；專案來源真相 |
| `ios/AndroidTVRemote/AndroidTVRemote.entitlements` | multicast=true；既有 App Group 不變 |
| `ios/AndroidTVRemote/Info.plist`、`Info-NoKeepAlive.plist` | Local Network usage 文案；既有 Bonjour type、portrait、URL scheme、NoKeepAlive 差異保留 |
| `ios/AndroidTVRemote.xcodeproj/project.pbxproj` | XcodeGen 產物，重新 generate，不把歷史手改當 canonical |

`1e187f6` 同時修改 Android MAC guide、大型 Widget、widget preview、版本等。`37851e9` 又含之後的 certificate identity／配對修復工作。重建 WOL **不等於** cherry-pick 整個提交或覆蓋全部 AppModel/adapter/widget 檔案；只抽取本表需要的 slice，適配當前 backend／trust／UI 邊界。

## 4. 資料 schema、相容性與儲存政策

`NetworkWakeSettings: Codable, Equatable, Sendable` 的三個 immutable 欄位：

```json
{
  "networkWake": {
    "macAddress": "A4:77:33:12:AB:CD",
    "source": "manual",
    "capability": "unverified"
  }
}
```

此物件是 `LastTvRecord` 的可選子欄位；例子只是 schema fragment，不是完整 pairing record。`Source` 只有 `manual`；`Capability` 的 raw strings 為 `unverified`、`verified`、`unsupported`。`init?(macAddress:capability:)` 預設 `.unverified`，驗證失敗回 nil，source 一律 `.manual`。

Decoder 必須重新驗證／正規化 MAC，並以 strict enum decode 處理 source/capability；未知 enum、不合法 MAC、missing required member 都讓 **wake 子物件** decode 失敗。但 `LastTvRecord` 用下面的 tolerant decode 隔離錯誤：

```swift
networkWake = try? values.decode(NetworkWakeSettings.self, forKey: .networkWake)
```

因此舊 record 沒有欄位、null、欄位型別錯誤、future enum 或損壞 wake 值都只得到 nil，不使原有 valid pairing tuple 失效、不刪 identity、不觸發重新配對。其他必要 trust 欄位仍要按原有嚴格政策 decode／驗證，不能把整個 record 改成寬鬆接受。

- `LastTvRecord` init 新增 default `networkWake: NetworkWakeSettings? = nil`；不要求改每個既有 caller。
- MAC 不參與 `isComplete`；完整性仍由 identity/name/host/trust tuple 決定。MAC 也不參與 `hasSameTrust`。
- `hasSameTrust` 比對 persistentDeviceID、clientIdentityFingerprint、pairingPeerFingerprint、remotePeerFingerprint；不比 host/name/wake metadata。
- 儲存仍是 `LastTvStore`，UserDefaults `.standard` 的 key `lastTvRecord`，value 為 `JSONEncoder` 產生的 Data；不加 schema version、不複製 credential、不使用 App Group 分享 MAC。
- save/clear 先建立 modified copy，`store.save` 成功後才更新 published rememberedRecord；encode／store error 保留舊 in-memory record，顯示 storage feedback。UserDefaults `set` 本身不提供磁碟落盤成功保證。
- 每次「儲存 MAC」（即使 MAC 一樣）都重新建 `.unverified` settings，不保留前一 capability；這是舊行為，若未来要保留必須另外決策。
- decode 正規化不代表立刻寫回磁碟；下次真正 save 才會重新 encode。
- 移除版 `1.0.3 (4)` 的模型已不含 `networkWake`：JSONDecoder 載入舊 record 時忽略該 key，下一次 record save 的 JSONEncoder 不再寫出它；trust／host／name／source／date 保留。這不等於啟動時就強制清理舊 JSON。
- 未來 re-enable 需同時測：移除 WOL 前的 record、有 WOL 的 record、移除版寫回後已無 WOL 的 record。已被移除版重新儲存而丟掉的 MAC 不能靠重建自動找回，必須手動輸入。移除版另有 LastTvStoreTests 覆蓋舊 wake 值忽略／read-save 丟欄位與 replacingHost 保留 trust/metadata；重建時需更新這些預期，使兩版本 migration 行為保持清楚。

## 5. MAC 驗證與 magic packet

`WolPacket.macBytes` 的規則按順序為：

1. 只 trim 字串首尾的 whitespace/newline；不忽略中間空白。
2. 接受 `A4:77:33:12:AB:CD`、`A4-77-33-12-AB-CD`、`a4773312abcd`。
3. 若含 `:` 或 `-`，含冒號時選冒號，否則選連字號；split 保留空片段，必須恰好六組、每組 UTF-8 長度 2。混用分隔符因此不能通過。
4. 合併後必須恰好 12 個 ASCII hex 字元 `[0-9A-Fa-f]`；拒絕全形字元、其他 Unicode、短組、尾部分隔符及非 hex。
5. 解成六個 UInt8；拒絕全零與 first octet 的 I/G bit 為 1 (`bytes[0] & 1 != 0`) 的 multicast/group address。`FF:FF:FF:FF:FF:FF` 也因此拒絕。
6. 接受 locally administered **unicast**，例如 `02:11:22:33:44:55`；不能把 U/L bit 當錯誤。
7. `normalizedMAC` 輸出大寫、六組兩位 hex、冒號分隔。

`make` 重做相同驗證，避免 caller 繞過，產出 **102 bytes**：

```text
offset   0..5   FF FF FF FF FF FF
         6..11  A4 77 33 12 AB CD  (第 1 次)
         ...
        96..101 A4 77 33 12 AB CD  (第 16 次)
```

沒有 protobuf framing、TLS、checksum 欄位、SecureOn password、padding 或 prefix length；UDP/IP header 由系統生成。

## 6. Sender：路徑選擇、socket 演算法與失敗語意

### 6.1 可注入 seam

```swift
protocol WolSending: Sendable {
    // 成功僅代表本機 socket 接受封包，不代表 TV 已醒。
    func send(macAddress: String) async throws
}

enum WolSendError: Error, Equatable {
    case invalidMAC
    case localNetworkUnavailable
    case sendFailed
}
```

`AppModel` 的 initializer 預設 `wolSender: WolSending = LocalNetworkWolSender()`；正式 `AndroidTVRemoteApp` 不必另傳 sender，也不引入額外 singleton。tests/previews 必須顯式 fake injection。Sender 的 nonisolated async 實作在 UI actor 外執行同步 bounded socket calls，不應在 MainActor 上跑 socket 工作。

### 6.2 一次性 default-path snapshot

`ActiveWolInterface.resolve()` 建 `WolPathRequest`，用 `withCheckedThrowingContinuation` 等待 `NWPathMonitor` 首次結果，另有 task cancellation handler。`WolPathRequest` 用 NSLock 保護 continuation/result，專用 dispatch queue `dev.local.AndroidTVRemote.wol-path`，3 秒 timeout。

接受條件：

```text
path.status == satisfied
AND 不 usesInterfaceType(other)
AND 不 usesInterfaceType(cellular)
AND availableInterfaces.first 是 wifi 或 wiredEthernet
AND path.usesInterfaceType(first.type)
```

取該 first interface 的 name 與 UInt32(index)，**不跳過偏好介面去找其他 Wi-Fi**；沒有合適 default-path、cellular、tunnel/other、first interface 不符即 `.localNetworkUnavailable`。這是 fail-closed 選路政策，不是完整辨識所有 VPN／route 的保證；即使 Wi-Fi 可用，條件不符仍拒絕。

`finish` 在 lock 中只保存第一個 result，移走 continuation，解鎖後 cancel monitor、resume 一次；timeout／path callback／task cancellation 競爭不能重複 resume。若 cancellation 比 `start` 先到，`start` 讀取預存結果直接 resume。3 秒內無 acceptable observation 也回 `.localNetworkUnavailable`。

### 6.3 getifaddrs 與 subnet broadcast

先生成 packet，invalid input 回 `.invalidMAC`；resolve 後 `Task.checkCancellation()`，再讀 `getifaddrs`，結束必 `freeifaddrs`。只枚舉上一步選出的**同名 interface**，條件為：

- flags 同時包含 `IFF_UP | IFF_RUNNING | IFF_BROADCAST`。
- flags 不含 `IFF_LOOPBACK | IFF_POINTOPOINT`。
- `ifa_addr` 是 `AF_INET`，且存在 netmask。
- IPv4 local != 0；netmask != 0、!= UInt32.max（不接受 /0／/32）；算出的 broadcast != UInt32.max（不送 `255.255.255.255`）。

計算使用 sockaddr 中的 network-byte-order 欄位做同位元操作：

```swift
let broadcast = local.sin_addr.s_addr | ~mask.sin_addr.s_addr
```

例：`192.168.50.23/24` → `192.168.50.255`。不硬編碼 Wi-Fi 名 `en0`、網段、mask 或 global broadcast，不拿 remembered TV 的 lastHost 來假設手機路由，也不做 IP→MAC 查詢。舊實作只檢查以上 mask 值，不額外驗證 mask bits 是否連續。

每個合格 IPv4 entry 設 foundTarget，先 check cancellation，呼叫一次 sendDatagram；同名介面若有多個 IPv4 位址，可能送多個 datagram。**不是全介面掃送／重試 burst。** 任一 entry 完整成功即整體 sent=true；後面的取消仍可讓整體回 CancellationError，已送出的 UDP 無法回收。

### 6.4 每個 datagram 的 Darwin socket 步驟

1. `socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)`，失敗回 false；`defer close(descriptor)`。
2. `fcntl(F_GETFL)`／`fcntl(F_SETFL, flags | O_NONBLOCK)`；任一步失敗回 false。沒有等待可寫、blocking retry 或長期 socket。
3. `setsockopt(SOL_SOCKET, SO_BROADCAST, enabled=1)`。
4. `setsockopt(IPPROTO_IP, IP_BOUND_IF, selected interface index)`，固定出口。
5. 用原 local `sockaddr_in`，把 source port 設 0，`Darwin.bind` 固定 source IP，由系統挑 ephemeral UDP port。
6. destination `sin_len=sizeof(sockaddr_in)`、`sin_family=AF_INET`、`sin_port=UInt16(9).bigEndian`、`sin_addr=broadcast`。
7. `sendto(..., flags=0)`；只有回傳 byte count **等於 102** 才 true。

沒有 eligible entry／getifaddrs 失敗 → `.localNetworkUnavailable`；有 target 但所有 socket/fcntl/options/bind/sendto 失敗或非完整 length → `.sendFailed`。舊 API 不保留 errno、不細分「無 entitlement」「Local Network denied」「EAGAIN」「bind address disappeared」，所以 UI 不能斷言唯一原因。不要把 sendto 成功寫成 TV acknowledgment。

### 6.5 已知限制與競態

- NWPath 與 getifaddrs 是兩次 snapshot；介面切換、DHCP、更換網路、VPN 建立／撤除可能發生在兩者之間或 bind/sendto 時。綁 index 與 source IP 可限制誤送出口，但不能消除競態或保證 broadcast 到達 TV。
- WOL 接收靠 L2/network standby 支援；手機同 Wi-Fi 字面上不保證 TV 可收到（AP client isolation／VLAN 等）。Sender 未驗證 TV 與手機在同 subnet。
- IPv6-only 或無合格 IPv4 broadcast interface 會拒絕；不以 fallback 繞過。
- cancellation 是 cooperative：socket 中沒有可撤銷已傳出的 datagram；UI 取消意味不再接受舊完成回報，不能保證零封包已送。
- first-interface policy 是舊碼採用的 route 判斷方式；未來若調整，需另加可測的 path/interface selection seam 和實機多網路案例，不宣稱舊 tests 已涵蓋它。

## 7. AppModel 狀態、取消與 trust merge

### 7.1 獨立於 RemoteState

新增 `@Published private(set)` 的 `networkWakeMessage: String?`、`isTestingNetworkWake=false`；private sender、`networkWakeTask: Task<Void,Never>?`、`networkWakeGeneration=0`。WOL 不另加 RemoteState，不改 connecting/connected/disconnected/reconnecting 狀態。

`canConnectRemembered` 本身為「有 rememberedRecord 且未 securityStoreBlocked」；record 完整性與 Keychain fingerprint 已由 restore 流程驗證，不是 MAC 狀態。

save/clear 只要求 `canConnectRemembered` 與有 record，**方法本身未要求 sceneIsActive**；UI 在主 app sheet 呼叫。invalid input 回 false 且顯示錯誤，保留 record；舊碼在 validation 成功後才 cancel test。clear 設 nil，不動 trust。store 成功才更新 published state。

### 7.2 Test Wake 流程與過期完成抑制

`testNetworkWake()` 的 gate：sceneIsActive、canConnectRemembered、未忙碌、有 record、有 settings；不檢查 `.connected`，所以可在 TV 離線／AppModel `.disconnected` 時使用。不存在 saved MAC 回 nil、不送封包。

```text
按 Test Wake
  -> 清除前一次 feedback，busy=true，generation += 1
  -> capture record + settings + generation
  -> await sender.send(settings.macAddress)
  -> 成功／錯誤轉成 message
  -> 未取消 AND generation 相同 AND current.hasSameTrust(captured)
     AND current.networkWake == captured settings
  -> 才 publish feedback，清 busy/task
```

Task capture weak self 與 sender；defer 也只在 generation 相同時清 busy/task，避免舊 task 清掉新 task 狀態。CancellationError 直接返回不發新錯誤；其餘 messages 用 NSLocalizedString（見第 9 節）。沒有 reconnect、pairing、送 Power、修改 capability。

`cancelNetworkWakeTest()` 先 generation += 1，再 task.cancel、task=nil、busy=false；**不清 feedback**。save/clear 成功會換自己的 feedback；Forget 另外清 feedback。

已接入取消點：有效 save、clear、`enterBackground()`、`forget()`、settings sheet `.onDisappear`。RootView 因 route/trust change dismiss sheet 也會經 onDisappear 取消。

精確限制：`enterInactive()` 在基準只停止 voice，沒有 cancel WOL、沒有把 sceneIsActive 設 false；`disconnect()` 也不 cancel WOL。因此「前景限定」是 test 啟動 gate 加 background cancellation，不是保證 permission sheet／其他短暫 inactive 期間一律停止。Disconnect 時仍允許已手動啟動的 packet test 完成，符合其與 remote session 分離；未來若要改這些語意需獨立決策和測試。

### 7.3 保存當前編輯，避免 stale session record 覆蓋

Adapter `handleFirstRemote` 初次 authenticated remote 成功建 record 時帶 `pairingExpectedRecord?.networkWake`；這只是 session snapshot。AppModel 接 `.pairingCompleted(incomingRecord)` 再做最新值 merge：

```swift
var record = incomingRecord
if let current = rememberedRecord,
   current.persistentDeviceID == record.persistentDeviceID,
   current.pairingPeerFingerprint == record.pairingPeerFingerprint,
   current.remotePeerFingerprint == record.remotePeerFingerprint {
    record.networkWake = current.networkWake // nil 也必須覆蓋，保留剛剛 Clear
}
try session.commitPairing { try store.save(record) }
```

此 merge **故意不要求 clientIdentityFingerprint 相同**：同一可信 TV 的 client certificate 修復可能更新 client fingerprint，仍保留 latest MAC。不同 TV／peer pin 不可繼承當前 MAC。它與「test completion 需 `hasSameTrust`（含 client fingerprint）」是兩個不同 gate；不能誤合併。

另外：

- `LastTvRecord.replacingHost` 複製 networkWake，避免 DHCP／manual IP／named resolution 丟 metadata。
- `scheduleReconnect` capture 舊 trust，但等待 delay 完成後重新讀 rememberedRecord，檢查同 trust，再 `session.connect(to: currentRecord)`；不能連 stale record，否則重連開始前的 MAC 編輯可能被覆蓋。
- pairing commit/store 失敗沿用既有 rollback／previous pairing policy；不得因 WOL 重写憑證流程。
- RootView 用 `hasSameTrust` 決定 sheet 是否可保留；host/name/MAC 更改不 dismiss，client fingerprint 變更或 Forget／其他 TV 則 dismiss。

## 8. UI、MAC guide、accessibility 與 previews

### 8.1 入口與導航

`DeviceView` 在 remembered TV 的 Last used card 後顯示 Network Wake；`RemoteView` 在 full remote header 後顯示；兩者至少 44pt 高、SF Symbol `wifi`、canConnectRemembered 為 false 時 disabled。無記憶 TV不顯示 Device 入口，compact remote 沒有獨立 WOL 入口。

RootView 的 `openNetworkWake()` 再 gate canConnectRemembered，sheet 共享同一 AppModel；route 切 compact 即 dismiss。把 RootView 的 Dynamic Type environment 顯式傳入 sheet；不要建立第二個 AppModel 或重新配對。

### 8.2 設定頁結構與操作

NavigationStack + vertical ScrollView，dark-first semantic colors、blue tint，內容 max width 420、外 padding 20、card padding 16/cornerRadius 18。

依序呈現 TV name／圖示／說明、MAC card、capability status、可展開 guide、TV standby 提醒、Test Wake、feedback、已儲存時的 destructive Clear MAC address。Toolbar Done 關閉；Save 按下才驗證並存。

MAC field 是 monospaced、ASCII capable keyboard、characters capitalization、autocorrection disabled、Done submit 取消 focus。右側 clear-input icon 的 hit region 至少 44×44；這只清編輯文字，**不刪 saved MAC**。改字即隱藏 validation error，Save 空白或 busy disabled；格式錯誤顯示 inline error，成功把 field 換成 canonical saved MAC。

`canTest` 除 canConnectRemembered 與有 saved settings 外，還要 `WolPacket.normalizedMAC(fieldText) == saved.macAddress`；未儲存的新 MAC 不能送，等價的小寫／dash 形式可送已存 MAC。busy 顯示 ProgressView 並禁重複 Test／Save。Test 點擊、Save、guide 展開時收鍵盤；ScrollView 支援 interactive keyboard dismiss。sheet appear 載 saved MAC；disappear cancel test。

status 對應 `verified`／`unsupported`／`unverified`／nil 文字；**沒有 UI 可以把 status 寫成 verified 或 unsupported**。有 capability 欄位不是完整 capability 驗證流程。

### 8.3 VoiceOver 與 UI automation anchors

| ID／label | 元件 |
|---|---|
| `network-wake-settings` | Device/full remote 入口 |
| `network-wake-mac`；label `MAC address` | MAC field |
| label `Clear input` | field 的 x icon |
| `network-wake-mac-error` | 格式錯誤 |
| `network-wake-guide` | DisclosureGroup |
| `network-wake-test` | Test Wake |
| `network-wake-feedback` | 非秘密結果文案 |
| `network-wake-clear` | 清除 saved MAC |
| `network-wake-save` | Save |

保留標準 Button／TextField／DisclosureGroup semantics、可讀文字狀態，不只靠顏色；大字體要可捲動、不裁切、不縮小 44pt targets。舊碼沒有專屬 UI test 或完整 VoiceOver驗收證據，未來需人工與 automation 檢查。

### 8.4 MAC guide 內容

三步：「在 TV 開 Settings 或 Help」→「找 About／Status／Network status」→「把 MAC 輸入上方」。明講 Wi-Fi 用 Wi-Fi MAC，Ethernet 用 Ethernet MAC。歷史 UI 的選單範例：

- Google TV Streamer／Chromecast：Settings → System → About → Status。
- TCL：Settings → Network & Internet → current network。
- Sony：Help → Status & Diagnostics → Network status。

這些是「menus vary by model」的導引例子，不是所有 firmware 路徑已逐台驗證。恢復時若改為 model-specific 精確指示，應重新查證。

### 8.5 DEBUG preview 防止實際副作用

`AndroidTVRemoteApp` 支援 `--wol-preview`、`--wol-accessibility-preview`，使用 `DebugCompactPreview.record/Session/Identity/Store`，初始 route fullRemote，再由入口開 sheet；不是自動直接顯示 sheet。accessibility flag 注入 `.dynamicTypeSize = .accessibility3`，RootView 繼續傳給 sheet。

所有 debug fixture 路徑（含 compact/widget preview）顯式注入 `DebugCompactPreview.WolSender`；它只驗證 packet 可生成、check cancellation，**完全不送 UDP**。record 是 documentation IP `192.0.2.10` 與 fake fingerprint，沒有預設 MAC；先在 UI 輸入再測。不可把 fake sender 的 success 當網路或 TV 證明。

## 9. Localization 與精確 feedback contract

主 app `Resources/Localizable.xcstrings` 的 sourceLanguage 為 `en`，WOL keys 有 `zh-Hant`。SwiftUI Text/Label 使用 localized key；AppModel 的 String feedback 明確 `NSLocalizedString`。不要只刪／重建整份 catalog，必須保留其它功能與使用者的翻譯變更；placeholder MAC 不需翻譯。

| English source key | zh-Hant（歷史值） |
|---|---|
| Network Wake | 網路喚醒 |
| MAC address | MAC 位址 |
| Test Wake | 測試喚醒 |
| How to find the MAC address | 如何找到 MAC 位址 |
| Wake support previously confirmed | 先前已確認支援喚醒 |
| Wake support marked as unavailable | 已標記為不支援喚醒 |
| Wake support not confirmed | 尚未確認支援喚醒 |
| No MAC address saved | 尚未儲存 MAC 位址 |
| Save the MAC address before testing. | 請先儲存 MAC 位址，再進行測試。 |
| Clear MAC address | 清除 MAC 位址 |
| Enter a valid device MAC address, such as A4:77:33:12:AB:CD. | 請輸入有效的裝置 MAC 位址，例如 A4:77:33:12:AB:CD。 |
| MAC saved. Wake support is unverified. | 已儲存 MAC 位址。尚未驗證喚醒支援。 |
| MAC address cleared. | 已清除 MAC 位址。 |
| Could not save the MAC address. Try again. | 無法儲存 MAC 位址，請再試一次。 |
| Wake packet sent. This does not confirm that the TV woke. | 已送出喚醒封包。這不代表電視已喚醒。 |
| Connect your iPhone to the same local Wi-Fi or Ethernet network as the TV. VPN and cellular connections cannot send this test. | 請將 iPhone 連接至與電視相同的本地 Wi-Fi 或乙太網路。此測試無法透過 VPN 或行動網路傳送。 |
| Could not send the wake packet. Check Local Network permission and your Wi-Fi connection, then try again. | 無法送出喚醒封包。請確認「區域網路」權限與 Wi-Fi 連線，再試一次。 |

其他 UI keys 需由歷史 catalog 精確取回：MAC connection 說明、standby/network standby/remote start 提醒、三步 guide、Wi-Fi/Ethernet 選擇、menus vary、三個品牌路徑。基準 UI 的 `Test waking your TV from standby over the local network.` 譯為「測試透過區域網路喚醒待機中的電視。」；`First put the TV in standby with its physical remote. Keep your iPhone on the same local network.` 譯為「請先用電視遙控器讓電視進入待機。iPhone 須連接同一區域網路。」；通用 Done／Save／Clear input 已有「完成」／「儲存」／「清除輸入」。恢復後仍須檢查實際顯示與 fallback，不能只憑 catalog 存在宣稱 UI 完整驗收。

錯誤對應：CancellationError 不新增 feedback；`.localNetworkUnavailable` 用同 LAN／VPN／cellular 提醒；`.invalidMAC`（正常 UI 不應發生）、`.sendFailed` 或其他 error 都使用 generic permission/Wi-Fi message。storage save failure 用獨立文案。success 文案不可刪除「不代表 TV 已醒」。

## 10. Apple 權限、簽章與 XcodeGen

### 10.1 實機 broadcast 需要獲批 entitlement

實體 iPhone／iPad 上 UDP broadcast/multicast 需要 Apple 核准的 `com.apple.developer.networking.multicast`；此要求包含 development／非 App Store 簽署，不能用「只本機測試」繞過。把 `<key>...multicast</key><true/>` 加入檔案不會自行賦予資格；需 entitlement approval、App ID capability 與 matching provisioning profile。[Apple Local Network privacy announcement](https://developer.apple.com/news/?id=0oi77447)、[multicast entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast)

Simulator 可在沒有 active multicast entitlement 時開發／測試，故 simulator 成功不能驗證實機簽章、permission 或 UDP broadcast 可用。[Apple multicast networking 說明](https://developer.apple.com/news/?id=0oi77447)

Xcode 15+ 支援在 Automatic Signing 中使用已核准的 managed capability；不能一概聲稱此 entitlement 必須 Manual Signing。恢復時確認 developer account 的 approved capability、target App ID、profile 及實際 signed app 都含權限，必要時更新 profile。[Provisioning with managed capabilities](https://developer.apple.com/help/account/reference/provisioning-with-managed-capabilities/)

### 10.2 Local Network privacy 是另外一層

Local Network 授權與 multicast entitlement 分開：entitlement 是 broadcast 能力，使用者允許 Local Network 也不能取代它。保留主 app `NSLocalNetworkUsageDescription` 與正常 remote discovery 的 `NSBonjourServices = ["_androidtvremote2._tcp"]`；declared specific Bonjour discovery 本身與額外 raw UDP broadcast 的要求不同。[Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

歷史 usage 文案為 `Find, connect to, and send network wake packets to your TV on the local network.`，同時在 `Info.plist` 與 `Info-NoKeepAlive.plist`。permission denied 不可聲稱 manual IP 可以繞過。若 WOL 被移除，仍需保留正常 remote 的 Local Network/Bonjour 設定。

### 10.3 Canonical configuration

先改 `ios/project.yml`，主 app：

```yaml
entitlements:
  path: AndroidTVRemote/AndroidTVRemote.entitlements
  properties:
    com.apple.security.application-groups:
      - group.dev.local.AndroidTVRemote
    com.apple.developer.networking.multicast: true
```

Widget extension 只有原 App Group；不加 multicast，因它不送 packet。不要更改 App Group、bundle ID、team、版本或 widget 大小來「順便」恢復 WOL。歷史 app 為 iOS 18、iPhone target family 1、portrait、Automatic Signing；iPad 並非此 app 的既有支持範圍，平台 entitlement 對 iPad 的要求不等於產品已支持 iPad。

`NoKeepAlive` 沿用自己的 Info-NoKeepAlive.plist、無 audio background mode；有無 Keep Ready 均需主 app 的 multicast 權限（若恢復 WOL）。一般 app audio mode 不應被 WOL 流程使用。sources 原本包含整個 `AndroidTVRemote` 與 tests folder，不需手動逐檔加 `.pbxproj`。

執行 `cd ios && xcodegen generate`，檢查生成 entitlements／Info plist／project diff；舊 generated scheme 已可能有使用者修改，不可全覆蓋不相關設定。未來版本號依當次發版決定，不把歷史 `1.0.2 (3)` 回寫蓋掉移除版 `1.0.3 (4)`。

## 11. 歷史測試清單與未驗證部分

以下是 `NetworkWakeTests.swift` **存在的測試**，本文件整理時未重跑，不能把列表當作此次或未來執行結果。

| class | test function | assertion 目的 |
|---|---|---|
| WolPacketTests | testNormalizesColonDashAndPlainHex | 三種輸入轉 canonical |
| WolPacketTests | testRejectsMalformedAndUnusableAddresses | malformed、all-zero、broadcast、multicast 拒絕；local unicast 接受 |
| WolPacketTests | testExactMagicPacketContainsSixFFBytesAndSixteenMACCopies | 精確 102 bytes、prefix、16 copies |
| NetworkWakeStorageTests | testLegacyRecordWithoutWakeFieldRetainsPairing | legacy record 配對保留 |
| NetworkWakeStorageTests | testMalformedOptionalWakeMetadataDoesNotDiscardPairing | malformed/unknown enums 只丟 wake 子欄位 |
| NetworkWakeStorageTests | testWakeMetadataRoundTripsThroughRealStore | 隔離 UserDefaults suite round trip、manual/unverified |
| NetworkWakeStorageTests | testDecodedWakeMACIsNormalized | decoding canonicalization |
| NetworkWakeModelTests | testSaveEditClearRetainsTrustAndPersists | trust／identity 不變，save/edit/clear 持久化 |
| NetworkWakeModelTests | testInvalidInputAndStorageFailurePreservePriorSettings | invalid／failSave 不覆蓋舊值 |
| NetworkWakeModelTests | testPacketTestDoesNotReconnectPairOrVerifyCapability | 手動 test 不改 session/state/capability |
| NetworkWakeModelTests | testForegroundDirectConnectNeverSendsCandidateOrVerifiedWake | unverified/verified 均不觸發自動 WOL |
| NetworkWakeModelTests | testSendFailureRetainsCandidateAndSessionState | send fail 保留 metadata/state |
| NetworkWakeModelTests | testNoSavedMACCannotSend | 沒 MAC 無 side effect |
| NetworkWakeModelTests | testEditedMACSuppressesOldTestCompletion | suspended sender 舊 completion 不蓋新 feedback |
| NetworkWakeModelTests | testSameTrustedTVSessionCompletionPreservesLatestEditAndClear | stale session result 不復活剛清除的 MAC |
| NetworkWakeModelTests | testClientCertificateRepairKeepsLatestMACAndTrustedTVMetadata | client fingerprint 更新保留同可信 TV 的最新值 |
| NetworkWakeModelTests | testDifferentTrustedTVDoesNotInheritWakeSettings | 不同 TV 不繼承 MAC |
| NetworkWakeModelTests | testEditingMACDuringScheduledReconnectUsesLatestRecord | delay 後用 currentRecord |

模型 fixture 是 `WakeModelFixture`，用 memory store、fake identity、recording session；`RecordingWolSender` 記錄 MAC／可拋 `.sendFailed`，`SuspendedWolSender` 人為延後 completion，`WakeRetryGate` 控制 retry delay。storage round-trip 使用真 LastTvStore 配隔離 UserDefaults suite 並清理。

沒有針對 `NWPathMonitor/getifaddrs/IP_BOUND_IF/sendto` 的實際 packet test；沒有上述 route 多網路政策的獨立 deterministic 測試；沒有實機 privacy deny／Apple managed capability／TV standby wake 成功結果。可新增有價值的 regression：background／Forget／sheet dismiss cancellation、不同 trust 在 test 期間更換、timeout/cancel continuation 單次 resume、localNetworkUnavailable feedback、duplicate test gate；這些是未來工作，不冒稱舊 coverage。

## 12. 可執行的重建步驟

### A. 確認來源與當前架構

1. 先讀當前 `ARCHITECTURE.md`／AGENTS 與 owning plan，檢查 working tree。確認未來是否已有 backend seam／versioned TV record；若已不同，保留同樣 policy，適配 source，不硬塞舊 Google-specific record。
2. 以只讀指令取 historical source 到臨時目錄，逐檔 review。例如：

   ```bash
   mkdir -p /private/tmp/ios-wol-restore-reference
   git show 37851e9:ios/AndroidTVRemote/WolSender.swift > /private/tmp/ios-wol-restore-reference/WolSender.swift
   git show 37851e9:ios/AndroidTVRemoteTests/NetworkWakeTests.swift > /private/tmp/ios-wol-restore-reference/NetworkWakeTests.swift
   git show --stat 1e187f6
   ```

   對其他表列 path 重複 `git show 37851e9:path`；不用 `git checkout 37851e9 -- ios/`，不盲目 cherry-pick `1e187f6`，不回退 widget／identity／版本或目前使用者修改。
3. 此時決定只恢復手動 Test Wake；自動 fallback 不在本輪。先查 Apple account multicast approval，無批准時可先完成 code／simulator，但實機 broadcast gate 必須記為未完成。

### B. 先恢復純資料與 deterministic 行為

4. 加回 WolPacket／NetworkWakeSettings／三種 sender error 與 protocol。對照第 4–5 節，先讓 packet/schema tests pass。
5. 把 optional settings 接入當前 remembered record；preserve strict trust decode，唯 wake 子物件 tolerant。找所有 record constructors/copy/replacingHost，避免 field 遺失；加／復原 store tests。
6. 在 backend/coordinator 的 authenticated record update 路徑補 latest-wake merge：只同可信 TV 保留；client cert repair 可保留；不同 peer 不繼承。delay retry 用 currentRecord，完成 targeted tests。

### C. 恢復 sender 與 state policy

7. 復原 one-shot monitor、3 秒 timeout、once continuation/cancellation、eligible IPv4/interface/broadcast filtering 與 nonblocking bound UDP/9；若重構可測 seam，保持 old public error contract，避免未經批准的 network fallback。
8. AppModel 加 default production sender 與 fake injection seam；save/clear 先持久化、test gate、generation/trust/settings 檢查、background/Forget/sheet cancel。保留 Disconnect、inactive 的基準語意或明確另立決策，不暗中改 remote lifecycle。
9. 執行 model tests，另補最有價值的取消／失效 regression；確認 foreground/retry/Power/widget 完全不調 sender。

### D. UI／localization／configuration

10. 接入入口與 sheet，保持單 AppModel、max width、touch targets、Dynamic Type、MAC editing gating、成功限制文案與 guide；只復原 WOL catalog slice。
11. 加 fake-only DEBUG preview flags，所有使用 fixture 的 preview 一律注入 fake sender，檢查 large Dynamic Type、英文與繁中、VoiceOver。
12. 更新 project.yml 的 app entitlement／Local Network 文案與 NoKeepAlive plist；核對 App ID/profile，XcodeGen regenerate，確認沒有把 entitlement 加到 extension、沒有背景 WOL、無 unrelated version/widget/identity diff。

### E. Build、實機與真 TV gate

13. 在當前可用 Xcode runtime 先用 `xcodebuild -list`／`xcrun simctl list devices available` 選 destination，不假設歷史 simulator 名稱存在。範例（自行替換 SIMULATOR_UDID）：

   ```bash
   cd ios
   xcodegen generate
   xcodebuild -project AndroidTVRemote.xcodeproj -scheme AndroidTVRemote -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' test
   xcodebuild -project AndroidTVRemote.xcodeproj -scheme AndroidTVRemote-NoKeepAlive -configuration NoKeepAlive -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
   ```

   無簽章 generic device build 只驗 compile，不驗真機 entitlement。正常 scheme／NoKeepAlive 都需檢查，所有 tests 結果與執行環境寫入當次紀錄。
14. 獲批准 provisioning 後裝到真 iPhone：核對 signed entitlements/profile、Local Network allow/deny，測 Wi-Fi／可用 wired Ethernet／cellular／VPN／IPv6-only，以及切網路／取消。不支持的 path 要 promptly bounded fail，不改 pairing或 remote state。
15. 以受控 LAN 的 packet capture 驗 102-byte payload、正確 subnet destination、UDP/9、source interface，明確區分「本機接受」「實際出線」「TV 已醒」三層證據。不要把 capture 成功視為 TV hardware gate。
16. 真 TV 做短待機、長待機、Wi-Fi／Ethernet（若支持）、錯 MAC、WOL/network standby 關閉、TV reboot、DHCP 更換。記型號、firmware/Google TV 版本、連線介面、standby 時長、network standby 設定、Remote v2 是否仍可達及 wake 結果；證明 TV 醒後正常 authenticated remote仍可用。
17. Review 最終 diff：普通 Power、pairing pin gate、certificate repair、Disconnect/Forget、named-IP recovery、widgets、compact remote、Keep Ready／NoKeepAlive 均無意外回退。只聲稱已有證據的完成層級。

## 13. 驗收條件與後續自動 WOL 設計

恢復第一階段的必要驗收：

- 有效配對不因 optional WOL metadata 缺失／損壞失效；no-MAC 仍完整可用普通 remote。
- MAC canonicalization 與 102-byte packet 精確；locally administered unicast 接受，group/all-zero/malformed 拒絕。
- save/edit/clear 成功才更新 record；失敗保留舊值；client cert repair／DHCP 更新不丟 latest MAC，其他 TV不繼承。
- Test Wake 僅明確手動開始，busy 不重入；不要 pairing/reconnect/Power 或改 verified；取消後 stale completion 不回寫。
- 無適合的 LAN path／IPv4 broadcast 及 socket error 正確 fail；不以 cellular/VPN/global broadcast/全介面掃送繞過。
- 主 app multicast 實機 provisioning 與 Local Network permission 分別驗證；兩種 build configuration 與 widget extension 設定正確。
- dark/大字體/英文/繁中/VoiceOver 可讀可操作；未保存編輯不能發不同 MAC；所有 preview 無真 UDP。
- packet/socket/TV wake 報告分層，真 TV 尚未通過時只標示「實作與 simulator checks 已完成，hardware wake 未驗證」，不宣稱 reliable wake。

若後續要實作原產品 plan 的 automatic fallback，另先定義：Power 是 toggle 還是 wake-only、direct Remote v2 attempt 的失敗分類／timeout、如何由真硬體測試或使用者確認建立 verified（包含網路介面／TV 設定／firmware／待機時長）、何時失效、單次/bounded WOL／reconnect/cancel 狀態，以及 trust changed 絕不自動解 pin 或配對。成功 sendto 不能產生 verified。應有 hardware evidence 的 capability gate，不把當前 `verified` enum 的存在視為上述設計已完成。

## 14. 本次移除版本與驗證紀錄

2026-10-02 的移除版為 iOS **1.0.3，build 4**，主 app 與 Widget extension 共用此版本。移除 WOL packet/sender/settings、AppModel 操作與取消狀態、MAC metadata 與更新合併、設定入口與 sheet、WOL DEBUG previews、32 個 WOL 專屬 localization entries 與主 app multicast entitlement；README 同步改為 Android 提供 WOL。Android 程式未修改。

| 檢查 | 實際結果與證據範圍 |
|---|---|
| XcodeGen | 已從 project.yml 重新生成；保留既有使用者 scheme 與非 WOL 翻譯修改 |
| XCTest | Xcode 26.5／iOS 26.5 iPhone 17 Simulator，ad-hoc 簽名後 **49/49 通過**：AppModel 25、IdentityRepair 9、LastTvStore 4、ProtocolAdapter 11 |
| 新 migration tests | 舊 record 缺 source/date、合法／損壞／future／null wake metadata、read-save 丟棄舊 wake key、host 更新保留 trust/name/source/locator/date 全部通過 |
| NoKeepAlive／Release | 兩種 generic iOS device configuration 均 `BUILD SUCCEEDED`；使用 CODE_SIGNING_ALLOWED=NO，僅驗證 compile／產物，不代表真機 provisioning 成功 |
| 產物 | 兩種 configuration 的 app／Widget 均 1.0.3 (4)；Bonjour、正常 Local Network 說明、portrait、App Group 保留；NoKeepAlive 無 audio background mode |
| Simulator UI | 正常簽名後 Device 頁與 compact fixture 已觀察，沒有 WOL 入口；compact 的 D-pad／OK／Back／Full Remote／Keep Ready 保留 |
| 未覆蓋 | Full Remote 的實際點擊受 simulator input tooling 限制，僅完成 source review／編譯；未做真 iPhone provisioning、TV pairing、remote command acceptance 或 wake packet 實測 |

第一輪未簽名 Simulator 測試有七個 Keychain identity 案例因 `-34018` 失敗；改用 CODE_SIGNING_ALLOWED=YES、CODE_SIGN_IDENTITY=- 後全套通過。這是本次測試環境的修正，不是為通過測試而改 production identity logic。第 11 節的 18 個 WOL 歷史測試已隨功能刪除，與上述移除版 49 個測試不能混為同一份 coverage。
