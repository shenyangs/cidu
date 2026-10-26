# 参与词渡 / Contributing to Cidu

欢迎提交问题、兼容性验证和 Pull Request。请先阅读 [中文 README](README.md) 或 [English README](README.en.md)：能够解析一种格式，不代表已验证该输入法的真实安装。

Issues, compatibility reports, and pull requests are welcome. Start with the README: format parsing and tested installation are separate capabilities.

## 报告问题 / Report an issue

请提供 macOS 版本与架构、词渡版本、两端输入法版本、预期与实际行为，以及最小复现步骤。使用人工构造或脱敏样例；不要提交个人词库、账号路径、备份、凭据或完整原生日志。

Include the macOS version and architecture, Cidu version, both input-method versions, expected and actual behavior, and minimal reproduction steps. Use synthetic or redacted fixtures. Keep personal dictionaries, account paths, backups, credentials, and full native logs out of issues and commits.

## 本地开发 / Local development

需要 Apple Silicon Mac、包含 macOS 26+ SDK 的 Xcode / Command Line Tools、CMake 3.16+（或已安装的 `uvx`）和 Python 3。最低部署目标为 macOS 13，但这不代表已在所有旧系统上测试。

Use an Apple Silicon Mac, Xcode / Command Line Tools with the macOS 26+ SDK, CMake 3.16+ (or an existing `uvx` installation), and Python 3. The macOS 13 deployment target does not imply testing on every older release.

```sh
bash scripts/test.sh
bash scripts/test-preflight.sh
bash scripts/build.sh
```

前两项包含 161 项核心检查和 17 项预检检查，使用合成数据与临时目录，无需安装输入法。GitHub Actions 还会完整构建应用并检查公开打包清单。

These run 161 core checks and 17 preflight checks against synthetic data and temporary directories, without installed input methods. GitHub Actions also builds the complete app and validates the public package manifest.

`scripts/test-native.sh` 与 `scripts/test-cli.py` 需要本机已适配的豆包版本，读取真实目标并在隔离副本上验证，不属于 CI；它们不安装或恢复活动词库。`bash scripts/test.sh --source /path/to/export.txt` 可额外验证私有百度导出，只报告计数。请先阅读脚本，并将真实数据留在仓库之外。

`scripts/test-native.sh` and `scripts/test-cli.py` require a locally supported Doubao version and validate isolated copies of the real target. They are excluded from CI and do not install or restore the active dictionary. `bash scripts/test.sh --source /path/to/export.txt` additionally checks a private Baidu export and reports counts only. Read these scripts first and keep real data outside the repository.

## 代码导航 / Code map

| 路径 / Path | 职责 / Responsibility |
| :--- | :--- |
| `Sources/Core.swift`, `Sources/Formats.swift` | 词条模型、解析与输出 / Entry model, parsing, and exports |
| `Sources/MacFormats.swift`, `Sources/WeType.swift` | 系统短语与微信实验适配 / Mac phrases and experimental WeType adapter |
| `Sources/Migration.swift` | 私有归档、事务、安装与恢复 / Private archives, transactions, installation, and restoration |
| `Sources/Compatibility.swift`, `Sources/Preflight.swift` | 兼容门禁与只读检查 / Compatibility gates and read-only checks |
| `Sources/LiveMigration.swift`, `Sources/BaiduAutomation.swift` | 自动导出与迁移执行 / Official export automation and migration execution |
| `Sources/App.swift`, `Sources/MigrationView.swift` | 原生界面 / Native UI |
| `Sources/CLI.swift`, `skills/cidu-migrate/` | Agent 命令与行为契约 / Agent commands and behavior contract |
| `vendor/` | 随附 LevelDB / Snappy 源码及许可 / Bundled LevelDB / Snappy source and licenses |
| `experiments/` | 历史研究，不属于产品安装器 / Historical research, separate from the product installer |

## 发布 / Releases

`VERSION` 与 `BUILD_NUMBER` 是版本源。普通开发构建采用 ad-hoc 签名；正式发行由维护者使用自己的 Developer ID 和钥匙串公证配置：

`VERSION` and `BUILD_NUMBER` are the version sources. Development builds use ad-hoc signing. Maintainers create official releases using their own Developer ID and Keychain notarization profile:

```sh
CIDU_SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
CIDU_NOTARY_PROFILE="YOUR_KEYCHAIN_PROFILE" \
bash scripts/notarize.sh
python3 scripts/package-public.py
```

公证脚本会签名应用及嵌套程序、提交公证、附加票据并检查 Gatekeeper。`--skip-build` 仅用于复用已经正确签名的构建。私钥、公证配置和日志不得进入 Git；`build/` 与 `dist/` 默认忽略。

The notarization script signs the app and nested executables, notarizes, staples tickets, and checks Gatekeeper. Use `--skip-build` only to reuse a correctly signed build. Keep private keys, notarization configuration, and logs out of Git; `build/` and `dist/` are ignored.

新增公开文件时，逐项更新 `scripts/public-files.txt`；Git 跟踪文件应与该清单完全一致。打包器会逐字节检查归档，并生成相对文件名的 SHA-256 清单。发布页仅上传 DMG、应用 ZIP、源码 ZIP、Skill ZIP 和校验文件。

Add each new public file to `scripts/public-files.txt`. Git-tracked files must match that manifest exactly. The packager verifies archive bytes and produces SHA-256 checksums with relative filenames. Upload only the DMG, app ZIP, source ZIP, Skill ZIP, and checksum file to a release.

应用包含一份 Skill。修改它后必须重新构建、签名并公证，不能直接改动已签名应用的 Resources。验证记录应区分合成检查、隔离原生检查、真实安装与未测范围。

The app embeds the Skill. Skill changes require rebuilding, signing, and notarizing the app; do not patch a signed app's Resources. Validation records should distinguish synthetic checks, isolated native checks, real installation, and untested scope.
