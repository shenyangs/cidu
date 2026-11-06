# 闪电说 → 豆包 · FlashSay → Doubao

**0.9.0 源码预览，尚未包含在 0.8.0 公证安装包中。** / **0.9.0 source preview; not included in the notarized 0.8.0 download.**

## 中文

闪电说的词典保存固定写法和纠错规则，没有拼音或词频。词渡读取它的 Markdown 文件，在本机提供拼音建议，由用户逐条核对后进入豆包迁移计划。只迁移拼音候选；语音识别热词、自动替换效果、学习历史和排序不在本次支持范围。

### 操作

1. 从 main 构建词渡，在首页选择「闪电说 → 豆包输入法」，点击「读取并核对词典」。
2. 选择闪电说的 `DICTIONARY.md` 或其副本。0.8.1 的默认位置为：

   ```text
   ~/Library/Application Support/Shandianshuo/workspace/library/DICTIONARY.md
   ```

   文件选择器会在该目录存在时直接打开它。若在闪电说中移动过工作区，以实际资料库位置为准。也可以在装有闪电说的电脑上复制这个文件，带到目标 Mac；词渡不要求同机安装闪电说。
3. 核对每行拼音，空格分隔、不带声调，`ü` 写作 `v`。多音字和姓名需特别注意。英文或混合词没有自动建议，需手动填写你希望使用的拼音，或保持未勾选。
4. 逐条勾选「读音已核对」。改动拼音会取消该行勾选。每页显示 50 条，不会默认全选。
5. 「保存并继续」将原件及全部词条保存为迁移包，位于 `~/Library/Application Support/Cidu/Transactions/imports`。至少核对一条才可保存；无需豆包就能先完成留档。
6. 通过豆包预检后审阅计划；未核对或无法映射的词条会保留并计入未迁移数量。部分安装需要明确接受；未知目标版本、引擎或账号仍会阻止安装。

只有全部词条都具备可表达的拼音时，才能导出需要拼音的常规文本格式；JSON / TSV 档案可保留未核对记录。高级文件工具需明确选择「闪电说」格式，日期标题或无标题 Markdown 不会被自动猜作词典。

### 实际格式与保留规则

以下样例由闪电说 0.8.1 的真实界面输入人工测试词后生成，退出并重新打开后保持不变。公开[样例文件](../fixtures/shandianshuo-0.8.1-synthetic.md)逐字节保留该结果：

```markdown
# 2026-11-06

词度星舟 → 词渡星舟
OpenAI
重庆
词渡星舟
```

词渡跳过标题和空行；一行一条，支持可选的 `- ` / `* ` 列表前缀。一个 `→` 表示纠错，右侧正确写法成为候选词；左侧错写、原始行及行号保留在档案。重复条目保留，在目标合并阶段再按词语和拼音处理。歧义箭头、表格、链接、代码块等已知不支持语法会拒绝整份导入；不会把坏行悄悄跳过。请使用实际词典文件，不要选通用资料、录音或配置文件。

自动建议使用 macOS 本机转写；只对汉字生成建议，不上传内容。`unpronounced` 标记表示尚未核对，不能进入豆包合并。核对后仍需目标引擎验证拼音映射。来源没有词频，档案中的数值 `1` 只是占位值。

### 已验证与待验证

| 项目 | 结果 |
| :--- | :--- |
| 闪电说 0.8.1 arm64 安装 | macOS 15.7.7 隔离 VM，通过严格签名校验 |
| 真实词典 | GUI 创建 3 个普通词和 1 个纠错规则；重启后 4 条记录和文件哈希一致 |
| 词渡 GUI | 读取 4 条、修改拼音取消勾选、确认 3 条、保存全部 4 条，通过 |
| 原件与 CLI | 原件逐字节保留；CLI 校验迁移包，报告 3 条已核对；缺少豆包时正确拒绝安装 |
| 自动合并 | 已核对 / 未核对分流及目标映射拒绝有合成回归；指定豆包引擎的原有安装路径保持不变 |
| 闪电说来源 → 豆包实际安装、候选、重启 | 本轮未完成；VM 未安装豆包，主机豆包 1.0.3 不在适配范围 |
| 语音识别与纠错效果、云同步、Windows / Intel | 未验证或未支持 |

VM 未配置模型账号或 API Key，不进行语音转写；闪电说显示未配置快速大模型，保存词典仍可使用。没有把保存成功当作语音识别生效。主机未安装闪电说，也未修改主机网络或活动词库。

## English

FlashSay stores preferred spellings and correction rules, without pinyin or frequency. Cidu reads its dictionary locally, suggests Mandarin pinyin, and requires a separate confirmation for every row. The resulting entries use Cidu's existing Doubao migration path. This transfers **pinyin candidates**, not speech-recognition hotwords, automatic correction behavior, learning history, or ranking.

Build Cidu from main and choose **闪电说 → 豆包输入法 → 读取并核对词典**. Select `DICTIONARY.md` at the default path above, its actual location if the workspace was moved, or a copy from another computer. FlashSay does not need to be installed on the destination Mac.

Review names and polyphonic characters carefully. Use lowercase, toneless syllables separated by spaces; use `v` for `ü`. Latin and mixed-script entries have no automatic suggestion. Check each reviewed row; editing its pinyin clears the checkbox. The review is paginated at 50 rows. **保存并继续** saves a private bundle containing the original and every entry, including unchecked entries. At least one confirmation is required; Doubao is not required for this archive step.

The actual 0.8.1 sample above uses a date heading. Headings and blank lines are skipped; duplicates remain. For `incorrect → correct`, only the right-hand spelling becomes a candidate. The original line, line number, and correction source remain in the archive. Unreviewed entries cannot reach the merge step, and reviewed entries must still pass the destination engine's pinyin mapping. Unsupported entries remain in the archive and require explicit acceptance of partial migration. Since the source has no frequencies, the stored value `1` is only a placeholder.

The advanced file tool requires an explicit FlashSay format selection for date-headed or plain Markdown. For the CLI, first save a reviewed bundle in the GUI, then pass its directory to `status --file PATH` or `plan --file PATH`. The CLI checks bundle integrity before reading it. Do not pass raw Markdown as a dictionary with confirmed pinyin.

Testing used FlashSay 0.8.1 on an isolated macOS 15.7.7 Apple Silicon VM. Four synthetic records were saved through the real FlashSay UI and survived restart. Cidu read all four, confirmed three, retained the unchecked fourth, and preserved the original bytes. Its CLI reported matching counts and correctly blocked installation because Doubao was absent. **This source's actual Doubao installation, candidate behavior, and restart persistence remain unverified.** The host's Doubao 1.0.3 is blocked by the existing version gate. No host dictionary or network settings were changed. Speech recognition was not tested and no model credentials were configured.

## 来源 / Sources

- [闪电说官方文档 / Official documentation](https://shandianshuo.cn/docs)
- [官方下载页 / Official download page](https://shandianshuo.cn/download)
- [官方 v0.8.1 发行页 / Official v0.8.1 release](https://github.com/shandianshuo/shandianshuo-releases/releases/tag/v0.8.1)
- [词渡验证记录 / Cidu validation log](VALIDATION.md)

本页的文件格式与行为结论来自上述指定版本的隔离测试，不将其作为未来版本的保证。 / Format and behavior findings come from isolated testing of the stated version, not a guarantee for future releases.
