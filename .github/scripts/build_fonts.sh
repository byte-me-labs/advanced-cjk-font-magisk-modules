#!/usr/bin/env bash
# 打包单个 CJK 字体为 Magisk 模块并发布到 GitHub Release。
#
# 用法：build_fonts.sh <字体配置.json>
# 由工作流的矩阵（strategy.matrix）为每个字体各起一个作业调用本脚本，
# 配置文件位于 .github/fonts/<slug>/config.json，本脚本只处理那一个字体。
#
# 流程：
#   1. 用 gh api 取上游 latest release 的 tag_name 作为版本号；
#   2. 若为定时触发（SKIP_PUBLISHED=true）且本仓库已存在 "slug-tag" 这个 tag 则跳过；
#      手动触发（workflow_dispatch）时 SKIP_PUBLISHED=false，强制重建并重新发布；
#   3. 下载字体（保留上游原始文件名）、组装模块、从 .github/fonts/<slug>/fonts.xml 与
#      .github/fonts/<slug>/font_fallback.xml 拷贝预设字体配置（无需运行时改名）、
#      写入 module.prop、携带许可证、打包 zip；
#   4. 产物写到 dist/ 并输出发布信息，由工作流的 softprops/action-gh-release
#      步骤创建 Release 并上传 zip。
#
# 依赖（ubuntu-latest 均已预装）：gh、jq、curl、zip、unzip；
#   处理 .7z 归档时额外需要 p7zip-full（由工作流安装）。
#
# 环境变量：
#   GITHUB_REPOSITORY  当前仓库（owner/name），GitHub Actions 自动提供。
#   GITHUB_TOKEN       gh 认证令牌，GitHub Actions 自动提供。
#   DRY_RUN=1          只构建不发布（should_publish=false）。
set -euo pipefail

REPO="${GITHUB_REPOSITORY:?必须设置 GITHUB_REPOSITORY}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CFG_FILE="${1:?用法: $0 <字体配置.json>}"
[[ "$CFG_FILE" == /* ]] || CFG_FILE="$ROOT/$CFG_FILE"
DRY_RUN="${DRY_RUN:-}"
# 定时触发时跳过已发布版本；手动触发时强制重建（默认 true，仅在未显式传入时兜底）
SKIP_PUBLISHED="${SKIP_PUBLISHED:-true}"

# 模板骨架：整目录复制（META-INF、system 为顶层目录，复制整棵子树以保留嵌套结构）
#   + 单文件复制（模块根目录的脚本/配置）
SKELETON_DIRS=(META-INF system)
SKELETON_FILES=(customize.sh post-fs-data.sh service.sh uninstall.sh sepolicy.rule system.prop)

info() { printf '\033[1;34m[%s]\033[0m %s\n' "$1" "$2"; }
warn() { printf '\033[1;33m[警告]\033[0m %s\n' "$*" >&2; }

# 从 release 资产里按正则找到唯一匹配，输出 browser_download_url；0/多匹配返回非零。
# 依赖全局数组 ASSETS（每行 "name<TAB>url"）。
pick_url() {
  local pattern="$1" line name url found="" count=0
  for line in "${ASSETS[@]}"; do
    name="${line%%$'\t'*}"
    url="${line#*$'\t'}"
    if [[ "$name" =~ $pattern ]]; then
      found="$url"; count=$((count + 1))
    fi
  done
  if (( count == 0 )); then
    warn "未找到匹配 '$pattern' 的资产"
    return 1
  fi
  if (( count > 1 )); then
    warn "匹配 '$pattern' 的资产多于 1 个（$count 个）"
    return 1
  fi
  printf '%s' "$found"
}

# 在解压目录里按正则找到唯一文件，输出其完整路径。依赖全局变量 EXTRACT_DIR。
pick_file() {
  local pattern="$1" f found="" count=0
  while IFS= read -r f; do
    if [[ "$(basename "$f")" =~ $pattern ]]; then
      found="$f"; count=$((count + 1))
    fi
  done < <(find "$EXTRACT_DIR" -type f)
  if (( count != 1 )); then
    warn "包内匹配 '$pattern' 的文件数 = $count"
    return 1
  fi
  printf '%s' "$found"
}

version_code() {
  local tag="$1" rule="${2:-digits}" m digits
  if [[ "$rule" == "digits" ]]; then
    m="$tag"
  else
    if [[ "$tag" =~ $rule ]]; then
      m="${BASH_REMATCH[1]:-${BASH_REMATCH[0]}}"
    else
      warn "version_code 正则 '$rule' 未匹配 tag '$tag'"
      m="$tag"
    fi
  fi
  digits="$(printf '%s' "$m" | tr -cd '0-9')"
  [[ -n "$digits" ]] && printf '%s' "$digits" || printf '1'
}

# 读取本字体的配置
font="$(jq -c '.' "$CFG_FILE")"
slug="$(jq -r .slug <<<"$font")"
name="$(jq -r .name <<<"$font")"
module_id="$(jq -r .module_id <<<"$font")"
upstream="$(jq -r .upstream <<<"$font")"
lic_type="$(jq -r .license.type <<<"$font")"
kind="$(jq -r .download.kind <<<"$font")"
vercode="$(jq -r '.version_code // "digits"' <<<"$font")"

tag="$(gh api "repos/$upstream/releases/latest" --jq '.tag_name')"
release_tag="$slug-$tag"

if [[ "$SKIP_PUBLISHED" == "true" ]] && gh api "repos/$REPO/releases/tags/$release_tag" >/dev/null 2>&1; then
  info "$slug" "$tag 已发布，跳过"
  [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "should_publish=false" >> "$GITHUB_OUTPUT"
  exit 0
fi
info "$slug" "构建 $tag"

work="$(mktemp -d)"
src="$work/src"; mkdir -p "$src"
mapfile -t ASSETS < <(gh api "repos/$upstream/releases/latest" \
    --jq '.assets[] | .name + "\t" + .browser_download_url')
if (( ${#ASSETS[@]} == 0 )); then
  warn "$slug 没有可用的 release 资产"
  exit 1
fi

declare -A weights  # 源字重 -> 源文件路径

if [[ "$kind" == "assets" ]]; then
  while IFS= read -r e; do
    from="$(jq -r .from <<<"$e")"
    w="$(jq -r .weight <<<"$e")"
    url="$(pick_url "$from")"
    fn="$(basename "$url")"
    curl -fsSL -o "$src/$fn" "$url"
    weights[$w]="$src/$fn"
  done < <(jq -c '.download.entries[]' <<<"$font")
else
  asset_re="$(jq -r .download.asset <<<"$font")"
  afmt="$(jq -r '.download.archive_format // empty' <<<"$font")"
  if [[ -z "$afmt" ]]; then
    warn "$slug 的 archive 类型缺少 archive_format（zip 或 7z）"
    exit 1
  fi
  url="$(pick_url "$asset_re")"
  aname="$(basename "$url")"
  curl -fsSL -o "$src/$aname" "$url"
  EXTRACT_DIR="$src/x"; mkdir -p "$EXTRACT_DIR"
  case "$afmt" in
    zip) (cd "$EXTRACT_DIR" && unzip -q "$src/$aname") ;;
    7z)  7z x -y "$src/$aname" -o"$EXTRACT_DIR" >/dev/null ;;
    *)   warn "不支持的归档格式 '$afmt'（只支持 zip / 7z）"; exit 1 ;;
  esac
  while IFS= read -r e; do
    from="$(jq -r .from <<<"$e")"
    w="$(jq -r .weight <<<"$e")"
    f="$(pick_file "$from")"
    weights[$w]="$f"
  done < <(jq -c '.download.entries[]' <<<"$font")
fi

# 组装模块目录
mod="$work/$slug"; mkdir -p "$mod"
for d in "${SKELETON_DIRS[@]}"; do cp -a "$ROOT/$d" "$mod/"; done
for f in "${SKELETON_FILES[@]}"; do cp -a "$ROOT/$f" "$mod/"; done

fontsdir="$mod/system/fonts"
# 字体文件保留上游原始文件名，预设的 fonts.xml / font_fallback.xml 直接引用这些名字
for f in "${weights[@]}"; do cp "$f" "$fontsdir/"; done

# 拷贝预设字体配置（去重后的最终引用已预先写好，无需运行时改名）
preset_dir="$ROOT/.github/fonts/$slug"
preset_fonts="$preset_dir/fonts.xml"
preset_fallback="$preset_dir/font_fallback.xml"
[[ -f "$preset_fonts" ]] || { warn "$slug 缺少预设 $preset_fonts"; exit 1; }
[[ -f "$preset_fallback" ]] || { warn "$slug 缺少预设 $preset_fallback"; exit 1; }
cp "$preset_fonts" "$mod/system/etc/fonts.xml"
cp "$preset_fallback" "$mod/system/etc/font_fallback.xml"

# 许可证
while IFS= read -r lic; do
  gh api "repos/$upstream/contents/$lic" --jq '.content' | base64 -d > "$mod/$lic"
done < <(jq -r '.license.assets[]' <<<"$font")

# module.prop（LF 行尾）
{
  echo "id=$module_id"
  echo "name=$name"
  echo "version=$tag"
  echo "versionCode=$(version_code "$tag" "$vercode")"
  echo "author=auto-built (upstream: $upstream)"
  echo "description=$name $tag，自动打包自 $upstream。许可证：$lic_type。"
} > "$mod/module.prop"

# 打包 zip，产物固定写到 dist/，由发布步骤（softprops/action-gh-release）上传
zipname="$slug-$tag.zip"
mkdir -p "$ROOT/dist"
zippath="$ROOT/dist/$zipname"
(cd "$mod" && zip -rq "$zippath" .)
info "$slug" "产物 dist/$zipname"

# 把发布信息输出给工作流的 softprops 步骤；本地 DRY_RUN 无 GITHUB_OUTPUT，自动跳过
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  if [[ -n "$DRY_RUN" ]]; then
    echo "should_publish=false" >> "$GITHUB_OUTPUT"
  else
    echo "should_publish=true" >> "$GITHUB_OUTPUT"
    echo "release_tag=$release_tag" >> "$GITHUB_OUTPUT"
    echo "title=$name $tag" >> "$GITHUB_OUTPUT"
    echo "notes=自动打包 $name $tag（上游 $upstream）。许可证：$lic_type。" >> "$GITHUB_OUTPUT"
  fi
fi
