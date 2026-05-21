# Azure CLI Proxy Wrapper 使用說明

這份工具讓使用者在公司 HTTP proxy 環境下，仍可直接使用一般 `az ...` 指令。安裝後會在目前使用者的 Windows PowerShell 5.1 profile 中加入一個 `az` wrapper，自動套用 proxy、TLS fallback，並強制對 Azure IMDS (`169.254.169.254`) 做 proxy bypass，避免 `az login --identity` 發生 JSONDecodeError。

## 使用者操作

### 安裝

雙擊：

```text
點兩下安裝-AzProxyProfile.cmd
```

看到 `Install completed.` 後，關閉並重新開啟 Windows PowerShell 5.1。

### 使用

重新開啟 Windows PowerShell 5.1 後，直接使用一般 Azure CLI 指令：

```powershell
az login --tenant b449d301-e285-4551-8467-773bebf5ed31
az login --identity
az login --identity --client-id <user-assigned-managed-identity-client-id>
az account show --output table
az network application-gateway list
```

### 移除

雙擊：

```text
點兩下移除-AzProxyProfile.cmd
```

看到 `Uninstall completed.` 後，關閉並重新開啟 Windows PowerShell 5.1。

## 需要交付給使用者的檔案

請提供整個資料夾，至少需包含：

```text
點兩下安裝-AzProxyProfile.cmd
點兩下移除-AzProxyProfile.cmd
Install-AzProxyProfile.ps1
Uninstall-AzProxyProfile.ps1
Invoke-AzWithProxy.ps1
.azure-cli-insecure-sitecustomize\sitecustomize.py
```

## 已硬編碼設定

| 項目 | 值 |
| --- | --- |
| Proxy | `http://proxy.example.com:8080` |
| Tenant ID | `b449d301-e285-4551-8467-773bebf5ed31` |
| Helper 路徑 | 安裝時自動使用目前工具資料夾 |

## 注意事項

- 本工具不提供 device-code 登入模式。
- 安裝只影響目前 Windows 使用者的 PowerShell profile。
- 若移動工具資料夾，請重新雙擊安裝檔。
- 如果你之前已安裝舊版 wrapper，請重新雙擊安裝，讓 NO_PROXY bypass 設定寫入 profile。
- 這是臨時 workaround；正式解法仍應由 proxy / PKI 團隊提供符合 Azure CLI 嚴格驗證要求的 CA 憑證，至少包含 `Subject Key Identifier` 與 `Authority Key Identifier`。
