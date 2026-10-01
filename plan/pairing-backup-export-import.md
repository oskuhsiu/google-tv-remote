# Google TV 配對資料匯出與匯入計畫

狀態：延期，尚未提供 App 功能。2026-10-01 使用者要求先完成 Android 與 iOS 的 CN 修正和升版；本次試作的備份、匯入、匯出與相關 UI 撤回，保留此計畫供後續實作。

目標是把同一組已配對身分完整搬到另一支手機，避免目的地重新產生憑證而失去 TV 信任。備份須包含私鑰、原始憑證、TV 信任資料與服務定位資訊。IP 只是可選的連線提示，不是 TV 身分，也不應決定配對資料是否有效。

## 已知問題與證據

| 項目 | 目前已知 | 對未來實作的影響 |
| --- | --- | --- |
| Android 舊私鑰 | 原生 `AndroidKeyStore` RSA 私鑰不可匯出。 | 不能只匯出公開憑證就宣稱能搬移配對；需要可匯出私鑰的新身分，並重新配對一次。 |
| iOS 舊私鑰 | `IdentityStore` 建立 RSA key 時指定 `kSecAttrIsExtractable=false`。Apple 對這個屬性的限制有平台差異，目前尚未完成實機提取測試。 | 先以獨立測試 namespace 驗證 `SecKeyCopyExternalRepresentation`，不能直接假定所有舊 iOS 身分都能或都不能匯出。 |
| RSA 格式 | Apple RSA 外部表示使用 PKCS#1；Android `PrivateKey.encoded` 通常是 PKCS#8。 | 跨平台檔案統一使用 PKCS#8 DER，iOS 須明確轉換與驗證。 |
| client name 與 CN | `f60ac61` 已唯一化配對請求／裝置資訊的 client name，但修正前 Android 憑證 CN 是 `TV Remote`，iOS 是 `Android TV Remote`。 | 兩個欄位不能混為一談。新身分 CN 與 client name 要一致且唯一；匯入必須保留來源的原值，不能依目的地重新命名。 |
| TV 拒絕手機憑證 | 現場確認原 TV pin 相符，但遙控握手收到 `SSLV3_ALERT_CERTIFICATE_UNKNOWN`。尚未證實是 CN 撞名、另一支手機覆寫配對，或其他 TV 端原因。 | 備份不能修復本來已失去 TV 信任的憑證。須從仍可工作的配對匯出，或先重新配對建立有效身分。 |
| 延後到達的 TLS 拒絕 | Android 的拒絕訊號可能在 TLS connect 之後、第一次 remote read 才到達；iOS 也要檢查底層錯誤分類與實際 pairing manager 啟動。 | 僅在原 TV pin 已驗證時進入重新配對，其他 TLS／網路錯誤與 pin mismatch 維持原分類。 |
| IP 與 Bonjour | 現場保存的 IP 已失效；舊 record 的 service type 含前導點 `._androidtvremote2._tcp`。 | 舊 locator 要正規化；保存精確 service instance 並做指定解析，不因 IP 失效刪除信任，不 broad scan。服務改名仍需明確的手動恢復流程。 |
| 現有 validator | Android `TrustTupleValidator` 與 iOS `LastTvRecord.isComplete` 原本要求非空 last host。 | 必須分開「信任完整」與「目前有可用位址」。缺 IP 但有服務 locator 的備份仍可使用；兩者都缺時保留配對並要求手動位址。 |
| 儲存與 crash | 私鑰／憑證和 metadata 目前位於不同原生 stores。依序覆寫後若 crash，tuple mismatch 可能觸發既有清除機制。 | 匯入要先完整驗證、暫存、讀回，再原子切換有效 generation，不能先刪掉原有可用配對。 |

本次 CN 修正處理可捕捉的儲存失敗並回復原憑證／metadata，但原生雙 store 仍不是 process-crash 原子交易；尤其 Android 26 的 certificate-chain replacement 和 iOS 的 certificate delete/add 可能被終止打斷。這個限制要與未來 generation／activation journal 一起解決，不能把 runtime rollback 測試通過當作 crash recovery 已完成。

Android 的不可匯出限制來自 [Android Keystore 文件](https://developer.android.com/privacy-and-security/keystore)。Apple 的格式與提取行為依 [SecKeyCopyExternalRepresentation 文件](https://developer.apple.com/documentation/security/seckeycopyexternalrepresentation(_:_:)) 驗證。外部同名 client 覆寫舊配對的案例及修正見 [Unfolded Circle issue 39](https://github.com/unfoldedcircle/integration-androidtv/issues/39) 與 [PR 36](https://github.com/unfoldedcircle/integration-androidtv/pull/36)；這些案例不能直接證明本次 TV 的拒絕原因。

## 功能邊界

- Android 與 iOS 原生實作共用檔案規格與測試向量，不增加跨平台 runtime。
- 每個 App 仍只記住一台 TV、維持一個 active session。
- 備份搬移同一個私鑰、同一張憑證、原 client name 與原 TV pins；不重新產生或修改匯入身分。
- 匯出只透過使用者選擇的檔案位置，檔案一定加密；不自動上傳、同步或傳送。
- Widget、Control Center、浮窗不提供匯入、匯出或 pairing；主 App 負責操作。
- 不搬移 overlay 權限、Keep Ready 設定、背景 session 或其他手機專屬偏好。保留 iOS `NoKeepAlive`。
- 不更換既有有效配對的私鑰或憑證。舊 Android 身分要變成可備份身分時，必須有明確的重新配對操作，失敗或取消仍保留原配對。

## 檔案規格草案

副檔名 `.gtrbackup`，UTF-8 JSON envelope：

```json
{
  "format": "google-tv-remote-backup",
  "version": 1,
  "kdf": "PBKDF2-HMAC-SHA256",
  "iterations": 600000,
  "salt": "Base64 16 bytes",
  "nonce": "Base64 12 bytes",
  "ciphertext": "Base64 ciphertext followed by 16 byte GCM tag"
}
```

使用 PBKDF2-HMAC-SHA256 衍生 256-bit key，AES-256-GCM 加密完整 payload。密碼依原樣 UTF-8 編碼，不 trim、不正規化。AAD 固定為 `google-tv-remote-backup|1|PBKDF2-HMAC-SHA256|600000`。salt 與 nonce 每次由安全亂數產生。版本 1 僅接受指定 KDF 和 iteration 數，在計算前拒絕未知版本及過大檔案；檔案上限草案為 128 KiB。600,000 iterations 參考 [OWASP PBKDF2 建議](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)，正式實作仍須量測低階手機耗時。

加密 payload 包含：

| 區域 | 欄位 |
| --- | --- |
| client | PKCS#8 RSA private key DER、原 X.509 certificate DER、certificate SHA-256 fingerprint、原 client name |
| TV identity | persistent TV ID、顯示名稱、pairing peer fingerprint、remote peer fingerprint |
| locator | 可選 `{domain, service_type, instance}`；Google TV 為 `local.`／`_androidtvremote2._tcp`，instance 保留原字串 |
| connection hints | 可選網路 MAC、可選 IP／host hint、最後成功連線的 Unix milliseconds |

wire fingerprints 統一為 64 字元小寫十六進位；native adapter 轉成平台現有表示。TV ID 必須等於 remote pin。實際 MAC 必須是 Wi-Fi／Ethernet 網路 MAC，不能從 TV 憑證中的 Bluetooth MAC 推測。

## 原生儲存與安全切換

Android 新可攜式身分可用軟體 RSA key，PKCS#8 material 在 App 內以 Android Keystore AES-GCM wrapping key 加密。iOS 可攜式身分使用允許提取的 RSA key，仍受 device-only Keychain 保護。這是未來備份功能的儲存選擇，不是本次 CN 修正要更換的 backend。

推薦把完整身分與 TV record 存成一個 authoritative generation：Android 使用單一加密 SharedPreferences blob，iOS 使用單一 device-only Keychain value。舊 generation／legacy stores 在新資料驗證和 activation 成功前維持可恢復。一般 metadata 更新只更新同一 generation，不能弄丟原私鑰。

匯入順序：

1. 讀取有大小上限的檔案，驗證 envelope／版本／KDF／欄位長度。
2. 驗證 GCM authentication tag，再解析 payload。
3. 解析 RSA 私鑰與憑證，要求至少 RSA-2048，驗證 self-signature、私鑰與 public key 的 sign／verify challenge，以及重算的 certificate fingerprint。
4. 驗證 TV pins、ID 與 locator，建立暫存 generation 並讀回確認。
5. 使用者確定匯入後，取消 pending connection，關閉目前 session，原子切換新的完整配對。
6. 顯示匯入結果；連線仍使用原 pin。錯誤密碼、損壞資料、錯配 key／certificate 或不完整 pins 都不能改動原配對，也不能中斷原有正常 session。

原生雙 store 若無法達到真正原子切換，必須設計可重播的 activation journal 或明確回復方案，不能以順序覆寫代替。

## 後續實作工作

1. **身分與相容性探查**：確認 iOS 舊 RSA key 提取能力；確認兩平台原生 key manager 能使用匯入的同一組 material。保留目前硬體／Keychain身分載入。
2. **固定格式與 codec**：完成上述 envelope、payload、PKCS#1／PKCS#8 轉換與 native validation。以獨立 OpenSSL／Node 或其他主流實作產生非 ASCII 密碼向量。
3. **儲存交易**：建立 generation stage／readback／activate／rollback；wrong password、cancel、crash 都保留原配對。Forget 清除所有 owned generations 和原身分。
4. **可備份重新配對**：明確說明舊 Android 私鑰不可搬移；使用者啟動後才產生新可攜式 key。以原 TV pins 完成 pairing 和 authenticated remote handshake 才 activation。
5. **App UI**：主 App 的配對設定提供匯出／匯入；匯出密碼確認，匯入資料預覽與替換範圍；密碼不進 saved state、log 或剪貼簿。錯誤只顯示安全分類。
6. **跨平台與硬體驗證**：Android → iOS、iOS → Android 的檔案互用，確認 fingerprint／CN／client name／原 private key 完全不變，並實測重連與 TV 接受指令。

涉及位置：Android `security/IdentityStore.kt`、`storage/LastTvStore.kt`、`protocol/TlsClient.kt`、controller／ViewModel／配對設定 UI；iOS `IdentityStore.swift`、`LastTvStore.swift`、`AndroidTVRemoteAdapter.swift`、`AppModel.swift` 與配對設定 UI。Xcode project 仍以 `ios/project.yml` 為準。

## 驗收條件與尚未證實事項

- 加密 roundtrip、每次 salt／nonce 不重複、Unicode 密碼、wrong password、tampering、未知版本／KDF、過大輸入皆有 deterministic tests。
- 私鑰／憑證不符、fingerprint 不符、TV ID／pin 不符、locator 異常、MAC 異常均不會啟用。
- 匯入和 metadata 更新的失敗／取消／中斷，不會覆蓋上一組完整配對。
- 沒有 IP 的合法配對不被清除；有 locator 可指定解析，沒有任何位址提示可要求手動 IP。
- 原私鑰和原憑證從匯出到匯入保持完全相同；不同平台不因建立 SecIdentity 或 KeyManager 重新簽發憑證。
- 新身分 CN 唯一且在重啟、重連與備份還原後保持不變；故意共享同一身分的兩支手機不重新命名。
- 不 log 私鑰、憑證內容、密碼、配對碼、長期 credentials 或 TV 輸入文字。
- 實測兩支手機使用不同 CN 配對，再各自重連；另測同一組匯入身分的雙手機同時操作。TV 的實際同時 session 限制依型號驗證，不因單一外部案例作通用承諾。
- 本次現場 `CERTIFICATE_UNKNOWN` 的真正 TV 端原因仍待驗證；CN 修正與能進入 pairing，不等於已證明根因或完成 authenticated 重連。

本次已撤回匯出／匯入試作；不把試作單元測試通過視為此功能完成，也不把生成的合成測試 key 當作真實 TV 配對證據。
