# victor_wiki：部署与维护

访问地址：http://192.168.30.2:8090 。本 fork 采用 WeKnora 完整服务端，不使用 Lite 模式。前端名称与标识统一由 `frontend/src/config/branding.json` 管理；`logoUrl` 留空时显示名称文字，设置为 `/branding/logo.svg` 等本地路径后，将图片放入 `frontend/public/branding/` 并重新构建。

已建立本地管理员 `victor@local.invalid`，随机初始密码只保存在 `/home/lenovo/victor_wiki/secrets/account.json`。公开注册已关闭；需要其他账户时由管理员添加或邀请。

联想使用 DHCP；服务自检使用回环地址，Web 服务监听本机 IPv4 接口的 8090 端口。若希望访问地址长期固定，可在路由器为该电脑保留当前 IP。

## 本地目录

- `/home/lenovo/victor_wiki/current`：正在运行版本的源码入口。
- `/home/lenovo/victor_wiki/repo`：Git 主仓库，配置 origin（个人 fork）和 upstream（官方）。
- `/home/lenovo/victor_wiki/secrets`：部署密码、JWT 密钥和仅限本 fork 的 GitHub 部署密钥，不提交 Git。
- `/home/lenovo/victor_wiki/logs`：构建、下载、启动和更新日志。
- `/data1/victor_wiki`：文档、PostgreSQL、Redis、Neo4j、本地模型、备份与打包文件。

## 启动与检查

安装时将 lenovo 加入 docker 组，重新登录 SSH 后生效。所有运行操作均通过脚本完成：

```bash
cd /home/lenovo/victor_wiki/current
bash scripts/victor-start.sh
bash scripts/victor-compose.sh ps
bash scripts/victor-smoke.sh
bash scripts/victor-backup.sh
bash scripts/victor-stop.sh
```

通过 systemd 启动：`sudo systemctl start victor-wiki`。日志位于上述 logs 目录和 `journalctl -u victor-wiki`。

默认对话模型选用非思考模型，以减少纯 CPU 的交互等待。模型为本机 Ollama 的 qwen2.5:3b 与 bge-m3（1024 维）。应用使用容器内部端点，不配置云模型、云解析或云端追踪。外网仅用于下载公共依赖、镜像、模型和同步公共源码。图谱使用本地 Neo4j；数据库和模型端口不发布到局域网。Neo4j 默认匿名使用统计已关闭。

Ollama 固定为 `0.40.18`，启用 `OLLAMA_NO_CLOUD=true`，健康检查通过后应用才启动。

本地模型的初次安装通过 `bash scripts/victor-models.sh` 完成：独立的临时下载容器仅下载公开模型，使用机器已有代理；下载后删除该容器，业务模型服务不带代理运行。

## 定制与构建

```bash
cd /home/lenovo/victor_wiki/current
bash scripts/victor-build.sh
```

前端在联想电脑使用锁文件安装依赖、编译并打包为 `victor-wiki/frontend:<版本>-<提交>`。后端、DocReader 和基础服务使用对应官方镜像，均保存在本地 Docker 中；GitHub 工作流不执行编译或接触资料；同步工作流同时禁用继承的其他工作流，只保留源码同步。

修改品牌配置并验证后提交个人分支。部署配置保存于独立 override，避免修改官方 Compose。首次部署使用 v0.9.1，升级时由 VERSION 和官方 release 确定上游镜像版本。

## 官方更新

GitHub 的 `victor_wiki upstream sync` 工作流每日同步官方 main 到 fork main。个人定制保存在 `personal/victor-wiki`，作为 fork 默认分支。

联想电脑的 `victor-wiki-update.timer` 每天北京时间 04:30 起检查稳定版，随机延迟不超过 15 分钟；错过执行时间后会补跑。更新在独立 worktree 合并、构建，冲突或失败时保留当前服务。PostgreSQL、Neo4j 镜像变化时停止自动升级，先进行迁移评估。

构建与镜像下载完成后进入短暂维护：停止应用写入，备份数据库、文件、Redis、Neo4j 、部署环境和 secrets，再升级及检查。失败时恢复升级前状态。旧源码、旧镜像和备份保留，不自动清理。

```bash
systemctl list-timers victor-wiki-update.timer
journalctl -u victor-wiki-update.service
bash scripts/victor-update.sh --check-only
```

若同版本候选目录已存在，脚本停止并提示路径。先查看对应 worktree 和 update.log，再决定继续或处理冲突，不自动覆盖候选目录。

## 手动恢复

进入备份 `source-commit` 对应的旧 worktree，然后执行 `bash scripts/victor-restore.sh <备份目录>`。脚本验证源码提交和备份格式，恢复后启动旧版；若源码不匹配则停止。


更新失败时先检查 update.log 和 `backups/pre-<版本>-<时间>`。备份包含 `database.dump`、`files.tar`、`neo4j.tar`、`redis.tar`、`secrets.tar`、部署环境、源码提交和镜像列表。恢复前停止应用及相关写入，数据库使用 pg_restore，文件及两个状态目录恢复对应 tar；恢复 deployment.env 后，将 current 指回备份 source-commit 对应的旧 worktree，再启动旧版。不得直接把升级后的数据库交给旧版程序运行。

## 验收范围

验收使用独立的合成资料：页面品牌、登录、上传、解析、检索、引用、本地回答，以及重启后数据持久性。解析质量仍应使用实际资料抽样评估；不把一种格式的成功扩大为所有扫描件、表格和公式均准确。

## 维护身份与离线包

日常验收使用 `secrets/acceptance-api-key`，无需管理员密码。其能力为检索和问答，空间范围为整个当前空间；请按私密凭据保护。备份同时保存数据库与 secrets，恢复时两者一起恢复。

执行 `bash scripts/victor-package.sh`，在 `/data1/victor_wiki/artifacts/` 生成当前提交完整源码与提交号、服务镜像和公开模型权重包；模型包只包含 `models/`，不包含 Ollama 私钥。部署配置和账号凭据从受保护备份单独恢复。

更新实际验证覆盖当前稳定版检查、候选保护、备份恢复和维护身份。未来版本的迁移与合并结果由当次检查决定，失败时保留当前版本。

## 2026-11-26 安装验收

已验证合成 Markdown 解析、原文 ID 检索、简短正确的本地回答与聊天来源引用；回答为“根据资料，星河计划的资料复查周期为21天。”。完整数据库、文件、Redis、Neo4j 与 secrets 备份恢复后，同一维护 API Key 检索和问答再次通过。全部容器健康，systemd 主服务已启用。纯 CPU 的完整知识问答约需数分钟，实际资料质量仍需抽样检查。

GitHub 源码同步已真实运行成功；继承的13个构建/发布工作流已关闭。本机每日检查已启用并实际执行，确认 v0.9.1 已为当前稳定版；未模拟尚未发布版本的数据库迁移。
