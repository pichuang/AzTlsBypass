# Security Policy

## ⚠️ 此工具的本質

`AzTlsBypass` **故意關閉 TLS 憑證驗證**。這違反一般 PKI 最佳實踐,是一個明確的 trade-off:

- ✅ 在受信任的企業 TLS 解密 Proxy(如 Zscaler、Symantec、Check Point)後,讓 `az login` 與整個 Azure CLI 流程能正常運作
- ❌ 在公開網路或不受信任的網路環境**絕對不可使用**(中間人攻擊)

## 適用情境

1. 你的電腦只能透過企業 Proxy 連到外網
2. 該 Proxy 會做 TLS 解密 → 重新加密,簽章用企業根 CA
3. 你的 Azure CLI 內建 Python 沒有採用企業 CA bundle(這是 Python `certifi` 預設行為)
4. 修正 CA bundle 的選項對你不適用(例如:bundled `python.exe` 唯讀、無 admin 權限)

如果上面有任一項不滿足,**請優先**:
- 用 `az extension add` 安裝企業 CA bundle
- 或設定 `REQUESTS_CA_BUNDLE` 指向企業 CA
- 或在 bundled Python 中替換 `certifi/cacert.pem`

僅當上述都行不通時,才考慮 `AzTlsBypass`。

## 不適用情境

| 場景 | 替代方案 |
|------|---------|
| CI/CD on GitHub Actions / Azure DevOps | 直接用 OIDC / federated identity,不需要任何 TLS bypass |
| 公開咖啡廳 Wi-Fi | **絕對不要用** — 用 VPN 或手機熱點即可 |
| Docker 容器內 | 在 Dockerfile 中安裝企業 CA bundle 更乾淨 |
| WSL 2 | 設定 `REQUESTS_CA_BUNDLE` 通常已足夠 |

## 報告漏洞

如果你發現本工具中可被惡意利用的設計缺陷(例如:在不該啟用時被啟用、env var 注入、profile script 被破壞性修改等),請透過 GitHub 的 **"Report a vulnerability"** 功能(Security 分頁)私下回報,**不要**開 public issue。

## 預設安全特性

- ✅ Opt-in only:沒有設 `AZ_TLS_BYPASS_ACTIVE=1` 不會啟動 patch
- ✅ 啟用時會在 stderr 印出 `[AzTlsBypass] TLS certificate verification disabled process-wide` 警告
- ✅ Profile 注入使用 marker comment,可被 `Disable-AzTlsBypass -Persist` 乾淨移除
- ✅ 環境變數變更預設只影響當前 process(非 User-level)
- ✅ `NO_PROXY` 強制包含 IMDS(`169.254.169.254`)讓 managed identity 不外洩到 Proxy
- ✅ 沒有任何外部網路呼叫、telemetry、自動更新邏輯
