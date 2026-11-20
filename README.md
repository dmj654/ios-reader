# 本地阅读器 · iOS Reader

纯本地 iOS 阅读器。不登录、不联网、不上架，自己装自己用。

## 功能（v1.8）

| 格式 | 支持情况 |
|---|---|
| TXT | ✅ 自动识别 UTF-8 / GBK / GB18030 / BIG5 编码，自动按「第 X 章」分章；大文件解析结果有缓存，第二次打开秒开 |
| EPUB | ✅ 读 container.xml + opf，按 spine 顺序抽正文，取书名作者，提取插图（独立成页） |
| PDF | ✅ PDFKit 单页阅读，进度记忆 |
| CBZ / ZIP 漫画 | ✅ 分页翻页 / 竖向滚动两种模式，缩略图目录，双指缩放，自动裁白边，预读缓存 |

- 阅读设置：字号（13–30）、行距、4 种背景主题（米黄 / 纯白 / 护眼 / 夜间）、翻页方式
- 漫画设置：适配（屏幕/宽/高）、方向（左→右 / 右→左）、工具栏（常驻 / 自动隐藏 / 点按）、点按区域、压暗、常亮、预读页数
- 手势：左边缘右滑退出；左 1/3 上一页，右 1/3 下一页，中间点一下呼出工具栏
- 目录跳转、书签、全文搜索、进度条拖动、进度自动保存
- 书架：封面网格 + 分组胶囊 + 搜索 + 四种排序 + 长按重命名/删书/重生成封面
- 书源：原生导入 Legado 书源 JSON，搜书下载到本地（CSS / XPath / JSON / 正则规则，不支持 JS）
- **阅读统计（v1.8）**：自动计时（连续 5 分钟无操作自动暂停）、每日目标环、连续天数、13 周热力图、最近 7 天柱状、读得最多的书排行、复制文字摘要。数据只存本机 Application Support。

## 怎么编译出 IPA（不需要 Mac）

1. 在 GitHub 新建一个 **Public** 仓库
2. 把本目录全部内容推上去
3. 打开仓库的 **Actions** 页，等 `Build IPA` 变绿（约 3–6 分钟）
4. 进这次运行 → 页面底部 **Artifacts** → 下载 `ReaderApp-unsigned-ipa`
5. 解压得到 `ReaderApp-unsigned.ipa`

## 怎么装到 iPhone

用侧载工具配合你自己的证书签名：

- **Sideloadly**（Windows 可用）：手机连电脑 → 拖入 IPA → 填 Apple ID → Start
- **AltStore** / **TrollStore** 也可以

装完到 **设置 → 通用 → VPN 与设备管理** 里信任证书。

## 怎么导书进去

三种方式，任选：

1. **App 内导入**：右上角 `+` → 从「文件」选中文件（可多选）
   - 用的是 UIKit 原生文件选择器（`asCopy` 模式），避开 iOS 18 上 SwiftUI `fileImporter` 多选点「打开」不回调的坑
   - **没有扩展名的文件也能认**：按文件头判断 PDF / EPUB / CBZ / TXT，导入时自动补上扩展名
2. **直接放文件夹**：把书拖进「文件」App → 我的 iPhone → 本地阅读器 → 放进去就行
   App 每次启动、切回前台、下拉刷新都会自动扫描并归位，不需要再点 `+`
3. **数据线**：连电脑 → Finder/iTunes 找到「本地阅读器」→ 拖进文稿目录

> v0.3 起，App 会同时扫描 `Documents/` 根目录和 `Documents/Books/`，
> 通过「文件」App 或数据线放进来的书会被自动搬到 `Books/` 并加入书架。

## 已知限制

- EPUB 只抽纯文本，不渲染图片和复杂样式（图片版 EPUB 会只剩文字）
- 漫画没有预读，快速连翻会有一两帧白屏
- 书源里的 JS 规则（`<js>` / `@js:`）没有引擎可跑，这类源会被标出来并跳过
- 需要登录 / Cookie 的站点搜不到

## v1.9.0 修了什么

- **搜不到书**：原来一千条源会同时发一千个请求，全部堵死超时。现在每批只并发 6 个、每个最多等 12 秒，按「以前搜成功过」优先挑 30 个源（可调 30/60/100/全部），搜完一批就先把结果摆出来
- **规则解析**：修好了 `class.xxx@tag.li` 这种最常用的 Legado 列表规则（原来一律当成取不到内容），另外支持 `id.` 前缀、`!N` 下标、`-id:` 排除前缀、`@textNodes`
- **失败看得懂**：同一个失败原因合并成一条（`×35 网络超时`、`×5 403`…），不再刷上千行
- **千条源管理**：搜索框、分类筛选（全部/小说/漫画/已启用/已停用/规则完整/缺东西）、分组筛选、排序（最近能搜到的优先…）、多选 + 批量启用/停用/删除；每条源显示成功/失败次数和分组

## 工程结构

```
ios-reader/
├── project.yml                 # XcodeGen 配置，自动生成 .xcodeproj
├── .github/workflows/build.yml # GitHub Actions 自动编译出未签名 IPA
└── ReaderApp/
    ├── ReaderApp.swift         # App 入口
    ├── Models/
    │   ├── Book.swift          # 书籍模型
    │   ├── BookText.swift      # 统一文本模型（章节列表）
    │   └── ReadingSettings.swift # 阅读设置持久化
    ├── Services/
    │   ├── TextLoader.swift    # TXT 解码 + 分章
    │   ├── EpubParser.swift    # EPUB 解析
    │   ├── ComicLoader.swift   # CBZ 解压取图
    │   └── TextPaginator.swift # CoreText 分页
    └── Views/
        ├── BookshelfView.swift
        ├── ReaderView.swift    # 按格式分发
        ├── TextReaderView.swift
        ├── PdfReaderView.swift
        ├── ComicReaderView.swift
        ├── SettingsView.swift
        └── PageTextView.swift
```

## 下一步计划

1. 自定义小说源 / 漫画源（订阅 JSON，按规则抓 HTML）
2. 书签 / 笔记 / 全文搜索
3. EPUB 图片渲染、漫画预加载
4. 阅读统计
