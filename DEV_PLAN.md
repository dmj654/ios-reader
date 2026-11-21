# 本地阅读器 · 开发计划（依据 PRD.md v1.0）

- 计划版本：v1.0
- 配套文档：`PRD.md`（同目录）
- 工程根：`ios-reader/`，源码目录：`ios-reader/ReaderApp/`
- 基线版本：v1.24.4 / Build 48（CI run 44725123479，已编译通过）
- 出包链路：GitHub Actions 编无签名 IPA → 用户 Sideloadly 自签侧载；Bundle ID 恒为 `com.local.reader.app`

---

## 0. 开发约束与固定流水线

### 0.1 代码约束
- 本机（Windows）无 Xcode，**编译只能靠 CI**；每个里程碑只改一块，避免一次堆多个错误难以定位。
- 每次提交前在工程根运行括号配平自检：`python -u ..\_check_braces.py`，输出 `done`。
- 新增 `.swift` 文件无需改 `project.yml`（`ReaderApp/` 目录递归包含）。
- 每次出包必须同时 bump `project.yml` 的 `CFBundleShortVersionString` 与 `CFBundleVersion`。
- 不回退现有已完成功能：本地阅读、在线抓取、搜索筛选、备份/iCloud/WebDAV、朗读、净化、统计保持可用。

### 0.2 出包流水线（每个里程碑重复执行）
1. 代码改完 → 括号配平自检通过。
2. 刷新 token：`& "C:\Program Files\GitHub CLI\gh.exe" auth token | Set-Content -NoNewline -Path "$env:TEMP\gh_token.txt"`
3. 推送：`cd ios-reader; python -u "$env:TEMP\gh_api_update.py" "<commit message>"`（脚本自动遍历工程目录、跳过 `.git`，输出 `UPDATE_DONE=<sha>`）。
4. 轮询：`& $gh run list --repo dmj654/ios-reader --limit 1 --json databaseId,status,conclusion`，约 4–6 分钟。
5. 失败排查：`& $gh run view <runId> --repo dmj654/ios-reader --log-failed | Select-String "error:"`。
6. 成功后：先删除 `_build/ReaderApp-unsigned.ipa`（否则解压报 file exists）→ `gh run download <runId> --name ReaderApp-unsigned-ipa --dir _build` → 复制为 `本地阅读器-vX.Y.Z-unsigned.ipa`。
7. 校验 plist：Bundle ID / 版本号 / Build 号正确。
8. `present_files` 交付 IPA，等真机验收后再进下一里程碑。

### 0.3 版本规划
| 里程碑 | 版本 | Build | 目标 |
|---|---|---|---|
| M1 导航骨架 | 1.25.0 | 49 | 四 tab 结构落地，主页/发现/搜索/设置通路打通 |
| M2 主页卡片与个性化 | 1.25.1 | 50 | 六张卡片模型、排序/显隐持久化、编辑态交互 |
| M3 卡片数据接入与跳转 | 1.25.2 | 51 | 摘要计数、封面预览、导入按钮、各卡片跳转接通 |
| M4 历史列表页 | 1.25.3 | 52 | 历史关联本地书、倒序展示、继续读、清除记录 |
| M5 联调验收与备份补全 | 1.25.4 | 53 | 对齐 PRD 第 10 节验收清单，备份纳入主页布局，修缺陷 |

---

## 1. M1 · 导航骨架（1.25.0 / 49）

### 1.1 目标
把现有「书架 / 搜索 / 设置」三 tab 改为「主页 / 书架 / 发现 / 搜索」四 tab；设置从主页进入；发现页从搜索页内嵌提为独立 tab。本阶段卡片先用静态占位，不做个性化。

### 1.2 改动文件
| 文件 | 动作 | 内容 |
|---|---|---|
| `Views/RootView.swift` | 改 | `RootTab` 枚举改为 `home, shelf, discover, search`；四个 `TabView` 页签；设置改为主页弹出的 sheet；保留 `readerBook` 全屏阅读覆盖层 |
| `Views/HomeView.swift` | 新增 | 主页占位骨架：标题「主页」+ 右上角「…」按钮 + 静态六行卡片占位 |
| `Views/DiscoverView.swift` | 微调 | 增加 `embedded` 参数；作为独立 tab 时不显示关闭按钮（参照 `SourceSearchView.embedded` 现有写法） |
| `Views/SourceSearchView.swift` | 改 | 移除内部 `SearchMode`（搜索/发现）分支与顶部模式切换条；发现入口交给独立 tab；保留搜索结果、详情、在线阅读全流程 |

### 1.3 实现步骤
1. `RootView`：
   - 新增 `@State private var tab: RootTab = .home`。
   - 页签顺序：HomeView → BookshelfView → DiscoverView → SourceSearchView。
   - HomeView 回调：`onOpenBook` 复用现有 `readerBook` 覆盖层；`onOpenSettings` 弹出 `SettingsView(settings:sources:books:shelf:embedded: true)`。
   - DiscoverView 传 `store: sources`，`onSelect` 行为与现状一致（打开详情 sheet）。
2. HomeView 占位：纵向列表六行（继续阅读 / 本地 / 历史 / 在线书源 / 发现 / 搜索），每行图标 + 标题；右上角「…」触发设置 sheet。
3. SourceSearchView 删除 `mode`、`SearchMode` 枚举、`mode == .discover` 分支和对应筛选段；确认 `selected` → `SourceBookView` sheet 链路不变。
4. DiscoverView 独立展示时去掉顶部关闭/返回类按钮。

### 1.4 验收检查点（对应 PRD 10.1）
- [ ] 启动后底部仅四个 tab：主页、书架、发现、搜索；设置不在底部。
- [ ] 四个 tab 互相切换不白屏、不崩溃。
- [ ] 主页右上角「…」可打开设置页，设置内各项可返回主页。
- [ ] 发现 tab 能拉分类/书单；搜索 tab 关键词搜索结果正常。
- [ ] 书架打开本地书阅读流程不受影响。

### 1.5 风险
- SourceSearchView 内嵌 DiscoverView 拆除时，注意 `selected` 状态与详情 sheet 归属：详情 sheet 挂在搜索 tab 层级，发现 tab 选中条目也要能弹出详情（通过 RootView 统一持有 `selectedSource` 状态，或 DiscoverView 回调上抛）。

---

## 2. M2 · 主页卡片模型与个性化（1.25.1 / 50）

### 2.1 目标
落地卡片数据模型、本地持久化、编辑态拖拽排序与显隐；默认六卡片全部可见、按 PRD 顺序排列。

### 2.2 新增文件与数据模型

**`Models/HomeCard.swift`**
```swift
enum HomeCardID: String, Codable, CaseIterable, Identifiable {
    case continueReading, local, history, sources, discover, search
    var id: String { rawValue }
    var title: String { /* 继续阅读/本地/历史/在线书源/发现/搜索 */ }
    var iconName: String { /* bell / folder / clock / list.bullet / compass / magnifyingglass */ }
}

struct HomeLayout: Codable {
    var order: [HomeCardID]          // 可见卡片顺序
    var hidden: [HomeCardID]          // 被隐藏的卡片
}
```
- 默认值：`order = [.continueReading, .local, .history, .sources, .discover, .search]`，`hidden = []`。

**`Services/HomeLayoutStore.swift`**
- `ObservableObject`，`@Published var layout: HomeLayout`。
- 持久化路径：`Application Support/HomeLayout.json`（纳入备份，见 M5）。
- 方法：`move(from:to:)`、`hide(_:)`、`restore(_:)`、`resetDefaults()`；每次变更落盘（先写临时文件再原子替换，沿用统计文件写法）。
- 首次启动/文件缺失/解码失败时回退默认值。

### 2.3 改动文件
| 文件 | 动作 | 内容 |
|---|---|---|
| `Models/HomeCard.swift` | 新增 | 卡片 ID、标题、图标 |
| `Services/HomeLayoutStore.swift` | 新增 | 布局读写、排序、显隐、持久化 |
| `Views/HomeView.swift` | 改 | 接入 store；非编辑态按 `order` 渲染可见卡片；编辑态拖拽手柄 + 眼睛按钮；底部「完成」；已隐藏卡片恢复区 |

### 2.4 交互细则
- **进入编辑态**：长按任意卡片；卡片出现拖拽手柄，隐藏按钮（眼睛/眼睛Slash）。
- **排序**：拖动手柄上下调整；松手后顺序写入 store。SwiftUI 可用 `List` + `.onMove` 进入编辑态，或自定义拖拽；优先复用系统 `EditMode` 减少自研手势风险。
- **显隐**：点眼睛隐藏进 `hidden`；已隐藏区点眼睛恢复回 `order` 末尾（或上次位置）。
- **退出编辑态**：底部「完成」按钮；非编辑态点卡片才触发跳转（编辑态不响应卡片点击）。
- 杀进程重进后顺序与显隐保持。

### 2.5 验收检查点（对应 PRD 10.1）
- [ ] 默认六卡片全部显示，顺序与 PRD 3.2 一致。
- [ ] 长按进入编辑态，可拖动排序；眼睛可隐藏/恢复。
- [ ] 调整后杀进程重进，布局保持。
- [ ] 已隐藏卡片在恢复区可见，可加回。
- [ ] 清空 `HomeLayout.json` 后回到默认布局。

---

## 3. M3 · 卡片数据接入与跳转（1.25.2 / 51）

### 3.1 目标
每张卡片接上真实摘要数据、预览区和跳转动作；本地卡片「导入」按钮接通文件选择器。

### 3.2 数据接入对照
| 卡片 | 摘要数据来源 | 预览区 | 跳转动作 |
|---|---|---|---|
| 继续阅读 | `shelf.books` 按 `lastReadAt`（缺失回退 `location`/`addedAt`）排序取首本 | 最近一本封面 | 直接打开该本阅读页（复用 `readerBook` 覆盖层） |
| 本地 | `shelf.books.count`（小说/漫画合计） | 最近导入 4 张封面横排；右下角「导入」按钮 | 卡片点击 → 切到书架 tab；按钮 → `DocumentPickerHost.present` + `shelf.importBook(from:)` |
| 历史 | `stats.books` 与书架 UUID 匹配后的数量 | 无 | 切到历史页（M4 接通；本阶段先占位提示） |
| 在线书源 | `sources.enabledSources` 中可用源数量（`searchUnsupportedReason == nil`） | 无 | 切到发现 tab |
| 发现 | 静态入口文案 | 无 | 切到发现 tab |
| 搜索 | 静态入口文案 | 无 | 切到搜索 tab |

### 3.3 改动文件
| 文件 | 动作 | 内容 |
|---|---|---|
| `Views/HomeView.swift` | 改 | 注入 `shelf: BookshelfViewModel`、`sources: SourceStore`、`stats: ReadingStatsStore`；实现摘要计算、封面预览、跳转闭包；导入复用 `DocumentPickerHost` 与 `shelf.importBook` |
| `Views/RootView.swift` | 微调 | 把 `shelf`/`sources` 传给 HomeView；提供 tab 切换闭包（HomeView → RootView 切 tab） |
| `Services/CoverStore.swift` | 复用 | 封面取图沿用现有封面缓存，不新造封面链路 |

### 3.4 实现要点
- 封面预览：取 `shelf.books` 最近导入（`addedAt` 倒序）前 4 本；无封面用格式图标占位。
- 空数据摘要：无在读显示「暂无在读」；本地 0 部显示「暂无」；无源显示「暂无可用源」；不抛错。
- 导入流程与书架一致：多选文件 → 逐个 `importBook` → 导入结果沿用书架现有诊断日志（Home 导入后可跳书架查看）。
- 继续阅读无书时，卡片点击改为跳书架，不做空打开。

### 3.5 验收检查点（对应 PRD 10.1 / 10.3）
- [ ] 继续阅读卡片显示最近一本封面与书名；点击直接进入阅读。
- [ ] 本地卡片显示总数与最多 4 张封面；「导入」可选文件并导入成功，书架可见新书。
- [ ] 在线书源卡片显示可用源数量；点击进发现。
- [ ] 发现、搜索卡片点击切到对应 tab。
- [ ] 无数据卡片显示占位文案，无报错。

---

## 4. M4 · 历史列表页（1.25.3 / 52）

### 4.1 目标
新增 `HistoryView`：按最近阅读时间倒序展示读过的本地书，支持继续阅读与清除单条；第一版不接在线书历史。

### 4.2 数据关联
- 统计记录：`ReadingStatsStore.shared.books: [UUIDString: BookStat]`（含 `lastAt`、`seconds`、`pages`）。
- 书架书目：`shelf.books`（UUID、书名、作者、封面、格式）。
- 关联方式：统计 key 解析为 UUID，匹配 `shelf.books.id`；按 `stat.lastAt` 倒序。
- 统计里有、书架已删的条目：不展示（第一版不做孤立记录保留）。

### 4.3 改动文件
| 文件 | 动作 | 内容 |
|---|---|---|
| `Views/HistoryView.swift` | 新增 | 历史列表：条目封面/书名/作者来源/时间/时长页数；继续阅读；左滑清除 |
| `Models/ReadingStats.swift` | 改 | 新增 `clearBook(id: UUID)`：删除对应统计记录并落盘 |
| `Views/HomeView.swift` | 改 | 历史卡片跳转接通 `HistoryView`（sheet 或 push） |
| `Views/RootView.swift` | 微调 | 历史页所需 `shelf`/`stats` 注入通路 |

### 4.4 条目与操作
- 条目信息：封面（无封面用格式图标）、书名、作者/来源、相对或绝对时间、累计时长（`StatsFormat.duration`）、页数。
- 点击条目：打开对应书阅读页。
- 左滑：删除该条历史记录（调 `stats.clearBook`）；不删书架书目本体。
- 空态：「还没有阅读记录」，附去搜索/导入引导。

### 4.5 验收检查点（对应 PRD 10.4）
- [ ] 读过的本地书出现在历史列表，按最近阅读时间倒序。
- [ ] 条目显示书名、来源、时间、时长/页数。
- [ ] 点条目继续阅读；左滑清除单条后列表更新、重进不恢复。
- [ ] 书架删除某本书后，其历史条目不再出现。

---

## 5. M5 · 联调验收与备份补全（1.25.4 / 53）

### 5.1 目标
对齐 PRD 第 10 节全部验收清单；主页布局纳入备份；修联调缺陷；出最终验收 IPA。

### 5.2 改动文件
| 文件 | 动作 | 内容 |
|---|---|---|
| `Services/BackupStore.swift` | 改 | 备份/恢复清单加入 `HomeLayout.json`（Application Support 目录） |
| 各视图 | 联调 | 按验收清单逐项走查，修布局、跳转、空态、刷新问题 |
| `project.yml` | 改 | 版本 1.25.4 / Build 53 |

### 5.3 联调走查清单（逐条对应 PRD 10）
**导航主页**
- [ ] 四 tab 齐全；设置不在底部。
- [ ] 六卡片默认顺序/显隐正确；编辑态排序/隐藏/恢复可用；持久化生效。
- [ ] 主页「…」进设置；本地导入按钮可用；空态占位正确。

**书架阅读**
- [ ] 四类格式导入显示正确；下拉刷新、更新角标正常。
- [ ] 阅读页翻页/目录/书签/搜索/朗读可用；外观设置即时生效并保持。

**在线链路**
- [ ] 发现分类浏览 → 详情；搜索关键词、作者筛选、精确开关生效。
- [ ] 详情目录加载；在线阅读正文/图正常；上下章、目录、预载、离线缓存可用。
- [ ] 在线页与本地页主题/字号/行距/段距/字体/加粗/简繁/胶囊工具条一致。

**历史与数据**
- [ ] 历史倒序、继续读、清除单条正常。
- [ ] 备份文件含书架/书签/书源/净化/统计/字体/主页布局；恢复后回来。
- [ ] iCloud、WebDAV 各完成一次上传下载还原；缓存目录不在备份包。

**工程出包**
- [ ] CI 编译通过；IPA 的 Bundle ID = `com.local.reader.app`，版本/Build 递增。
- [ ] 侧载后各页面可打开，无白屏崩溃。

### 5.4 备份补全细节
- `BackupStore` 现有 `addFile`/`write` 机制扩展到 Application Support 目录（与 `stats.json` 同路径基）。
- 恢复后 `HomeLayoutStore` 重新读盘刷新主页。

---

## 6. PRD 功能追溯表

| PRD 第 8 节必做项 | 落地里程碑 |
|---|---|
| 四 tab 导航、设置进主页 | M1 |
| 六卡片默认展示 | M2 |
| 排序/显隐持久化、编辑态 | M2 |
| 主页设置入口 | M1 |
| 本地卡片封面预览 + 导入按钮 | M3 |
| 本地四类格式阅读、书架进度/角标 | 沿用基线，M5 走查 |
| 本地阅读外观与工具能力 | 沿用基线，M5 走查 |
| 发现分类/榜单浏览 | M1 提级，M5 走查 |
| 搜索跨源、作者筛选、精确开关 | 沿用基线，M5 走查 |
| 详情目录、在线阅读、预载、离线缓存 | 沿用基线，M5 走查 |
| 在线/本地阅读外观与工具条统一 | 沿用基线，M5 走查 |
| 历史列表（本地书） | M4 |
| 书源管理、净化规则、统计查看 | 沿用基线，M5 走查 |
| 备份/恢复/iCloud/WebDAV | 沿用基线；主页布局 M5 纳入 |
| 规则引擎与 JS 表达式/ajax 桥 | 沿用基线，不在本计划改动 |

---

## 7. 风险、预留与不做项

### 7.1 已知风险与对策
| 风险 | 对策 |
|---|---|
| 发现/搜索详情 sheet 归属在拆除内嵌模式后失效 | M1 先把 `selectedSource` 状态上提到 RootView，两个 tab 共用同一详情弹层 |
| 自定义拖拽排序手势与列表滚动冲突 | 优先用系统 `EditMode` + `onMove`，不自研长按拖拽 |
| 历史统计 key 与书架 UUID 匹配失败 | 匹配不到的统计记录不展示；保留 `clearBook` 清理入口 |
| 备份恢复后主页布局不刷新 | 恢复流程触发 `HomeLayoutStore.reload()`（参照统计 `reload()`） |

### 7.2 本计划不包含（PRD 第 9 节）
- 推荐流/榜单推送、账号体系、社区评论打分。
- Word/RTF/有声书播放器；Android。
- 在线书阅读历史；jsoup DOM 绑定、Cookie 罐、AES 解密；卷分组多层目录拆分。
- 主页卡片自定义配色、尺寸、组件混搭。

### 7.3 后续迭代候选（验收后按反馈排期）
1. 在线书阅读历史接入。
2. jsoup DOM 包装与 Cookie 罐，扩大可读书源范围。
3. 卷分组目录自动拆分。
4. 主页卡片更多样式与自定义能力。

---

## 8. 开工顺序

1. 先做 **M1 导航骨架**，出 1.25.0 IPA 验收四 tab 通路。
2. 验收通过后进 **M2 卡片模型与个性化**。
3. **M3 数据接入跳转** → **M4 历史页** → **M5 联调备份**。
4. 每个里程碑独立出包、独立真机验收；上一版未验收不堆叠下一版改动。
