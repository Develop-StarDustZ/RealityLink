# Security policy

## Supported versions

安全更新目前只覆盖最新发布版本。`main` 分支可能包含尚未发布的改动。

## Reporting a vulnerability

请不要为未修复漏洞创建公开 Issue。请通过 GitHub 仓库的
**Security → Report a vulnerability** 私密报告功能联系维护者，并提供：

- 受影响版本、操作系统与设备架构
- 复现步骤和预期影响
- 是否涉及管理员权限、配置泄露或系统代理无法恢复
- 可行的缓解建议（如有）

维护者应在 7 天内确认收到报告，并在确认修复方案后协调披露时间。

## Sensitive data

节点凭据、分享链接、服务器地址和完整日志可能属于敏感信息。报告问题前
请替换这些字段。不要上传 RealityLink 用户数据目录、配置导出或真实节点截图。

RealityLink 启动 TUN 时会请求管理员授权。任何扩大管理员命令范围、改变
系统代理或持久化特权进程的修改都应视为安全敏感变更。
