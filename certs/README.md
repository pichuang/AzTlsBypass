# certs/ — 你的企業 CA 憑證放這裡

把你的**企業 TLS 解密 Proxy CA 憑證**(PEM 格式 `.crt` / `.pem`)直接複製到這個資料夾,**安裝腳本(`點兩下安裝-AzTlsBypass.cmd` / `OneClick-Install.ps1` / `Install-AzTlsBypass.ps1`)會自動偵測並設為 `CaCertPath`**,不需要再手動輸入路徑。

## 用法

1. 把企業 CA 憑證檔(例如 `contoso-proxy-ca.crt`)放到 **這個資料夾**。
2. 雙擊執行 `powershell\點兩下安裝-AzTlsBypass.cmd`。
3. 安裝程式看到此處有檔案時會自動帶入,並在提示中顯示偵測到的檔名。

```
certs/
├── README.md             ← 本檔(已加入 git)
├── .gitignore            ← 忽略所有憑證檔(已加入 git)
└── contoso-proxy-ca.crt  ← ★ 你自己放,git 不會追蹤
```

## 支援的格式

| 副檔名 | 內容 | 是否支援 |
|--------|------|---------|
| `.crt` / `.pem` | PEM(`-----BEGIN CERTIFICATE-----` 開頭,純文字) | ✅ |
| `.cer` | 多半是 DER 二進位(Windows 匯出預設) | ⚠️ 需先轉成 PEM,見下方 |
| `.pfx` / `.p12` | PKCS#12 含私鑰 | ❌ 不適用(這裡只需公鑰 CA) |

### `.cer` → `.pem` 一行轉換

PowerShell:

```powershell
$src = '.\contoso-proxy-ca.cer'
$dst = '.\contoso-proxy-ca.crt'
$bytes = [IO.File]::ReadAllBytes($src)
$b64   = [Convert]::ToBase64String($bytes, 'InsertLineBreaks')
"-----BEGIN CERTIFICATE-----`n$b64`n-----END CERTIFICATE-----" |
    Set-Content -LiteralPath $dst -Encoding ascii
```

或用 `certutil`:

```powershell
certutil -encode contoso-proxy-ca.cer contoso-proxy-ca.crt
```

## 多張憑證(中介 + 根)

直接把每張都丟進來,**安裝腳本會把同一資料夾下所有 `.crt` / `.pem` 自動串接成單一 bundle**(`~/.AzTlsBypass/certs/bundle.pem`)並設為 `CaCertPath`。

或你也可以自己手動串接成單一檔案:

```powershell
Get-Content .\root-ca.crt, .\intermediate-ca.crt | Set-Content .\bundle.crt
```

## 從 Windows 信任根匯出企業 CA(沒拿到憑證檔時)

如果你只在 Windows 信任根存放區(`Cert:\LocalMachine\Root`)看得到 CA、手上沒有實際檔案:

```powershell
$ca = Get-ChildItem Cert:\LocalMachine\Root |
      Where-Object Subject -like '*Contoso*Proxy*CA*'
$bytes = $ca[0].Export('Cert')
$b64   = [Convert]::ToBase64String($bytes, 'InsertLineBreaks')
"-----BEGIN CERTIFICATE-----`n$b64`n-----END CERTIFICATE-----" |
    Set-Content -LiteralPath '.\contoso-proxy-ca.crt' -Encoding ascii
```

把產出檔案複製到本資料夾即可。

## 安全與隱私

- **CA 公鑰憑證本身不是機密** — 任何 TLS 用戶端在 handshake 時都能看到。但因每家企業的 CA 名稱可能洩漏組織資訊,**本資料夾的 `.gitignore` 已預設忽略所有 `.crt` / `.pem` / `.cer`**,git 不會追蹤。
- 若你 fork 本專案並要建立公司內部專用版本,可考慮自行調整 `.gitignore` 以便團隊共享 CA。

## 相關設定

- 詳細的 Proxy / CA 行為說明:見根目錄的 [DEVELOPER.md § 設定 Proxy 與 CA 憑證](../DEVELOPER.md#設定-proxy-與-ca-憑證完整版)
- 設定檔最終會落到:`~/.AzTlsBypass/config.json`
