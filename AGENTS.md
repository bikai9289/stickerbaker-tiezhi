# AGENTS.md

本文件是本仓库给 Codex/自动化代理的项目级工作说明。后续所有改动都必须先读本文件，再结合当前真实代码、Git 状态、OpenSpec 状态和 ops 任务状态执行。

## 协作语言

- 默认使用中文与用户沟通，包括进度更新、问题说明、OpenSpec 报告、验证结论和最终回复。
- 代码标识符、命令、路径、环境变量名、错误码、接口字段名保持原文，不强行翻译。
- 用户明确要求英文或其他语言时，按用户要求处理。

## 项目概览

- 项目名称：StickerBaker / AI Sticker Maker。
- 技术栈：Elixir、Phoenix 1.7、Phoenix LiveView、Ecto/PostgreSQL、Tailwind、esbuild。
- 业务定位：在线 AI 贴纸生成工具，支持文本生成贴纸、头像/人像转贴纸、贴纸历史、搜索、下载、SEO 落地页、账号与积分、支付与退款。
- 核心外部服务：
  - Replicate：默认图片生成与 prompt moderation。
  - OpenAI Images：可通过 `IMAGE_PROVIDER=openai` 切换生成链路。
  - Tigris/S3：生成图、源图和媒体文件存储。
  - Stripe：默认支付提供商。
  - Creem：可选支付提供商。
  - Sentry、SMTP：生产监控与邮件能力。
- 生产域名相关配置集中在 `config/runtime.exs`，默认主域包含 `ai-sticker-maker.com`。

## 重要目录

- `lib/sticker/`：业务上下文与核心逻辑。
  - `accounts.ex`：账号、积分、匿名/注册用户关联。
  - `predictions.ex`：贴纸生成、批量生成、限流、取消、重试、收藏、退款兜底。
  - `payments.ex`：支付计划、Checkout、webhook 校验、入账、退款。
  - `openai_image.ex`、`image_safety.ex`、`image_upload.ex`：OpenAI 生成、安全审核、上传处理。
- `lib/sticker_web/`：Web 层。
  - `router.ex`：路由入口。
  - `live/home_live.*`：首页生成器、上传、人像贴纸、展示区。
  - `live/account_live.*`、`history_live.*`、`batch_live.*`、`search_live.*`：用户工作台、历史、批次、搜索。
  - `controllers/replicate_webhook_controller.ex`：Replicate moderation/generation webhook。
  - `controllers/stripe_webhook_controller.ex`、`creem_webhook_controller.ex`：支付 webhook。
  - `controllers/page_html/`：SEO 与静态页面。
- `priv/repo/migrations/`：数据库迁移。
- `priv/static/images/`：静态图片与展示素材。
- `assets/css/app.css`、`assets/js/app.js`：前端样式与脚本入口。
- `docs/`：产品、SEO、分析漏斗和设计文档。
- `doc/ui-v1.html`：静态 UI 参考稿，不等同于运行时代码。
- `ops/`：本仓库的 Codex 项目运维队列和报告系统，不是产品运行时队列。
- `openspec/`：本仓库 OpenSpec 变更与规格目录；该目录被 `.gitignore` 忽略，不能只靠 `git status` 判断其状态。

## 本地开发

- 常用初始化：`mix setup`。
- 复制环境文件：`cp .env.copy .env`，但必须先检查并移除或轮换任何真实密钥。
- 启动服务：`mix phx.server` 或 `iex -S mix phx.server`。
- 默认本地地址：`http://localhost:4000`。
- 本地 Replicate webhook 需要公网 HTTPS 回调，通常使用 `ngrok http 4000` 并配置 `NGROK_URL`。
- 测试数据库默认读取 `DB_USERNAME`、`DB_PASSWORD`、`DB_HOST`，无值时使用 `postgres/postgres/localhost`。

## 常用验证命令

- 基础状态：`git status --short --branch`。
- 文件检索：优先使用 `rg` 和 `rg --files`。
- 编译检查：`mix compile`。
- 全量测试：`mix test`。
- 指定测试：`mix test path/to/test.exs`。
- 格式化检查或修复：`mix format`。
- 静态资源构建：`mix assets.build`。
- 生产静态资源构建：`mix assets.deploy`。
- OpenSpec 列表：`openspec.cmd list --json`。
- OpenSpec 状态：`openspec.cmd status --change "<change-name>" --json`。
- ops 任务检查：读取 `ops/README.md` 和 `ops/rules/*.md`，再看 `ops/queue/*.md`。

如果某个命令因本机依赖、数据库、网络、凭据或外部服务不可用而失败，必须记录：执行的命令、失败原因、是否阻塞、剩余风险和建议下一步。

## 敏感信息规则

- 不得把任何密钥、token、cookie、私钥、数据库连接串、webhook secret、SMTP 密码写入回复、报告、提交信息或文档。
- 可引用环境变量名，例如 `REPLICATE_API_TOKEN`、`OPENAI_API_KEY`、`STRIPE_SECRET_KEY`、`STRIPE_WEBHOOK_SECRET`、`CREEM_API_KEY`、`CREEM_WEBHOOK_SECRET`、`AWS_ACCESS_KEY_ID`、`AWS_SECRET_ACCESS_KEY`、`BUCKET_NAME`、`DATABASE_URL`、`SECRET_KEY_BASE`、`ADMIN_USERNAME`、`ADMIN_PASSWORD`。
- 当前仓库的 `.env.copy` 可能包含疑似真实 token。读取时只用于确认变量结构，不得复制值；如发现真实密钥已暴露，应提醒用户轮换。
- 生产访问、生产配置、远程命令、部署、数据库变更、支付配置、密钥操作必须先征得用户明确同意。

## 远程服务器操作规则

- 用户提供的线上排查目标为腾讯云服务器：
  - 主机：`43.173.94.85`
  - SSH 用户：`ubuntu`
- 当用户要求处理线上问题、部署问题、服务异常、环境配置、进程状态、日志排查或远程验证时，默认优先把这台服务器作为目标环境来核查真实状态，而不是只在本地猜测。
- 远程操作前必须说明将要执行的目标和风险；涉及重启服务、修改配置、安装依赖、变更数据库、部署、清理文件、开放端口等操作时，必须先获得用户明确同意。
- 服务器密码、私钥或其他登录凭据不得写入 `AGENTS.md`、报告、提交信息或任何仓库文件；需要登录时通过当前会话临时使用用户已授权的凭据，或请用户以安全方式提供。
- 远程排查完成后必须回报：执行的关键命令、观察到的真实状态、是否修改了服务器、残余风险和下一步建议。

## Git 与文件边界

- 不要还原用户已有改动。开始修改前先看 `git status --short --branch`，只处理本次任务相关文件。
- 当前 `.gitignore` 忽略了 `/ops/`、`/openspec/`、`/.codex`、`/doc/`、`/deps/`、`/_build/`、`.env` 等目录或文件；被忽略目录的真实状态需要直接检查磁盘或用对应工具验证。
- 不要执行破坏性命令，例如 `git reset --hard`、强制推送、删除数据、迁移回滚，除非用户明确要求。
- 用户要求提交、推送、归档、部署时，必须先确认预期范围，再执行并验证结果。

## OpenSpec 强制完整性检测规则

使用任何 OpenSpec 技能或执行 OpenSpec 相关工作时，默认自动执行全套功能完整性检测，缺一不可：

1. 接口参数完整性：必选参数、可选参数定义完整，无遗漏、无错配。
2. 请求/响应结构完整性：字段齐全、类型正确、注释完整、无缺失字段。
3. 异常场景完整性：参数非法、空值、超限、过期、权限不足、外部依赖不可用等场景全覆盖。
4. 错误码完整性：所有异常场景都有专属错误码或明确用户提示文案。
5. 业务逻辑完整性：业务流程闭环，无断裂逻辑、无未处理分支。
6. 边界场景完整性：极值、空数据、重复请求、重复 webhook、异常入参、并发/幂等场景全部覆盖。
7. 规范代码一致性：代码实现与 OpenSpec 规范完全匹配，无实现遗漏、无私自改动。
8. 兼容性完整性：迭代改动不破坏原有正常业务逻辑、路由、数据库迁移、支付和生成链路。

检测不通过时，必须输出：完整性检测报告、缺失清单、问题原因、一键修复方案。完成修复或明确等待用户决策后，才能结束本次开发流程。

## OpenSpec 工作方式

- 开始 OpenSpec 工作前，先运行或读取 `openspec.cmd list --json` 确认当前 change 状态。
- 如果只有一个活跃 change 且用户没有指定名称，可以自动选择，但必须说明 `Using change: <name>`。
- 如果 change 已经 `complete` 或任务全完成，不要继续当作 apply-mode 改代码；应转为归档、复核或新 change 规划。
- 产品行为、路由/页面行为、分析事件契约、认证、账号、支付、积分、退款、隐私、SEO 落地页、公开 API、请求/响应或错误处理变化，都必须通过 OpenSpec 提案或变更推进。
- 诊断或规划任务发现需要实现时，应把发现、影响和推荐 change 名写入报告，然后等待用户确认。
- 归档 completed change 前，必须确认 delta spec 是否需要同步到 `openspec/specs/`，并在归档后再次用 `openspec.cmd list --json` 验证状态。

## ops 队列规则

- `ops/` 是本仓库给 Codex 使用的任务队列、规则、报告和复核区。
- 接手 ops 任务时，必须先读 `ops/README.md` 和 `ops/rules/*.md`。
- 只执行任务文件描述的范围；`requires_user_input: true` 时先问用户。
- 诊断、规划、报告、复核和验证可以留在 ops 内；代码或产品行为变化必须升级到 OpenSpec。
- 任务完成前必须有验证证据：命令/检查名、目标路径或 URL、结果、关键输出摘要、残余风险。
- 默认在 `review_required` 停下，除非任务文件明确允许自动完成。

## 业务关键路径

- 首页文本生成：
  - 路由 `/` 进入 `StickerWeb.HomeLive`。
  - 表单事件 `save` 消耗用户积分，创建 `Prediction`，再异步启动 moderation。
  - 默认生成链路为 `Predictions.moderate/3 -> ReplicateWebhookController -> Predictions.gen_image/3 -> Replicate/OpenAI -> webhook/storage -> PubSub broadcast`。
- 人像转贴纸：
  - `HomeLive` 使用 LiveView upload，限制 JPG/PNG 和 8 MB。
  - 未登录用户只能看到注册/登录引导，登录后上传会触发安全审核、源图保存、积分扣减和生成。
  - 人像贴纸默认不公开展示。
- 积分与限制：
  - 生成前检查用户积分、24 小时生成限制、同时进行中的生成限制。
  - 失败、取消或创建失败时要注意退款/积分返还逻辑。
- 支付：
  - `/pricing` 展示付费入口，`POST /checkout` 创建 Checkout。
  - Stripe webhook 处理 `checkout.session.completed` 和 `charge.refunded`。
  - webhook 必须保持签名校验、幂等记录、金额/币种/plan/credits/user 校验。
  - 退款逻辑涉及积分扣回、余额不足人工复核、部分退款人工复核。
- SEO 页面：
  - 长尾页面集中在 `PageController` 和 `controllers/page_html/*.html.heex`。
  - 改 SEO 文案、canonical、sitemap、metadata、分析事件时要同步验证路由、模板和测试。

## 前端与产品要求

- 这是工具型 SaaS 页面，首屏应优先展示可用生成器，而不是纯营销落地页。
- UI 改动要保持工具可用、信息清晰、移动端不重叠、按钮文字不溢出。
- 不要为了装饰引入与贴纸/生成/账号/支付无关的大型视觉重构。
- LiveView 模板和 CSS 改动后，至少检查相关 route、关键交互和响应式布局风险。
- `doc/ui-v1.html` 可作为视觉参考，但实际实现必须以 `lib/sticker_web/**`、`assets/**` 和路由为准。

## 测试与完整性期望

- 改业务逻辑时优先补或更新对应测试：
  - `test/sticker/*`：业务上下文。
  - `test/emoji_web/live/*`：LiveView 交互。
  - `test/emoji_web/controllers/*`：controller 和 webhook。
- 支付、积分、webhook、退款、生成失败、取消、重试、权限、隐私、SEO 路由属于高风险区域，不能只做静态阅读后声称完成。
- 数据库 schema 或 migration 改动必须考虑已有数据兼容、回滚风险和测试环境迁移。
- 对外部服务调用应优先用已有封装和测试替身，不要在测试中依赖真实网络或真实密钥。

## 完成回复要求

- 最终回复用中文，简明说明改了什么、验证了什么、仍有什么风险。
- 如果没有运行测试或某项验证不可用，必须直接说明原因。
- 引用本地文件时给出路径，必要时说明关键行或关键段落。
