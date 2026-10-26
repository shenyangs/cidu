<p align="center">
  <img src="docs/assets/cidu-banner.svg" alt="词渡 Cidu — Your words. A new home." width="100%">
</p>

<p align="center">
  <strong>把熟悉的词，带到下一款输入法。</strong><br>
  macOS 原生词库迁移工具 · 本机处理 · 自动备份 · 可供 Agent 调用
</p>

<p align="center">
  <a href="https://github.com/shenyangs/cidu/releases/tag/v0.8.0"><img alt="版本 0.8.0" src="https://img.shields.io/badge/version-0.8.0-267A61?style=flat-square"></a>
  <img alt="macOS 13+ · Apple Silicon" src="https://img.shields.io/badge/macOS-13%2B%20%C2%B7%20Apple%20Silicon-333333?style=flat-square&logo=apple">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-267A61?style=flat-square"></a>
  <a href="https://github.com/shenyangs/cidu/actions/workflows/ci.yml"><img alt="Build and tests" src="https://github.com/shenyangs/cidu/actions/workflows/ci.yml/badge.svg"></a>
</p>

<p align="center">
  <strong>简体中文</strong> · <a href="README.en.md">English</a><br>
  <a href="https://github.com/shenyangs/cidu/releases/download/v0.8.0/Cidu-0.8.0-macOS-arm64.dmg">下载 macOS 安装包</a> ·
  <a href="https://github.com/shenyangs/cidu/releases/tag/v0.8.0">全部发行文件</a> ·
  <a href="CONTRIBUTING.md">参与贡献</a>
</p>

---

词库里有你的名字、常用表达，还有多年积累的输入习惯。换输入法时，这些内容值得被好好带走。

词渡将读取、兼容检查、转换、备份和迁移放进一个原生窗口。可以通过官方导出流程迁移，也可以先把词库保存成可重新打开的档案。遇到无法确认的编码，会保留原件和原因，让你决定下一步。

| 原生操作 | 认真保留 | 本地可控 |
| :--- | :--- | :--- |
| SwiftUI 界面，分步权限引导；macOS 26+ 使用 Liquid Glass | 原始文件、完整档案、未迁移词条与原因一并保存 | 无账号、无遥测；GUI 与 CLI 使用同一套迁移逻辑 |

> **0.8.0 是公开预览版。** 自动迁移已适配「百度 Mac 6.1.12.10 官方导出 → 豆包 Mac 1.0.2 指定引擎」，执行前还会检查本机版本、引擎指纹和账号。**豆包 1.0.3 及其他未知引擎会被拦截**，可以使用文件工具保存档案。格式支持与真实安装验证的范围见下表及[验证记录](docs/VALIDATION.md)。

## 开始使用

1. 下载 [DMG](https://github.com/shenyangs/cidu/releases/download/v0.8.0/Cidu-0.8.0-macOS-arm64.dmg)，将「词渡」拖入 Applications 后打开。发行包已通过 Developer ID 签名和 Apple 公证。
2. 选择来源与去向，处理界面列出的待办项。自动读取百度词库时，需要你在系统设置中允许辅助功能权限；也可以改用已经导出的文件。
3. 查看迁移计划。存在待适配词条时，会分别显示新增、已存在和未迁移数量；只有明确选择「只迁移已验证的词条」才会部分安装。
4. 完成后在目标输入法中抽查词语，并重启输入法复查。「迁移记录」可恢复迁移前备份；目标后来学习了新内容时，会拒绝覆盖。

发布包面向 **Apple Silicon**，最低部署目标为 **macOS 13**；实机验证系统为 macOS 27.0.1，其他系统版本、Intel 和第二台设备尚未实测。当前应用界面为中文。

<details>
<summary><strong>看看应用界面</strong></summary>

<p align="center"><img src="docs/assets/cidu-preview.png" alt="词渡主界面：来源、目标和兼容性检查" width="900"></p>

截图展示当前机器的只读预检：豆包已升级为 1.0.3，版本门禁按预期阻止自动安装。未显示个人词条。

</details>

## 迁移时发生了什么

```text
读取原件 → 检查兼容 → 生成计划 → 隔离副本验证 → 保存备份 → 安装并回读
                         ↓
               保留完整来源与未迁移档案
```

自动安装会先退出目标输入法，再核对账号、目标文件和哈希，以原子替换提交结果。安装与恢复都会先持久化操作意图；发生中断时，历史记录根据前后快照检查当前结果。目标已被外部修改时停止写入。

备份位于 `~/Library/Application Support/Cidu/Transactions`，目录权限为 `0700`、文件为 `0600`。0.8 新计划保留 `source.original`、完整 `source.json`、可重新打开的 `unmigrated.json` 和 `unmigrated-reasons.json`。文件转换工具生成的迁移包与自动安装备份是不同产物；生成转换文件不表示已安装。

## 格式与兼容性

| 来源 / 格式 | 读取 | 输出 | 当前边界 |
| :--- | :---: | :---: | :--- |
| 百度 Mac 官方导出 TXT | ✓ | ✓ | 已测真实读取与往返；导入百度尚未实机验证 |
| 搜狗拼音 TXT | ✓ | ✓ | GBK；不支持 SCEL / BIN；不保留权重 |
| Rime / 鼠须管 `.dict.yaml` | ✓ | ✓ | 明确的全拼 text / code / weight；不展开 import_tables、不读 userdb |
| 豆包 Mac `usr.dat` | ✓ | 档案 | 保留音节 ID 和原始属性；自动安装仅限已适配的 1.0.2 引擎 |
| QQ 拼音 TXT | ✓ | ✓ | 三列拼音 / 词语 / 词频，UTF-16 LE 输出；无逗号扩展、QPyd / Qcel |
| 谷歌拼音文本 | ✓ | ✓ | GBK 三列词语 / 词频 / 拼音，适用于历史词库 |
| macOS 文本替换 PLIST | ✓ | ✓ | XML / 二进制读取、XML 输出；通过系统官方拖入 / 拖出流程使用 |
| 微软 `mschxudp` 自定义短语 | ✓ | 档案 / Mac | 保留缩写和候选序号；不支持 DCTX 或 Windows 安装 |
| 微信 Mac LevelDB 完整副本 | 实验 | 已识别记录 | 只读已知键，保留完整快照；不写回、未做真实版本验证 |
| 词渡 JSON / TSV | ✓ | ✓ | 保留重复、多音字、原始字段与内部编码，可重新导入 |

除注明的百度 / 豆包本机验证外，其他输入法的真实导入或部署仍待验证。不是所有格式组合都能无损互转：

- **编码与词频**：不可表达的字符、未知音节边界和非标准编码不会静默丢弃。Rime 输出权重为 1；百度原值仅同来源保留，其他来源输出占位值 1；QQ / 谷歌仅同格式输出保留词频。完整原值留在 JSON / TSV，候选排序、联想与学习历史不保证迁移。
- **拼音与短语**：Rime 需要用户确认是全拼，形码 / 双拼不能可靠自动识别。短语缩写独立建模；普通学习词库不会自动变成系统文本替换。系统短语仅支持单行和已知字段。
- **微信实验**：退出输入法后复制完整数据库文件夹，再选择副本。需要 CURRENT、引用的 MANIFEST 和全部数据 / 日志文件；上限 40 MB。仅识别 `!u_d_v_p!` 键，识别数量不代表完整学习词库。系统自动学习词库仍未支持。

详细说明见[兼容性协议](docs/COMPATIBILITY.md)和[第三方说明](THIRD_PARTY.md)。

## 交给 AI 助手

在「更多工具 → 交给我的 AI 助手」复制指引，或安装发行页中的 [Agent Skill](https://github.com/shenyangs/cidu/releases/download/v0.8.0/Cidu-0.8.0-agent-skill.zip)。适用于能访问本机文件和执行命令的 Agent；目前提供 **CLI + Skill**，没有 MCP 服务。

CLI 随完整应用分发，请根据安装位置调整路径，保留它与 `EngineProbe` 的相对位置：

```sh
"/Applications/词渡.app/Contents/MacOS/cidu-cli" help
"/Applications/词渡.app/Contents/MacOS/cidu-cli" status --file "/path/to/export.txt"
"/Applications/词渡.app/Contents/MacOS/cidu-cli" plan --file "/path/to/export.txt"
"/Applications/词渡.app/Contents/MacOS/cidu-cli" history
```

`status` 只检查；`plan` 在私有目录准备候选与备份并验证隔离副本，不安装词库。省略 `--file` 时会操作百度官方窗口导出，需要对应权限。计划有效期为 24 小时。

已明确授权安装或恢复时，再使用以下命令；部分迁移还需要用户明确接受后添加 `--allow-partial`：

```sh
"/Applications/词渡.app/Contents/MacOS/cidu-cli" apply PLAN_ID --confirm
"/Applications/词渡.app/Contents/MacOS/cidu-cli" restore RECEIPT_ID --confirm
```

每次命令输出一条 JSON，退出码为 `0` 成功、`2` 环境未就绪、`1` 参数或操作失败。`status.ok` 表示检查完成，`ready` 才表示基础条件通过；只有 `installed` 表示已安装。`--confirm` 表达写入意图，不是权限绕过或用户授权凭证。完整行为契约见 [SKILL.md](skills/cidu-migrate/SKILL.md)。

## 隐私与数据保留

词渡没有网络请求、账号或遥测代码。词库解析、转换与备份都在本机进行；选择云盘目录时，文件可能由系统或云盘客户端同步。Agent 应只讨论计数和检查结果，不把完整词库、备份或原始日志送给远程模型。

迁移包中的哈希用来发现损坏或文件变化，不能证明作者身份。词渡不自动开启系统权限、不修改 TCC 数据库，也不会猜选多个目标账号。请将个人词库保存在仓库之外。

## 从源码构建

需要 Apple Silicon Mac、**Xcode 26+ 或提供 macOS 26+ SDK 的 Command Line Tools**、CMake 3.16+ 和 Python 3。没有 CMake 时，脚本也支持通过 `uvx` 首次下载固定版本 CMake。LevelDB 1.23 与 Snappy 1.2.1 的源码已包含，运行应用无需 Homebrew。

```sh
git clone https://github.com/shenyangs/cidu.git
cd cidu
bash scripts/test.sh
bash scripts/test-preflight.sh
bash scripts/build.sh
open "build/词渡.app"
```

缺少 Apple 工具链时，先运行 `xcode-select --install`，并确认 `xcrun --sdk macosx --show-sdk-version` 至少为 26。CMake 可从[官方安装包](https://cmake.org/download/)安装；已有 uv 时可用 `uvx --from cmake==3.31.6 cmake --version` 检查备用路径。

开发构建默认使用 ad-hoc 签名，与已公证发行包不同。`VERSION` / `BUILD_NUMBER` 是唯一版本源；`python3 scripts/package-public.py` 按[明确清单](scripts/public-files.txt)生成源码、Skill ZIP 和发行校验和。开发者签名与公证流程、项目结构及测试边界见[贡献指南](CONTRIBUTING.md)。

## 0.8.0 有什么变化

- 安装与恢复记录可在中断后按快照核对，避免错误覆盖。
- 完整保留原始来源与未迁移档案，部分迁移需要明确选择。
- 有界读取、特殊文件拒绝和私有权限检查覆盖更多异常输入。
- 清楚区分待执行、部分完成、未变化和已恢复，兼容旧记录中的未知计数。
- 统一版本与公开打包清单；**161 项核心检查 + 17 项预检检查**通过。

后续重点是更多设备和系统版本验证、输入法升级适配，以及更多目标的官方导入流程。已完成项与验证限制分别记录在[整改记录](docs/REMEDIATION-0.8.md)、[验证记录](docs/VALIDATION.md)和[产品路线](docs/PRODUCT.md)。

## 贡献与许可

欢迎报告兼容性结果、提交人工样例、改进格式适配和英文体验。提交问题时请提供版本、复现步骤与脱敏错误，避免上传个人词库。开始前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

词渡源代码采用 [MIT License](LICENSE)。LevelDB、Snappy 与格式参考的许可和来源见 [THIRD_PARTY.md](THIRD_PARTY.md)。本项目独立开发，与文中提及的输入法厂商无隶属关系；不分发它们的框架、安装包或个人词库。
