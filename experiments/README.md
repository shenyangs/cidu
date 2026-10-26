# 本机研究工具

这些是本次受授权实验的源码，不是通用安装器。个人词库和框架不分发。

`doubao_merge.py` 从环境变量 `CIDU_EXPERIMENT_DIR` 指定的私有目录读取已备份的 initial-usr.dat、原生映射 native-map.json，以及上一级的完整 JSON 档案；生成独立候选文件，不写实际输入法目录。默认位置为 `~/Library/Application Support/Cidu/live-merge`。输入文件需先经当前进程与账号路径核对。

`native_probe.mm` 仅在装有本次豆包框架的 Apple Silicon Mac 上用于隔离副本加载、编码映射和候选检查。传入词库路径必须是隔离副本，因为引擎可能创建或更新辅助文件。框架可能随版本变化；调用签名来自本机静态元数据。未配置账号或调用云同步接口。

产品化前还需要自动发现版本、可靠的输入边界、可审计事务安装与恢复、跨版本测试和同步验证。实际实验结果见 ../docs/VALIDATION.md。
