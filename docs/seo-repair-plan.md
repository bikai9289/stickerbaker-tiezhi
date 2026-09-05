# ai-sticker-maker.com 修复文档（SEO + 技术债）

生成时间：2026-09-05
数据来源：哥飞 SEO AGENT 分析（domain overview / GSC 截图 / 关键词难度精评）+ 本仓库代码与线上实测核实

---

## 0. 结论先行

网站**产品和页面质量没有硬伤**（首页 On Page 93 分、SSR 直出、10 个子页面都有完整结构化数据）。真正卡住排名的是三件事，且全部可在 2~4 周内动手：

1. **外链几乎为零**（DR 0）——`ai sticker maker` 这个词只需 10~25 个引用域就能进前十，现在是 0。
2. **缺一个 `ai sticker generator` 独立承接页**——这个词第 4 名是个 DR17、12 个月的弱站，你的产品力比它强，但你现在没有页面去抢这个位置。
3. **首页有实打的技术债**：无结构化数据、`og:image` 用相对路径、圣诞季节内容窗口没接（11~12 月搜索量会从 ~600 冲到 27,100~60,500，现在 9 月不动手就来不及了）。

以下按 P0（本周必须）/ P1（两周内）/ P2（长期）列出，每一条都标注了「现状实测」「为什么」「怎么改」「涉及文件」。

---

## P0 — 本周必须做

### P0-1. 首页补 `og:image` 绝对地址

- **现状实测**：线上首页 `<meta property="og:image" content="/og.webp">`，是相对路径。
- **为什么**：分享到微信/Twitter/Slack 等抓取 OG 数据的爬虫通常不会自动拼接域名，相对路径大概率解析失败，分享卡片没有配图，白白损失社交分享的点击率。
- **怎么改**：在 SEO 配置里把 `og:image` 换成绝对 URL，例如 `https://ai-sticker-maker.com/og.webp`。
- **涉及文件**：`lib/sticker_web/components/layouts/root.html.heex`（`<SEO.juice conn={@conn} config={StickerWeb.SEO.config()} .../>` 这一行调用的 SEO 配置模块，需要找到 `StickerWeb.SEO.config()` 定义处，把 image 字段改成带 host 的绝对地址，或在渲染时用 `SEO.OpenGraph` 的 `url()` helper 拼接 `conn` 的 scheme+host）。

### P0-2. 首页补结构化数据（FAQPage 至少）

- **现状实测**：首页源码里没有任何 `<script type="application/ld+json">`，而 10 个子页面（`/face-to-sticker`、`/custom-sticker-maker` 等）全部有 `BreadcrumbList + HowTo + FAQPage`。原因是首页走 `HomeLive`（LiveView），而结构化数据目前只在 `PageController` 里通过 `assign_structured_data/4`（`lib/sticker_web/controllers/page_controller.ex:432`）注入；`HomeLive` 从没设置过 `:structured_data` assign，`root.html.heex:13` 的 `for schema <- List.wrap(assigns[:structured_data] || [])` 于是渲染空。
- **为什么**：首页是全站权重最高、承接搜索流量最多的页面，恰恰漏了结构化数据，等于把最值钱的页面的 FAQ 富媒体摘要机会让给了别人。
- **怎么改**：在 `HomeLive` 的 `mount/3` 或 `handle_params/3` 里 `assign(:structured_data, [...])`，复用 `page_controller.ex` 里已有的 `faq_schema/1`、`breadcrumb_schema/2` 逻辑（可以抽成公共 module，例如 `StickerWeb.StructuredData`，两处都调用，避免重复代码）。FAQ 内容直接用首页现有的 5 条 FAQ 文案。
- **涉及文件**：`lib/sticker_web/live/home_live.ex`（新增 assign）、`lib/sticker_web/controllers/page_controller.ex`（抽公共函数，可选）、`lib/sticker_web/components/layouts/root.html.heex`（渲染逻辑不用改，已经支持）。

### P0-3. 新增 `/ai-sticker-generator` 独立落地页

- **现状实测**：线上访问 `https://ai-sticker-maker.com/ai-sticker-generator` 返回 404；`sitemap.xml` 里也没有这个 URL。而这个词月搜索量 1,600、哥飞版 KD 42.2（中等），第 3 名是老对手 icoloring.ai，**第 4 名是 fastimage.ai —— DR 仅 17、站龄 12 个月、体验分垫底（28 分，停留 9 秒）**，说明这个词的门槛并不高，你的产品质量（首页 On Page 93 分）明显更强，缺的只是一个专门页面。
- **为什么**：现在这部分搜索流量被首页（排 90 名开外）和已有子页面稀释、承接不到，等于让给了产品力更弱的竞品。
- **怎么改**：仿照现有 10 个子页面的模式（`PageController` + `assign_structured_data`），新增一个路由 `get "/ai-sticker-generator", PageController, :ai_sticker_generator`，页面内容围绕：
  - H1/标题直接用 "AI Sticker Generator"（而不是变体词）
  - 页面正文强化 **"free" + "no sign up"** 文案 —— GSC 数据显示 `ai sticker generator free`、`ai sticker generator free no sign up` 已经有真实曝光和点击，这是你免登录产品的差异化优势，要写进标题和首屏
  - 配 HowTo + FAQPage + BreadcrumbList 结构化数据（复用现有 helper）
  - 加入 `sitemap.xml`（`PageController.sitemap_xml`）
  - 首页/其他子页面做内链指向这个新页面
- **涉及文件**：`lib/sticker_web/router.ex`（新路由）、`lib/sticker_web/controllers/page_controller.ex`（新 action + 模板 + sitemap 条目）、新增模板文件（可参考 `custom_sticker_maker` 等现有模板结构）。

---

## P1 — 两周内做（抢 11~12 月圣诞季）

### P1-1. 上线 2~3 个「AI + 圣诞」主题落地页

- **数据依据**：`christmas stickers` 类词美国月搜索量从 9 月 ~2,900 一路爬到 11 月 27,100、12 月峰值 60,500；但 `christmas stickers` 本身 KD 50，被 Amazon/Pinterest/Adobe 霸榜，正面打不动，也**不该打**——那批词的搜索意图是「买/下载现成贴纸」，不是「用 AI 生成」，你的工具承接不了这些流量的转化。
- **怎么改**：不要抢 `christmas stickers`，改做「AI + 圣诞」组合长尾词页面，例如：
  - `christmas ai sticker maker`
  - `make christmas stickers with ai`
  - `ai christmas sticker generator`
  这类词竞争小、意图和产品完全匹配（生成意图，不是购买意图）。
- **时间窗口很紧**：Google 收录 + 爬到稳定排名一般要 4~8 周，10 月底前必须上线才能吃到 11~12 月的峰值，现在（9 月初）是最后的动手窗口。
- **涉及文件**：同 P0-3 的模式，新增 1~3 个 `PageController` action + 路由 + sitemap 条目。可复用首页的生成器组件（内链导流回 `/#generator`）。

### P1-2. 外链从 0 破到 10+

- **现状**：DR 0，`ai sticker maker` KD 只有 15.7（极易），前十里 5 个是 Canva/Reddit/Bing/WhatsApp/YouTube 这类"顺路排"的大站内页，**没有一个专门经营这个词的对手**——这是典型的「小站可反超」盘面，但 0 外链就是 0 位置。
- **怎么改（非代码，运营动作）**：
  1. 先免费渠道：AI 工具导航站/目录提交收录（Product Hunt、AI 工具导航类站点）
  2. 客座投稿 / 免费评测博客
  3. 预算允许可买 5~10 条 DR 20~40 的 Guest Post
  - 目标：3~4 周内把引用域从 0 拉到 10~25，这是进 `ai sticker maker` 前十的门票。

### P1-3. 已有子页面内容加厚

- **现状**：`/sticker-maker-online`、`/custom-sticker-maker` 等子页面结构化数据齐全，但正文内容偏薄（约 300~400 词量级），且暂无外链支撑，排不进首页结果。
- **怎么改**：给这几个已被收录但排名靠后的页面补充内容深度（增加使用场景说明、示例 prompt、对比表格等），不需要新建页面，编辑现有模板文案即可。

---

## P2 — 长期，不用现在花力气

- **品牌词护城河**：icoloring 靠 `icoloring ai` 这类品牌词也能吃到几百 ETV，你现在这个阶段还没有搜索量，属于站龄和外链积累到位后自然长出来的东西，现阶段不用专门投入。
- **主题贴纸词（cute/funny/meme/whatsapp stickers）——明确不要碰**：预筛难度显示 0~6，但哥飞版精评实际是 41.5~68.5（中等到困难），第一页被 Amazon/Pinterest/Giphy/RedBubble/Etsy 等平台内页霸占，且这些词的搜索意图是"买/下载现成贴纸"而不是"AI 生成"，就算砸 40~230 个引用域挤进去，来的用户也用不上你的工具，ROI 极差。

---

## 3. GSC 真实数据核对（供参考，需要精确值需重新导出）

用户提供的 GSC 截图口径（最近 3 个月，非精确值，"排名"列显示的具体含义待用户上传 CSV 后二次核实）：

| 指标 | 数值 |
|---|---|
| 总点击 | 15 |
| 总曝光 | 553 |
| 平均 CTR | 2.7% |
| 平均排名 | 40.5 |

关键信号：`ai sticker maker`、`ai sticker generator`、`sticker maker` 三个核心词都已经有曝光，说明 Google 已经开始试探性发放位置（新站爬坡期正常现象），但 0 个词进前 10，和外链为零、内容矩阵薄弱直接对应。

`ai sticker generator free no sign up` 已经有真实点击，排名约 221 位——这是产品差异化最强、意图最精准的词，应在 P0-3 的新页面文案里重点强化，而不是单独开页承接（体量太小，2~10/月）。

---

## 4. 执行清单（可直接转成 Issue / TODO）

- [x] 修 `og:image` 为绝对 URL（P0-1）
- [x] `HomeLive` 补 FAQPage/HowTo 结构化数据（P0-2）
- [x] 新建 `/ai-sticker-generator` 页面 + 路由 + sitemap + 首页内链（P0-3）
- [x] 新建「AI + 圣诞」主题页（`/christmas-ai-sticker-maker`、`/ai-christmas-sticker-generator`）（P1-1）
- [ ] 启动外链建设：目录提交 + 客座投稿 + 少量付费 Guest Post，目标 10~25 条引用域（P1-2，运营动作，不在代码里）
- [x] 给现有子页面（sticker-maker-online / custom-sticker-maker 等）加厚正文内容（P1-3）
- [x] 不做：主题贴纸词（cute/funny/meme/whatsapp/christmas stickers）正面竞争（P2，明确排除）
