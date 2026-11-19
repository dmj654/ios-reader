# 本地阅读器 · iOS Reader

纯本地 iOS 阅读器。不登录、不联网、不上架，自己装自己用。

## 功能（v0.3）

| 格式 | 支持情况 |
|---|---|
| TXT | ✅ 自动识别 UTF-8 / GBK / GB18030 / BIG5 编码，自动按「第 X 章」分章 |
| EPUB | ✅ 读 container.xml + opf，按 spine 顺序抽正文，自动取书名作者 |
| PDF | ✅ PDFKit 单页阅读，进度记忆 |
| CBZ / ZIP 漫画 | ✅ 自动按文件名排序，逐页浏览，双指缩放 |

- 阅读设置：字号（13–30）、行距、4 种背景主题（米黄 / 纯白 / 护眼 / 夜间）、翻页方式
- 手势：左 1/3 上一页，右 1/3 下一页，中间点一下呼出菜单
- 目录跳转（TXT/EPUB）、进度条拖动、阅读进度自动保存
- 书架：长按删除，进度条直接显示在封面上
- 支持「文件」App 里「用其他应用打开」直接导入

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
2. **直接放文件夹**：把书拖进「文件」App → 我的 iPhone → 本地阅读器 → 放进去就行
   App 每次启动、切回前台、下拉刷新都会自动扫描并归位，不需要再点 `+`
3. **数据线**：连电脑 → Finder/iTunes 找到「本地阅读器」→ 拖进文稿目录

> v0.3 起，App 会同时扫描 `Documents/` 根目录和 `Documents/Books/`，
> 通过「文件」App 或数据线放进来的书会被自动搬到 `Books/` 并加入书架。

## 已知限制

- EPUB 只抽纯文本，不渲染图片和复杂样式（图片版 EPUB 会只剩文字）
- 漫画没有预读，快速连翻会有一两帧白屏
- 搜索、书签、笔记、自定义书源还没做

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
