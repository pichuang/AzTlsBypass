# AzTlsBypass

> 在 TLS 中介 Proxy 後讓 `az login` 與 Azure CLI 透明可用 — 為 PowerShell 5.1 / 7+ 而生。

Azure CLI(自 [#26021](https://github.com/Azure/azure-cli/pull/26021) 起)在 `az login` 路徑硬編碼了 `verify=True`,使得在企業 TLS 解密 Proxy 後執行 `az login` 必定觸發 `SSLCertVerificationError`。本專案以**雙軌**方式繞過這個限制:

| 軌道 | 目標族群 | 安裝方式 | 使用體驗 |
|------|----------|----------|----------|
| **L1 — `AzTlsBypass` PowerShell 模組** | 個人 / 工作站 | `Install-AzTlsBypass.ps1` | `az login` 直接可用,**對使用者完全透明** |
| **L2 — `az tls-bypass` 擴充套件** | 團隊 / CI(規劃中) | `az extension add` | `az tls-bypass login` 顯式呼叫 |

> ⚠️ **安全提醒**:啟用本工具會關閉整個 Python 程序的 TLS 憑證驗證,**只應在受信任的企業 TLS 解密 Proxy 後使用**。詳見下方「[設定 Proxy 與 CA 憑證](#設定-proxy-與-ca-憑證)」一節。

---

## 為什麼需要它

| 你已嘗試 | 為何不管用 |
|----------|-----------|
| `$env:REQUESTS_CA_BUNDLE = "...crt"` | `az login` 仍走 MSAL 強制 `verify=True` 路徑 |
| `az config set core.disable_connection_verification=true` | 同上,啟動最初的登入連線不被覆寫 |
| 安裝企業 CA 到 Windows 信任根 | Python `requests` 預設用 `certifi` bundle,**不讀** Windows 根憑證 |

`AzTlsBypass` 透過 `PYTHONPATH` 注入一個 `sitecustomize.py` shim,在 Python 直譯器啟動時(早於任何 `azure.cli` 程式碼載入)就 monkey-patch `requests.sessions.Session`,把 `verify=False` 強制套用到整個程序。

---

## 快速開始(PowerShell 模組)

### 選項 0 — 從 PowerShell Gallery 安裝(預計,尚未上架)

> 待 `AzTlsBypass` 0.1.0 正式發布到 [PowerShell Gallery](https://www.powershellgallery.com/) 後,即可直接:
>
> ```powershell
> # PowerShell 5.1 或 7+ 皆可
> Install-Module -Name AzTlsBypass -Scope CurrentUser
> Import-Module AzTlsBypass
> Set-AzTlsBypassConfig -ProxyUrl 'http://proxy.example.com:8080'
> Enable-AzTlsBypass -Persist
> ```
>
> 若是首次安裝可能需要先信任 PSGallery:`Set-PSRepository -Name PSGallery -InstallationPolicy Trusted`。

### 選項 A — 一鍵安裝(Windows 雙擊,推薦給終端使用者)

從本 repo 取得 `powershell/` 資料夾後,直接雙擊:

```text
powershell\點兩下安裝-AzTlsBypass.cmd
```

此腳本會:

1. 在 PowerShell 視窗依序詢問**企業 Proxy URL**(可直接 Enter 跳過)與**選用的 CA bundle 路徑**。
2. 自動把模組複製到 `Documents\WindowsPowerShell\Modules\AzTlsBypass`。
3. 自動呼叫 `Set-AzTlsBypassConfig` 寫入設定。
4. 自動執行 `Enable-AzTlsBypass -Persist`,把自動啟用區塊寫入 `$PROFILE.CurrentUserAllHosts`。
5. 開新的子 PowerShell 程序執行 `Get-AzTlsBypassStatus` 驗證後 `pause`。

完成後**任何新開的 PowerShell 視窗**直接 `az login` 即可,無須 `Import-Module`、無須 `Enable-AzTlsBypass`。

解除時同樣雙擊:

```text
powershell\點兩下移除-AzTlsBypass.cmd
```

> 兩個 `.cmd` 會自動偵測並優先使用 `pwsh.exe`(PowerShell 7+),不存在時回退到 `powershell.exe`(5.1),並以 `-ExecutionPolicy Bypass` 啟動,因此**不需要事先變更執行原則**。

### 選項 B — 手動安裝(進階 / CI / 跨平台)

#### 1. 安裝(從本 repo)

```powershell
git clone https://github.com/<your-org>/tls-bypass.git
cd tls-bypass\powershell
.\Install-AzTlsBypass.ps1                # 安裝到 $env:PSModulePath (CurrentUser)
```

#### 2. 設定企業 Proxy 與選用 CA

```powershell
Import-Module AzTlsBypass

Set-AzTlsBypassConfig `
    -ProxyUrl 'http://proxy.example.com:8080' `
    -NoProxy  @('*.contoso.com')         # IMDS 端點會自動加入,無須列出
    # -CaCertPath 'C:\corp\ca.crt'       # 可選;詳見下方「設定 Proxy 與 CA 憑證」
```

> 完整 Proxy / CA 憑證設定方法(含「能否用本機 Windows 憑證存放區」)請見下方專章:[設定 Proxy 與 CA 憑證](#設定-proxy-與-ca-憑證)。

#### 3. 啟用 — 兩種模式擇一

```powershell
# 當前 session(臨時):
Enable-AzTlsBypass
az login --identity                      # 透明可用,使用者完全無感

# 寫入 $PROFILE.CurrentUserAllHosts(永久,所有新 session 自動啟用):
Enable-AzTlsBypass -Persist
```

> 若想用單一指令完成「安裝 + 設定 + 永久啟用」三步,可加 `-AutoEnable`:
>
> ```powershell
> .\Install-AzTlsBypass.ps1 -AutoEnable -ProxyUrl 'http://proxy.example.com:8080' -Force
> ```

#### 4. 解除

```powershell
Disable-AzTlsBypass                      # 當前 session 停用
Disable-AzTlsBypass -Persist             # 從 $PROFILE 移除自動啟用區塊
```

#### 5. 移除

```powershell
.\Uninstall-AzTlsBypass.ps1              # 從模組路徑刪除
```

---

## 設定 Proxy 與 CA 憑證

本節是「**進到企業環境前必讀**」的完整指南。`AzTlsBypass` 把所有設定都收斂到一個 JSON 檔(`~/.AzTlsBypass/config.json`),由 `Set-AzTlsBypassConfig` 寫入、`Enable-AzTlsBypass` 啟用時讀取轉成環境變數。

### 三個可調欄位

| 欄位 | 對應參數 | 對應環境變數 | 必要性 |
|------|---------|------------|--------|
| Proxy URL | `-ProxyUrl` | `HTTPS_PROXY` + `HTTP_PROXY` | 走企業 Proxy 才需要;直連可省略 |
| 額外不走 Proxy 的主機 | `-NoProxy` | `NO_PROXY`(合併 IMDS / 127.0.0.1 後) | 視內網需求 |
| 企業 CA bundle 路徑 | `-CaCertPath` | `REQUESTS_CA_BUNDLE`(僅在路徑存在時寫入) | 選用,**注意實際行為見下方說明** |

### A. 設定 Proxy URL

```powershell
# 最常見的 HTTP CONNECT proxy(企業 Zscaler / Squid / Forcepoint 等)
Set-AzTlsBypassConfig -ProxyUrl 'http://proxy.contoso.com:8080'

# 需要帳號密碼的 Proxy(URL-encode 密碼中的特殊字元)
Set-AzTlsBypassConfig -ProxyUrl 'http://user:p%40ssw0rd@proxy.contoso.com:8080'

# 同時設定不走 Proxy 的內網主機(IMDS 169.254.169.254 / localhost 會自動合併,毋須列出)
Set-AzTlsBypassConfig `
    -ProxyUrl 'http://proxy.contoso.com:8080' `
    -NoProxy  @('*.contoso.local', '10.0.0.0/8')

# 取消 Proxy(回到直連)
Set-AzTlsBypassConfig -ProxyUrl ''
```

> 啟用後可用 `Get-AzTlsBypassStatus` 檢查 `Config.ProxyUrl`,或在 PowerShell 中 `$env:HTTPS_PROXY` 確認已套用。

### B. 設定 CA 憑證 — **請先讀懂目前的實際行為**

`AzTlsBypass` 的核心是在 Python 啟動時 monkey-patch `requests.sessions.Session`,把 `verify=False` **無條件**強制套到整個程序。也就是說:

> ⚠️ **目前版本(0.1.0)無論你是否提供 `-CaCertPath`,`az login` 走的 HTTP 請求都不會做 TLS 憑證驗證。**

`-CaCertPath` 在當前版本實際上只做兩件事:
1. 把路徑寫入 `REQUESTS_CA_BUNDLE` 環境變數,讓**同一個 session 中其他不在 monkey-patch 影響下的工具**(例如 `pip`、`curl --cacert "$env:CURL_CA_BUNDLE"`)可以撿到。
2. 為「日後改成『有 CA 就做驗證、沒 CA 才停用』」的演進保留設定面。

換句話說:**若你的目的是「讓企業 CA 做合法的憑證驗證」,目前 `az login` 路徑做不到** — 只能整段停用驗證走 Proxy。若這對你的合規要求是不可接受的,請改用 `azure-cli` 官方支援的 `REQUESTS_CA_BUNDLE`(在 `az login` 之外的 azure-cli 子指令是有效的)並暫不啟用 `AzTlsBypass`。

設定方式(會把路徑記到 config,Enable 後寫入 `REQUESTS_CA_BUNDLE`):

```powershell
Set-AzTlsBypassConfig -CaCertPath 'C:\corp\ca-bundle.crt'

# 取消
Set-AzTlsBypassConfig -CaCertPath ''
```

支援的檔案格式:**PEM**(`-----BEGIN CERTIFICATE-----` 開頭,可包含多張串接)。**不接受** `.cer` (DER) / `.pfx` / `.p12`。下節有轉換方法。

### C. 能不能直接用「本機 Windows 憑證存放區」?

**不能直接用**。原因如下:

- Python 的 `requests` 函式庫**預設使用 `certifi` 的 PEM bundle**,**完全不讀** Windows 信任根憑證存放區(`Cert:\LocalMachine\Root` / `Cert:\CurrentUser\Root`)。
- 即使你已透過 GPO 把企業 Proxy CA 部署到 Windows 信任根,Azure CLI 也看不到。
- 第三方套件如 `python-certifi-win32` / `pip-system-certs` 可以橋接,但**不在本模組範圍**,且 Azure CLI 的 bundled Python 不建議自行裝套件。

**實務上有兩條路**:

#### C-1. 整段停用驗證(本模組預設,即「Enable-AzTlsBypass」)

不提供 `-CaCertPath`,讓 monkey-patch 直接把 `verify=False` 套上。**最簡單但安全等級最低**,只在你信任企業 Proxy 解密的前提下可接受。

#### C-2. 把企業 CA 從 Windows 憑證存放區匯出成 PEM 餵給 `-CaCertPath`

若你的政策要求至少對企業 CA 做驗證(雖然目前版本不會被 `az login` 使用,但 `REQUESTS_CA_BUNDLE` 對其他工具仍有效):

```powershell
# 1) 從 Windows 信任根找到企業 Proxy CA(用 Subject 關鍵字過濾)
$ca = Get-ChildItem Cert:\LocalMachine\Root |
      Where-Object Subject -like '*Contoso*Proxy*CA*'
$ca | Format-List Subject, Thumbprint, NotAfter

# 2) 匯出單張 CA 為 PEM(.crt 副檔名只是慣例)
$pemPath = 'C:\corp\contoso-proxy-ca.crt'
$bytes   = $ca[0].Export('Cert')   # DER bytes
$b64     = [Convert]::ToBase64String($bytes, 'InsertLineBreaks')
"-----BEGIN CERTIFICATE-----`n$b64`n-----END CERTIFICATE-----" |
    Set-Content -LiteralPath $pemPath -Encoding ascii

# 3) 若有多張 CA(中介 + 根),重複步驟 2 再用 Get-Content 串接:
#    Get-Content ca1.crt, ca2.crt | Set-Content corp-bundle.crt

# 4) 寫入 AzTlsBypass 設定
Set-AzTlsBypassConfig -CaCertPath $pemPath
Enable-AzTlsBypass
```

> 進階使用者也可改用 `certutil -encode <derFile> <pemFile>` 或 `openssl x509 -in <derFile> -inform DER -out <pemFile>` 進行格式轉換。

### D. 完整一次設定範例

最常見的「公司有 Proxy + 不在乎驗證」情境:

```powershell
Import-Module AzTlsBypass
Set-AzTlsBypassConfig -ProxyUrl 'http://proxy.contoso.com:8080'
Enable-AzTlsBypass -Persist        # 寫入 $PROFILE,永久生效
az login --identity                 # 透明可用
Get-AzTlsBypassStatus               # 確認狀態
```

「有 Proxy + 有自家 CA bundle(進階)」:

```powershell
Set-AzTlsBypassConfig `
    -ProxyUrl 'http://proxy.contoso.com:8080' `
    -NoProxy  @('*.contoso.local') `
    -CaCertPath 'C:\corp\contoso-bundle.crt'
Enable-AzTlsBypass -Persist
```

### E. 設定檔位置與檢視

| 項目 | 路徑 |
|------|------|
| 設定檔 | `~/.AzTlsBypass/config.json`(Windows: `$env:USERPROFILE\.AzTlsBypass\config.json`) |
| 讀取 | `Get-AzTlsBypassConfig` |
| 清空 | `Clear-AzTlsBypassConfig` |
| 啟用後實際生效的環境變數 | `Get-AzTlsBypassStatus` 的 `EnvActive` 區塊,或 `Get-ChildItem env: | Where-Object Name -match 'PROXY|TLS|VERIFY'` |

---

## 透明性是怎麼做到的

`Enable-AzTlsBypass` 做兩件事:

1. **設定環境變數** — `AZ_TLS_BYPASS_ACTIVE=1` + `HTTPS_PROXY`、`NO_PROXY`、`AZURE_CLI_DISABLE_CONNECTION_VERIFICATION` 等姊妹變數。
2. **定義 `function global:az`** — 攔截所有 `az ...` 呼叫,轉交給 `Invoke-AzWithBypass`,後者:
   - 解析 `az.cmd` 與 bundled `python.exe` 路徑
   - 把 `AzTlsBypass\PythonShim` 推到 `PYTHONPATH` 最前面
   - 帶著正確的 env vars 呼叫 `az.cmd`
   - 結束後還原 env vars(只影響子程序,不汙染當前 session 的其他工具)

對使用者而言,輸入的還是 `az login`。

---

## 指令一覽

| Cmdlet | 說明 |
|--------|------|
| `Enable-AzTlsBypass [-Persist] [-NoBanner]` | 啟用當前 session(可選永久) |
| `Disable-AzTlsBypass [-Persist]` | 停用,可同時移除 `$PROFILE` 區塊 |
| `Get-AzTlsBypassStatus` | 回傳 `Active` / `EnvActive` / `FunctionOverride` / `Persisted` / `Config` / `AzPath` / `PythonPath` |
| `Invoke-AzWithBypass <AzArgs>` | 一次性呼叫(不影響全域 `az` 函式) |
| `Set-AzTlsBypassConfig [-ProxyUrl] [-NoProxy] [-CaCertPath]` | 持久化設定到 `~/.AzTlsBypass/config.json` |
| `Get-AzTlsBypassConfig` | 讀取目前設定 |
| `Clear-AzTlsBypassConfig` | 刪除設定檔 |

---

## 環境變數契約

| 變數 | 用途 | 由誰寫入 |
|------|------|---------|
| `AZ_TLS_BYPASS_ACTIVE` | 主啟用旗標,被 `sitecustomize.py` 讀取 | `Enable-AzTlsBypass` |
| `AZ_LOGIN_INSECURE_PATCH` | 向下相容(舊版 hotpatch 命名) | `Enable-AzTlsBypass` |
| `AZURE_CLI_DISABLE_CONNECTION_VERIFICATION` | azure-cli 自己的開關;同步以保證一致 | `Enable-AzTlsBypass` |
| `ADAL_PYTHON_SSL_NO_VERIFY` | MSAL/ADAL 路徑用 | `Enable-AzTlsBypass` |
| `PYTHONHTTPSVERIFY` | Python `urllib` 路徑用 | `Enable-AzTlsBypass` |
| `HTTPS_PROXY` / `HTTP_PROXY` | requests/MSAL Proxy 設定 | `Enable-AzTlsBypass`(讀 config) |
| `NO_PROXY` | 必須包含 `169.254.169.254`(IMDS)讓 `az login --identity` 在 Azure VM 上可用 | `Enable-AzTlsBypass` 自動 merge |
| `REQUESTS_CA_BUNDLE` | 若 `CaCertPath` 有設則寫入;否則 **清除**(避免覆寫 `verify=False`) | `Enable-AzTlsBypass` |

---

## 開發

```powershell
# Python 單元 + 整合測試 (18 case)
python -m pytest tests/python/ -v

# PowerShell 單元 + 整合測試 (21 case,含 PSScriptAnalyzer)
pwsh -Command "Invoke-Pester -Path tests/powershell/ -Output Detailed"
```

CI 必須兩端皆綠才能合併。

---

## 目錄結構

```
tls-bypass/
├── core/                   # 共用 Python 邏輯
│   └── tls_bypass_core.py
├── powershell/
│   ├── AzTlsBypass/        # PowerShell 模組
│   │   ├── AzTlsBypass.psd1
│   │   ├── AzTlsBypass.psm1
│   │   ├── Public/         # 對使用者匯出的 cmdlets
│   │   ├── Private/        # 內部 helpers
│   │   └── PythonShim/     # sitecustomize.py + tls_bypass_core.py
│   ├── Install-AzTlsBypass.ps1
│   └── Uninstall-AzTlsBypass.ps1
├── extension/              # L2 az extension (規劃中)
├── tests/
│   ├── python/             # pytest
│   └── powershell/         # Pester
├── archive/                # 原始 hotpatch 保存(歷史參考)
├── LICENSE
├── HISTORY.md
├── SECURITY.md
└── README.md
```

---

## 授權

MIT — 見 [LICENSE](LICENSE)。

## 貢獻與問題回報

歡迎透過 GitHub Issues / Pull Requests 參與。安全議題請依 [SECURITY.md](SECURITY.md) 指引私下回報。
