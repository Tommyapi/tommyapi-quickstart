# tommyapi-quickstart

**一条命令把 Claude Code / Codex CLI 配到 TommyAPI（大模型 API 中转站），Cursor / Cline / Cherry Studio 等 OpenAI 兼容客户端附带填写指引。**
One command to point Claude Code and Codex CLI at TommyAPI, an LLM API relay (Anthropic base url + OpenAI-compatible endpoint). Setup notes for Cursor, Cline, Roo Code, Cherry Studio and Open WebUI included.

关键词：Claude Code 国内、Claude Code 中转、Anthropic base url、ANTHROPIC_BASE_URL、Codex 配置、Codex CLI 第三方 API、OpenAI 兼容、API 中转、大模型 API 中转站、国内直连、一键配置。

## 一行安装 / Quick install

先到 <https://tommyapi.com/start/> 注册，在 <https://tommyapi.com/console> 的「令牌」页创建 key（形如 `sk-...`）。

macOS / Linux：

```bash
curl -fsSL https://raw.githubusercontent.com/Tommyapi/tommyapi-quickstart/main/install.sh | bash -s -- --key sk-xxx
```

Windows PowerShell（5.1 与 7 都行）：

```powershell
$env:TOMMYAPI_KEY = 'sk-xxx'; irm https://raw.githubusercontent.com/Tommyapi/tommyapi-quickstart/main/install.ps1 | iex
```

带参数的写法（国内用 `cn` 入口）：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Tommyapi/tommyapi-quickstart/main/install.ps1))) -Key sk-xxx -Endpoint cn
```
```bash
curl -fsSL https://raw.githubusercontent.com/Tommyapi/tommyapi-quickstart/main/install.sh | bash -s -- --key sk-xxx --endpoint cn
```

装完**新开一个终端**，运行 `claude` 或 `codex` 即可。脚本最后会做一次不花钱的连通性自检（`GET /v1/models`）。

> 不放心可以先看脚本再跑：`install.sh` 和 `install.ps1` 都是明文，不下载任何额外东西，不上报任何数据。先加 `--dry-run`（PowerShell 是 `-DryRun`）只看会改什么、不写文件。

## 支持的工具 / Supported tools

| 工具 | 方式 | 脚本改什么 |
|---|---|---|
| Claude Code | 脚本自动配置 | `~/.claude/settings.json` 的 `env`；Windows 另写用户级环境变量 |
| Codex CLI | 脚本自动配置 | `~/.codex/config.toml`（只增改 `model_provider` 与 `[model_providers.tommyapi]`）+ 环境变量 `TOMMYAPI_KEY` |
| Cursor / Cline / Roo Code | 手动填写（见下） | 脚本不碰它们的私有配置 |
| Cherry Studio / Open WebUI | 手动填写（见下） | 同上 |
| 其他任何 OpenAI 兼容客户端 | 手动填写 | Base URL 填 `https://tommyapi.com/v1` |

## 配置参数表 / Parameters（2026-11-06 核实）

| 项 | 值 |
|---|---|
| 主入口（美国直连） | `https://tommyapi.com` |
| 国内加速 | `https://cn.tommyapi.com` |
| 新加坡 | `https://sg.tommyapi.com` |
| OpenAI 兼容 | `POST /v1/chat/completions`，`GET /v1/models` |
| Codex 的 Responses 协议 | `POST /v1/responses` |
| Anthropic 兼容 | `POST /v1/messages` |
| 未带 key 的响应 | HTTP 401，JSON `{"error":{"message":"Invalid token ..."}}`（可用来免费测连通性） |
| 注册 / 取 key | <https://tommyapi.com/start/> / <https://tommyapi.com/console>「令牌」页 |
| Claude Code | `ANTHROPIC_BASE_URL=https://tommyapi.com`（**不要带 `/v1`**，Claude Code 自己拼 `/v1/messages`），`ANTHROPIC_AUTH_TOKEN=<key>`，可选 `ANTHROPIC_MODEL` |
| Codex CLI | `base_url = "https://tommyapi.com/v1"`，`env_key = "TOMMYAPI_KEY"`，`wire_api = "responses"` |
| Cursor / Cline / Roo Code / Cherry Studio / Open WebUI | Base URL `https://tommyapi.com/v1`，API Key 填 key |

三个入口接口完全相同，哪个快用哪个：`--endpoint us|cn|sg`。

## 参数 / Options

| install.sh | install.ps1 | 说明 |
|---|---|---|
| `--key sk-xxx` | `-Key sk-xxx` | key；也可用环境变量 `TOMMYAPI_KEY`，都没有则交互输入（不回显） |
| `--endpoint us\|cn\|sg` | `-Endpoint` | 默认 `us` |
| `--tools claude,codex,all` | `-Tools` | 默认 `all` |
| `--model NAME` | `-Model` | 可选，写入 `ANTHROPIC_MODEL` |
| `--dry-run` | `-DryRun` | 只显示将要做的修改 |
| `--uninstall` | `-Uninstall` | 只移除 TommyAPI 相关条目，其余原样保留 |
| `--no-check` | `-NoCheck` | 跳过最后的连通性自检 |
| | `-NoUserEnv` | 不写 Windows 用户级环境变量（只改文件） |

`irm | iex` 方式读取环境变量 `TOMMYAPI_KEY`、`TOMMYAPI_ENDPOINT`、`TOMMYAPI_TOOLS`、`TOMMYAPI_MODEL`；`install.sh` 同样认这几个环境变量。

### 安全与幂等

- 改任何已有文件之前，先备份到同目录 `*.bak-tommyapi-<时间戳>`；内容没变就不改、不备份，重复运行不会重复追加。
- 备份里含有原来的内容（包括可能的旧 key），请自行保管。新建的 `settings.json` 权限为 600（Unix）。
- `--uninstall`：从 `settings.json`、`config.toml`、shell rc 里摘掉 TommyAPI 条目；你原来的 `model_provider` 行装的时候会被注释成 `# tommyapi-disabled: ...`，卸载时还原。文件摘完变空则删除（备份保留）。
- 不收集数据，不上报，不下载额外内容；唯一的网络请求是最后那一次 `GET /v1/models`。
- Claude Code 原有的、指向别处的 `ANTHROPIC_BASE_URL` 会被覆盖（有备份）。卸载时只有当它指向 tommyapi 才会删。

## 手动配置 GUI 客户端

下面都是同一组值：**Base URL = `https://tommyapi.com/v1`**（国内可换 `https://cn.tommyapi.com/v1`），**API Key = 你的 `sk-...`**，模型名用你在控制台看到的名称。

- **Cursor**：Settings → Models，打开 *OpenAI API Key* 并填 key，展开 *Override OpenAI Base URL* 填 Base URL。
- **Cline**（VS Code 扩展）：侧栏设置里 API Provider 选 *OpenAI Compatible*，依次填 Base URL、API Key、Model ID。
- **Roo Code**：同 Cline，Provider 选 *OpenAI Compatible*。
- **Cherry Studio**：设置 → 模型服务 → 添加，提供商类型选 *OpenAI*，填「API 地址」和「API 密钥」，再添加模型。
- **Open WebUI**：管理员面板 → Settings → Connections → OpenAI API，Base URL 与 Key 填入。

各客户端界面会随版本变动，位置以你当前版本为准；字段名称（Base URL / API Key）是不变的。

## 测试 / Tests

```bash
bash tests/test_install_sh.sh        # 假 HOME 下的纯 bash 断言
pwsh -NoProfile -File tests/test_install_ps1.ps1   # PowerShell 7；也可用 powershell.exe（5.1）
```

测试覆盖：首次安装内容、幂等、保留已有配置、备份、重新换 key、`--uninstall` 还原、`--dry-run`、参数校验、`irm | iex` 形式。CI 在 Linux / macOS / Windows 上跑。

## English

`tommyapi-quickstart` configures [Claude Code](https://docs.claude.com/en/docs/claude-code) and [Codex CLI](https://github.com/openai/codex) to use TommyAPI, an LLM API relay with an Anthropic-compatible (`/v1/messages`), OpenAI-compatible (`/v1/chat/completions`) and Responses (`/v1/responses`) API.

- Claude Code: sets `ANTHROPIC_BASE_URL` (without `/v1`) and `ANTHROPIC_AUTH_TOKEN` in `~/.claude/settings.json` (plus user env vars on Windows).
- Codex CLI: sets `model_provider = "tommyapi"` and a `[model_providers.tommyapi]` table (`wire_api = "responses"`) in `~/.codex/config.toml`, and exports `TOMMYAPI_KEY`.
- Idempotent, timestamped backups, `--dry-run`, `--uninstall`, no telemetry, plain-text scripts. One free `GET /v1/models` self-check at the end (HTTP 200 = works, 401 = bad key, timeout = try `--endpoint cn` or `sg`).
- Cursor / Cline / Roo Code / Cherry Studio / Open WebUI / any OpenAI-compatible client: Base URL `https://tommyapi.com/v1` + your key.

Endpoints (verified 2026-11-06): `https://tommyapi.com` (US, primary), `https://cn.tommyapi.com` (China-optimized), `https://sg.tommyapi.com` (Singapore). Get a key at <https://tommyapi.com/console>.

## Support / 打赏

如果这个脚本帮你省了时间，欢迎打赏（请按网络转对应币种 / send the matching coin on the matching network）：

| 币种 / 网络 | 地址 |
|---|---|
| USDT-TRC20 | `TNGdTwE6opH6rmUyoG1JUR7FSyEb4k273R` |
| USDT (ERC20 / BEP20 / Polygon)、ETH (Ethereum / Arbitrum / Base) | `0x59c43144a862b351fa1086ae842d1327c9d91613` |
| BTC | `1RS6tWXHregLfEsiPzVUCUBuhgDg5uTSV` |
| USDT-Solana | `HZguEXfTtLChNdJTxAYCbcGscaqikz8JYrEpUhEyeVd9` |

## License

MIT, see [LICENSE](LICENSE). Copyright (c) 2026 tommyapi.
