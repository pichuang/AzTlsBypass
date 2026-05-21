# AzTlsBypass

> 在 TLS 中介 Proxy 後讓 `az login` 與 Azure CLI 透明可用 — 為 PowerShell 5.1 / 7+ 而生。

Azure CLI(自 [#26021](https://github.com/Azure/azure-cli/pull/26021) 起)在 `az login` 路徑硬編碼了 `verify=True`,使得在企業 TLS 解密 Proxy 後執行 `az login` 必定觸發 `SSLCertVerificationError`。本專案以**雙軌**方式繞過這個限制:

| 軌道 | 目標族群 | 安裝方式 | 使用體驗 |
|------|----------|----------|----------|
| **L1 — `AzTlsBypass` PowerShell 模組** | 個人 / 工作站 | `Install-AzTlsBypass.ps1` | `az login` 直接可用,**對使用者完全透明** |
| **L2 — `az tls-bypass` 擴充套件** | 團隊 / CI(規劃中) | `az extension add` | `az tls-bypass login` 顯式呼叫 |

> ⚠️ **安全提醒**:啟用本工具會關閉整個 Python 程序的 TLS 憑證驗證,**只應在受信任的企業 TLS 解密 Proxy 後使用**。優先選擇 `Set-AzTlsBypassConfig -CaCertPath` 安裝企業 CA 憑證(僅停用名稱驗證而非整體驗證)。

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
    # -CaCertPath 'C:\corp\ca.crt'       # 若有 CA bundle 則此處供給;否則直接停用驗證
```

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
