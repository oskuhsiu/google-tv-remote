# iOS 鎖定畫面遙控器

日期：2026-10-09。基底：`main` / `6dd1c67b29fdd65ec88409bf8b45de9bb8843611`。

## 本次功能

- 原有 `TV Remote` 小工具增加 `.accessoryRectangular` 與 `.accessoryCircular`，會出現在鎖定畫面的「加入小工具」。桌面小／中／大三種尺寸和既有 kind 均保留。
- 長方形是兩排六鍵：上排左／上／右，下排返回／下／OK。圓形是一個 OK 鍵。使用系統鎖定畫面的單色渲染，不顯示電視名稱。
- 新增 `TV Command` 控制項，可選上、下、左、右、OK、返回、Home，供鎖定畫面底部、控制中心與動作按鈕使用。既有 `Remote` 開啟 App 捷徑不變。
- 直接指令使用 `openAppWhenRun = false`、`authenticationPolicy = .alwaysAllowed`，但一般 accessory widget 仍受 iOS 自身的驗證規則限制。
- 發送前檢查最新的可用狀態；不可用時不排隊。逾時／取消清除尚未消費的指令，佇列有效期與回覆等待時間統一為 1 秒，拒絕過期或未來時間戳記。
- 暫存指令及 acknowledgement 檔案使用 `completeUntilFirstUserAuthentication` 保護，允許開機後解鎖過一次的手機在再次鎖定後讀寫。沒有變更 Keychain、憑證或配對金鑰的存取設定。

## 兩種鎖定畫面入口，不是同一個功能

**時鐘下方的小工具**：可以在仍停留於鎖定畫面的介面操作，但 Apple 的規則仍可要求先通過 Face ID／密碼驗證。`.alwaysAllowed` 不能繞過 accessory widget 的系統驗證要求。

**底部 TV Command 控制項**：這才是本次允許在裝置尚未驗證時直接執行的路徑。指令不要求開啟 App，但實機仍須確認鎖定狀態、系統設定與背景連線均符合條件。若將它加入鎖定畫面，其他拿到手機的人也可能使用所選指令控制已配對的電視。

Apple 參考資料：
- https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities
- https://developer.apple.com/videos/play/wwdc2024/10157/
- https://developer.apple.com/documentation/appintents/intentauthenticationpolicy/alwaysallowed

## 安裝與使用

1. 從此分支重新建置並安裝 iOS App，確認安裝包包含 Widget extension，而且 App 與 extension 保留相同 App Group 的有效簽章／權限。舊的已發布 IPA 不會自動取得本次修改。
2. 開啟 App，與電視完成配對並確認已連線。開啟 **Keep Ready**，再鎖定 iPhone。使用同一個可連到電視的區域網路。
3. 長按鎖定畫面 → 自訂 → 鎖定畫面 → 加入小工具 → **TV Remote** → 選長方形六鍵或圓形 OK。
4. 需要底部直接控制時，在同一編輯畫面移除原本手電筒／相機位置的按鈕，按「＋」加入 **TV Command**，設定要送出的 Command。不要選仍然只會開啟 App 的 **Remote**。
5. 控制中心也能加入多個 **TV Command**，各自設定不同指令；若要在鎖定時取用控制中心，須在 iOS 設定中允許該入口。

## 背景連線邊界

此版本沿用既有 `Keep Ready` 與 App Group → Darwin notification → 主 App 連線的流程，沒有新增第二條電視 TCP/TLS 連線，也不會在 extension 複製配對憑證。

**先開啟 App 並連線、開啟 Keep Ready 是必要條件。** 本次沒有把被強制關閉或被系統停止的 App 變成可任意喚醒的常駐服務。Keep Ready 關閉、NoKeepAlive 組態、背景保活被中斷、手機重啟或電視斷線時，不保證直接遙控；需要回 App 重新連線。既有背景保活仍屬實驗性功能。

不可用的小工具會顯示開啟 App 的入口；直接控制項會回報需要連線／Keep Ready，不自動跳到前景。回覆確認只表示主 App 接受指令，不代表電視已完成動作。按住控制項不等於 App 內的長按連發。

## 驗證紀錄

目前開發環境為 Linux，沒有 Xcode、iOS SDK 或實體 iPhone。因此以下結果**不是完整 iOS 建置或實機通過**：

- 六個修改的 Swift 檔案通過 `swiftc -frontend -parse` 語法檢查。
- 擷取未改寫的正式程式中可攜的狀態、序列化與逾時邏輯，以 Swift 編譯執行，25 項檢查通過。
- 13 項結構回歸檢查通過：保留桌面尺寸、註冊 accessory 尺寸與直接控制項、背景 intent 設定、離線檢查、清理與檔案保護。
- 在既有 `ProtocolAdapterTests.swift` 追加 `LockScreenRemoteTests` 六個 XCTest；原有測試保留，尚未使用 Xcode 執行。未新增 Swift source file，因此 checked-in Xcode project 不需要重新產生。

Mac 建置檢查：

```sh
xcodebuild -project ios/AndroidTVRemote.xcodeproj \
  -scheme AndroidTVRemote \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project ios/AndroidTVRemote.xcodeproj \
  -scheme AndroidTVRemote -showdestinations
```

使用列出的可用模擬器執行 XCTest，並在真機驗收以下情境：

| 情境 | 驗收重點 |
| --- | --- |
| 新安裝／更新 | 鎖定畫面清單可看到 TV Remote 兩種尺寸與 TV Command 控制項；桌面三尺寸不退化。 |
| 已連線＋Keep Ready | 六鍵逐一控制正確，圓形 OK 正確；不因按鍵開啟 App。 |
| 尚未 Face ID 驗證 | 遮住前鏡頭測試底部 TV Command；再分別記錄 accessory widget 的驗證提示，不混為同一結果。 |
| 已驗證但未滑入桌面 | accessory 六鍵可操作，檢查兩排小按鈕的誤觸率及深／淺背景可讀性。 |
| 鎖定超過五分鐘 | 複測控制項與 accessory，確認保活、狀態租約與系統小工具更新沒有造成持續不可用。 |
| 關閉 Keep Ready／強制關閉 App | 不假裝成功，不在稍後開啟 App 時補送舊指令。 |
| Wi-Fi 斷線／電視斷線 | 顯示不可用並可回 App 恢復；不無限制重試。 |
| NoKeepAlive 建置 | 無背景可用性承諾，不出現假連線。 |
| 冷開機後 | 先解鎖及開啟 App 連線，再測試；不能依靠重啟前的狀態。 |
