> [!CAUTION]
> **⚠️ 重要警告**
> - 刷机、刷入 Magisk 模块可能导致系统无法正常启动，请在操作前审慎考虑，并务必备份重要数据。因操作不当导致的任何系统故障（包括卡开机动画、功能异常等）与模块作者无关。
>
> **📜 免责声明**
> - 本模块按「原样」（AS-IS）提供，作者不对因使用、修改或分发本模块所导致的任何直接或间接损失承担责任。
> - 用户须自行确保所使用的字体文件拥有合法的使用和分发授权，因字体版权引发的一切纠纷由用户自行承担。
> - 使用本模块即表示您已阅读并同意以上条款。

# CJK Font Magisk Module Auto-Builder </br> CJK 字体 Magisk 模块自动构建器

本项目自动检查若干开源 CJK 字体的上游仓库是否有新版本，检测到新版本后自动打包为 Magisk 模块，并发布到 [GitHub Releases](https://github.com/byte-me-labs/advanced-cjk-font-magisk-modules/releases)。刷入生成的模块即可一键换字体，无需手动改任何配置。

原模板出处见文末 **「致谢」**。

## 工作原理

整条流水线分两段：**构建期**（GitHub Actions）与**安装期**（手机上的 `customize.sh`）。

### 构建期（CI）

1. 工作流每天定时（UTC 03:17）运行，也可在 Actions 页手动触发；为每个字体各起一个作业并行构建。
2. 对每个字体：
   - 用 `gh api` 取上游仓库最新 release 的 `tag_name` 作为版本号（仅 prerelease 时回退到列表第一条）；
   - 定时触发时若本仓库已存在 `slug-版本` 这个 tag，则跳过（手动触发强制重建）；
   - 按配置下载字体文件、下载 [`fontgen`](https://github.com/byte-me-labs/magisk-module-fontgen) 三架构二进制（arm64/arm/x64）、生成 `fontgen.json`、写入 `module.prop`、携带许可证文件，打包为 zip；
   - 由 `softprops/action-gh-release` 创建 Release 并上传 zip；
   - 生成 `updates/<slug>.json` 更新清单，由汇总作业收集全部清单后**一次性**提交到 `master`（单次提交避免并行作业互相冲突）。

### 安装期（customize.sh）

构建期**不生成** `fonts.xml` / `font_fallback.xml`。安装时：

1. `customize.sh` 按设备 ABI 挑选对应的 `fontgen` 二进制；
2. `fontgen` 读取设备**原厂**的 `/system/etc/fonts.xml` 与 `/system/etc/font_fallback.xml`，把模块携带的 CJK 字体族**插入回退链起点**，原厂字体族逐字节保留（留作生僻字回退）；
3. 生成结果写到 `$MODPATH/system/etc/`，由 Magisk 挂载覆盖系统配置。

之所以在**安装时**而非开机时生成：安装时模块尚未挂载到 `/system`，读到的还是设备原厂配置；开机后模块已覆盖挂载，再读只会读到自己的文件，拿不到原厂配置。生成逻辑是**字节级拼接**（定位用解析、写入用拼接），不重新序列化 XML，因此原厂配置里的注释、缩进、未识别的属性都会被原样保留。

## 模块内更新检查

生成的 `module.prop` 含 `updateJson` 字段，指向本仓库 `master` 分支上的更新清单：

```
updateJson=https://raw.githubusercontent.com/byte-me-labs/advanced-cjk-font-magisk-modules/master/updates/<slug>.json
```

Magisk 刷新模块列表时读取该文件，比较 `versionCode` 判断是否有新版本，并在模块页提供更新入口。清单格式：

```json
{
  "version": "v0.827",
  "versionCode": 20261024,
  "zipUrl": "https://github.com/byte-me-labs/advanced-cjk-font-magisk-modules/releases/download/lxgw-zhenkai-v0.827/magisk-module-font-lxgw-zhenkai-v0.827.zip",
  "changelog": "https://github.com/byte-me-labs/advanced-cjk-font-magisk-modules/releases/tag/lxgw-zhenkai-v0.827"
}
```

- `versionCode` 使用**构建日期**（UTC `YYYYMMDD`，如 `20261024`），不再从上游 tag 提取。历史 tag 派生的值最高为 6 位（`YYMMDD` 形式，如 `261022`），8 位日期恒大于它，因此切换后所有已安装模块都会收到一次更新。
- 定时任务每天运行一次，日期天然递增；同一天内多次重建版本号相同，不会重复提示更新。
- Magisk 用 Kotlin `Int` 解析 `versionCode`，越界（> 2147483647）会中止 `module.prop` 后续字段解析，故 `updateJson` 写在 `versionCode` **之前**。
- 更新清单只在内容变化时提交，不会产生空提交。若某次发布后清单未能提交（对应作业在上传清单前失败），手动触发该字体重建即可补齐。
- KernelSU 同样支持 `updateJson`；APatch 未验证。

## 支持的字体

<!-- fonts-table:start -->
| slug | 字体 | 上游 | 格式 | 最新版本 | 构建时间 |
| ---- | ---- | ---- | ---- | ---- | ---- |
| `lxgw-wenkai` | 霞鹜文楷 LXGW WenKai | [lxgw/LxgwWenKai](https://github.com/lxgw/LxgwWenKai) | ttf | `v1.530` | 2026-10-24 03:26 UTC |
| `lxgw-wenkai-screen` | 霞鹜文楷屏幕版 LXGW WenKai Screen | [lxgw/LxgwWenKai-Screen](https://github.com/lxgw/LxgwWenKai-Screen) | ttf | `v1.530` | 2026-10-24 03:26 UTC |
| `lxgw-wenkai-gb` | 霞鹜文楷 GB LXGW WenKai GB | [lxgw/LxgwWenKaiGB](https://github.com/lxgw/LxgwWenKaiGB) | ttf | `v1.530` | 2026-10-24 03:26 UTC |
| `lxgw-zhenkai` | 霞鹜臻楷 Slab 版 LXGW ZhenKai Slab | [lxgw/LxgwZhenKai](https://github.com/lxgw/LxgwZhenKai) | ttf | `v0.827` | 2026-10-24 03:26 UTC |
| `lxgw-xihei` | 霞鹜晰黑 LXGW XiHei | [lxgw/LxgwXiHei](https://github.com/lxgw/LxgwXiHei) | ttf | `v1.002` | 2026-10-24 03:26 UTC |
| `lxgw-zhisong` | 霞鹜致宋 LXGW ZhiSong | [lxgw/LxgwZhiSong](https://github.com/lxgw/LxgwZhiSong) | ttf | `v1.002` | 2026-10-24 03:26 UTC |
| `lxgw-neo-xihei` | 霞鹜新晰黑 LXGW Neo XiHei | [lxgw/LxgwNeoXiHei](https://github.com/lxgw/LxgwNeoXiHei) | ttf | `v1.308` | 2026-10-24 03:26 UTC |
| `lxgw-neo-zhisong` | 霞鹜新致宋 LXGW Neo ZhiSong | [lxgw/LxgwNeoZhiSong](https://github.com/lxgw/LxgwNeoZhiSong) | ttf | `v1.070` | 2026-10-24 03:26 UTC |
| `lxgw-neo-xizhi-screen` | 霞鹜新晰黑屏幕版 LXGW Neo XiHei Screen | [lxgw/LxgwNeoXiZhi-Screen](https://github.com/lxgw/LxgwNeoXiZhi-Screen) | ttf | `26.08.21` | 2026-10-24 03:26 UTC |
| `sim-xizhi` | 简晰知 Sim XiZhi | [lxgw/SimXiZhi](https://github.com/lxgw/SimXiZhi) | ttf | `v1.103` | 2026-10-24 03:26 UTC |
| `lxgw-marker-gothic` | 霞鹜马科特黑体 LXGW Marker Gothic | [lxgw/LxgwMarkerGothic](https://github.com/lxgw/LxgwMarkerGothic) | ttf | `v1.004` | 2026-10-24 03:26 UTC |
| `lxgw-bright` | 霞鹜明亮 LXGW Bright | [lxgw/LxgwBright](https://github.com/lxgw/LxgwBright) | ttf | `26.10.22` | 2026-10-24 03:26 UTC |
| `lxgw-bright-code` | 霞鹜明亮代码 LXGW Bright Code | [lxgw/LxgwBright-Code](https://github.com/lxgw/LxgwBright-Code) | ttf | `26.10.22` | 2026-10-24 03:26 UTC |
| `975hei` | 975黑体 LXGW 975Hei | [lxgw/975Hei](https://github.com/lxgw/975Hei) | ttf | `26.06.20` | 2026-10-24 03:26 UTC |
| `975yuan` | 975圆体 LXGW 975Yuan | [lxgw/975Yuan](https://github.com/lxgw/975Yuan) | ttf | `26.07.26` | 2026-10-24 03:26 UTC |
| `sarasa-gothic` | 更纱黑体 Sarasa Gothic | [be5invis/Sarasa-Gothic](https://github.com/be5invis/Sarasa-Gothic) | ttf | `v1.0.42` | 2026-10-24 03:26 UTC |
| `source-han-sans` | 思源黑体 Source Han Sans | [adobe-fonts/source-han-sans](https://github.com/adobe-fonts/source-han-sans) | otf | `2.005R` | 2026-10-24 03:26 UTC |
| `source-han-serif` | 思源宋体 Source Han Serif | [adobe-fonts/source-han-serif](https://github.com/adobe-fonts/source-han-serif) | otf | `2.003R` | 2026-10-24 03:26 UTC |
| `dream-han-sans` | 梦源黑体 Dream Han Sans | [Pal3love/dream-han-cjk](https://github.com/Pal3love/dream-han-cjk) | ttf | `dream-3.03-sans-2.005-serif-2.003` | 2026-10-24 03:26 UTC |
| `zhuque` | 朱雀仿宋 Zhuque Fangsong | [TrionesType/zhuque](https://github.com/TrionesType/zhuque) | ttf | `v0.212` | 2026-10-24 03:26 UTC |
| `maple-mono` | 枫叶等宽 Maple Mono | [subframe7536/maple-font](https://github.com/subframe7536/maple-font) | ttf | `v7.9` | 2026-10-24 03:26 UTC |
| `smiley-sans` | 得意黑 Smiley Sans | [atelier-anchor/smiley-sans](https://github.com/atelier-anchor/smiley-sans) | ttf | `v2.0.1` | 2026-10-24 03:26 UTC |
<!-- fonts-table:end -->

> 「最新版本」与「构建时间」由 CI 在每次构建后自动刷新，标记之间的内容无需手工维护；新增字体若未插入表格，会自动追加到表末。

## 添加新字体

在 `.github/fonts/<slug>/` 下新建一个 `config.json`，下一次工作流运行即会自动纳入构建矩阵。配置格式见下节。以「霞鹜文楷」为例：

```json
{
  "slug": "lxgw-wenkai",
  "name": "霞鹜文楷 LXGW WenKai",
  "module_id": "byte-me-labs-font-lxgw-wenkai",
  "upstream": "lxgw/LxgwWenKai",
  "format": "ttf",
  "fallback": "nearest",
  "license": { "type": "SIL OFL 1.1", "assets": ["OFL.txt"] },
  "download": {
    "kind": "assets",
    "entries": [
      { "from": "LXGWWenKai-Light\\.ttf", "weight": 3 },
      { "from": "LXGWWenKai-Regular\\.ttf", "weight": 4 },
      { "from": "LXGWWenKai-Medium\\.ttf", "weight": 5 }
    ]
  }
}
```

## config.json 字段说明

### 顶层字段

| 字段 | 必填 | 说明 |
| ---- | ---- | ---- |
| `slug` | ✅ | 唯一标识，也是发布 tag 的前缀（`slug-版本`） |
| `name` | ✅ | 显示名，写入 `module.prop` 的 `name` 与 Release 标题 |
| `module_id` | ✅ | Magisk 模块 id，只能含字母、数字、`_`、`.`、`-` |
| `upstream` | ✅ | 上游仓库 `owner/repo`，用于取 `latest release` |
| `format` | ✅ | `ttf` 或 `otf`，声明字体文件格式 |
| `version_code` | ❌ | **已弃用（保留但忽略）**。`versionCode` 现统一使用构建日期（UTC `YYYYMMDD`），不再从上游 tag 提取 |
| `fallback` | ❌ | 默认 `nearest`。字重回退策略，目前仅支持 `nearest` |
| `cjk_langs` | ❌ | 默认 `["zh-Hans", "zh-Hant,zh-Bopo", "ja", "ko"]`。生成的字体的语言标签列表（每个元素对应一个 `<family lang="...">`） |

### license

| 字段 | 必填 | 说明 |
| ---- | ---- | ---- |
| `type` | ✅ | 许可证名，写入 `module.prop` 的 `description` |
| `assets` | ✅ | 上游仓库内的许可证文件路径数组，逐一打包进模块根目录 |

### download

| 字段 | 必填 | 说明 |
| ---- | ---- | ---- |
| `kind` | ✅ | `assets`（直接下载 release 资产）或 `archive`（下载归档后解包） |
| `entries` | ✅ | 字体条目数组，每个元素 `{ "from": 正则, "weight": 1..9 }`。`from` 匹配资产名或归档内文件名（正则，注意转义 `.`） |
| `asset` | archive 时必填 | 匹配归档资产名的正则（如 `^SarasaGothic-TTF-[0-9.]+\\.7z$`） |
| `archive_format` | archive 时必填 | `zip` 或 `7z` |

### 字重（weight）

`entries[].weight` 取值 1–9，安装时由 `fontgen` 展开为最接近的 100–900 字重（平手取较细）：

| weight | 字重 | weight | 字重 |
| ------ | ---- | ------ | ---- |
| 1 | Thin (100) | 6 | SemiBold (600) |
| 2 | UltraLight (200) | 7 | Bold (700) |
| 3 | Light (300) | 8 | ExtraBold (800) |
| 4 | Regular (400) | 9 | Heavy/Black (900) |
| 5 | Medium (500) | | |

## 手动触发与本地构建

- **手动触发**：Actions → “Build CJK Font Modules” → Run workflow，可填逗号分隔的 slug 只重建部分字体（留空=全部）。
- **本地试跑**：`DRY_RUN=1 bash .github/scripts/build_fonts.sh .github/fonts/lxgw-wenkai/config.json`，只构建不发布（需本机装有 `gh`、`jq`、`curl`、`zip`、`unzip`，处理 7z 时还需 `p7zip-full`）。

## fontgen 子项目

安装期配置生成器是一个独立的 Go 项目：[`byte-me-labs/magisk-module-fontgen`](https://github.com/byte-me-labs/magisk-module-fontgen)。构建期从它的 latest release 拉取 `fontgen-{arm64,arm,x64}` 三个静态二进制。选 Go 的原因：

- 需要**字节级定位 + 拼接**（保留原厂 XML 的注释、缩进、未识别属性），shell/awk 对单行压缩的 XML 力不从心；
- 编译为无依赖的静态 Linux 二进制（`GOOS=linux`），在 Android 内核上直接运行，无需 NDK/解释器；
- 有单元测试 + golden 文件锁死行为，适合长期维护。

它读取 `fontgen.json`（构建期生成，含 `cjk_langs` 与原始字重 → 实际文件名映射），在安装时完成字重展开与 XML 拼接。

## 致谢

本仓库骨架源自 [lxgw/advanced-cjk-font-magisk-module-template](https://github.com/lxgw/advanced-cjk-font-magisk-module-template)（作者 [@落霞孤鹜lxgw](https://github.com/lxgw)），后者基于 [Petit-Abba/Magisk-Modules-Template-ge20.4](https://github.com/Petit-Abba/Magisk-Modules-Template-ge20.4)。感谢他们为字体模块模板做出的贡献。

## 许可证

本项目整体采用 [MIT License](./LICENSE) 开源发布。各字体模块随包附带的字体文件与其许可证均来自各自上游仓库，版权归原作者所有，请遵守其授权条款。
