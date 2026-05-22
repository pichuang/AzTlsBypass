# AzTlsBypass

> 在企業 TLS 解密 Proxy 後,讓 `az login` 與 Azure CLI 透明可用 — 支援 PowerShell 5.1 / 7+。

Azure CLI 自 [#26021](https://github.com/Azure/azure-cli/pull/26021) 起在 `az login` 路徑硬編碼 `verify=True`,使得企業 TLS 解密 Proxy 後的 `az login` 必定觸發 `SSLCertVerificationError`。本模組透過 `PYTHONPATH` + `sitecustomize.py` shim,在 Python 啟動時 monkey-patch `requests.Session`,讓 `az login` 在 Proxy 後也能正常運作。

> ⚠️ **啟用後會關閉整個 Python 程序的 TLS 憑證驗證,只應在你信任的企業 TLS 解密 Proxy 後使用。** 詳細安全考量見 [SECURITY.md](SECURITY.md) 與 [DEVELOPER.md](DEVELOPER.md)。

---

## 安裝

### 方法 A — 從 PowerShell Gallery(預計,尚未上架)

```powershell
Install-Module -Name AzTlsBypass -Scope CurrentUser
```

### 方法 B — Windows 雙擊一鍵安裝(推薦給終端使用者)

下載本 repo 後直接雙擊:

```text
powershell\點兩下安裝-AzTlsBypass.cmd
```

腳本會依序詢問**企業 Proxy URL** 與**選用的 CA bundle 路徑**,然後自動完成安裝、設定、永久啟用,並開新視窗驗證。

> `.cmd` 自動偵測 `pwsh.exe`(7+),不存在時回退 `powershell.exe`(5.1),並用 `-ExecutionPolicy Bypass`,**無須事先變更執行原則**。

### 方法 C — 手動安裝

```powershell
git clone https://github.com/pichuang/AzTlsBypass.git
cd AzTlsBypass\powershell
.\Install-AzTlsBypass.ps1
```

---

## 快速使用

```powershell
Import-Module AzTlsBypass

# 1. 設定企業 Proxy(若不需 Proxy 可跳過這步)
Set-AzTlsBypassConfig -ProxyUrl 'http://proxy.contoso.com:8080'

# 2. 永久啟用(寫入 $PROFILE,任何新 session 自動生效)
Enable-AzTlsBypass -Persist

# 3. 直接用,跟平常一樣
az login
az account show
```

當前 session 臨時啟用(不寫入 `$PROFILE`):

```powershell
Enable-AzTlsBypass
```

驗證狀態 / 解除 / 移除:

```powershell
Get-AzTlsBypassStatus            # 看目前狀態與設定
Disable-AzTlsBypass -Persist     # 停用並移除 $PROFILE 區塊
.\Uninstall-AzTlsBypass.ps1      # 完整移除模組
```

---

## 想做進階設定?

- **設定企業 CA 憑證、用本機 Windows 憑證、調整 NoProxy?** → 見 [DEVELOPER.md § 設定 Proxy 與 CA 憑證](DEVELOPER.md#設定-proxy-與-ca-憑證完整版)
- **完整 cmdlet 一覽、環境變數契約、內部原理?** → 見 [DEVELOPER.md](DEVELOPER.md)
- **開發、測試、發布到 PSGallery?** → 見 [DEVELOPER.md § 開發與測試](DEVELOPER.md#開發與測試)
- **版本歷史?** → 見 [HISTORY.md](HISTORY.md)
- **安全議題?** → 見 [SECURITY.md](SECURITY.md)

---

## 授權

MIT — 見 [LICENSE](LICENSE)。歡迎透過 GitHub Issues / Pull Requests 參與。
