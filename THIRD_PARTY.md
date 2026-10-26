# Third-party notices

`Sources/Core.swift` 中的豆包头部与记录解码实现参考了 [taxueseek/ime-lexicon](https://github.com/taxueseek/ime-lexicon) 的 `skill/scripts/doubao.py`、`codec.py` 和格式说明。Swift 实现添加严格区间检查并仅用于只读预检。

Copyright (c) 2026 ime-lexicon contributors. MIT License. 完整许可见 [LICENSE.ime-lexicon](LICENSE.ime-lexicon)。

研究过的 studyzy/imewlconverter 和 nopdan/rose 使用 GPL-3.0，本项目没有复制、链接或分发其代码。用户提供的 Windows EXE 只用于本地研究，其字节码与常量表不属于开源发行内容。

0.2 搜狗 TXT 结构参考 studyzy/imewlconverter 的 SougouPinyinImporter.cs / SougouPinyinExporter.cs（格式研究，未复制实现）；Rime 结构参考官方 RimeWithSchemata 文档：https://github.com/rime/home/wiki/RimeWithSchemata 。新 Swift 格式读写代码独立实现。

0.3 QQ / 谷歌文本协议研究：
- https://skin.qq.pinyin.cn/help/pinyin05.html （官方导入功能说明）
- https://github.com/studyzy/imewlconverter/tree/master/src/ImeWlConverter.Formats/QQPinyin
- https://github.com/studyzy/imewlconverter/tree/master/src/ImeWlConverter.Formats/GooglePinyin

仅核对行结构与编码，Swift 适配独立实现，未复制第三方实现或测试词库。微软 DCTX 的声调要求研究后未纳入支持范围。

## 0.4 Mac 适配

- Apple 官方文本替换导入/导出：https://support.apple.com/zh-cn/guide/mac-help/mchl2a7bd795/mac
- PLIST 的 phrase / shortcut 键核对：https://github.com/kyan001/UserDefinedPhraser/blob/master/phrasers/macphraser.py （只研究文件结构，使用 Foundation 独立实现）
- 微软 UDP 结构核对：https://github.com/studyzy/imewlconverter/blob/master/src/ImeWlConverter.Formats/Win10Ms/MsChxUdpExporterBase.cs （只研究格式，不复制或链接 GPL 实现）
- 微信键结构参考 taxueseek/ime-lexicon 的 wetype.py（MIT，同上许可）；未使用其原始字节扫描或日志注入实现。
- Google LevelDB 1.23：BSD-3-Clause，源码 https://github.com/google/leveldb/tree/1.23 ，许可 `vendor/leveldb-1.23/LICENSE` 与 AUTHORS。
- Google Snappy 1.2.1：BSD-3-Clause，源码 https://github.com/google/snappy/tree/1.2.1 ，许可 `vendor/snappy-1.2.1/COPYING`。

后两项随源码原样提供、静态链接；许可证同时复制到应用 Resources/Licenses。CMake 包装脚本由本项目提供，未修改上游实现。
