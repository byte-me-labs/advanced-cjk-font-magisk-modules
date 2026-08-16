#!/system/bin/sh
# 安装时调用 fontgen 二进制，按设备原厂字体配置生成 fonts.xml 与 font_fallback.xml。
#
# 为什么在 customize.sh（安装时）而非 post-fs-data.sh（开机时）生成：
#   安装时本模块尚未挂载到 /system，读到的 /system/etc/*.xml 仍是设备原厂文件；
#   开机后模块已覆盖挂载，再读只会读到我们自己生成的文件，无法拿到原厂配置。
#
# fontgen 的做法：完整保留原厂所有字体族，仅把本模块携带的 CJK 族插入回退链起点，
# 原厂 CJK 族（如 NotoSansCJK）留作生僻字回退。字节级拼接，逐字节保留原厂内容。

MODPATH=${MODPATH:-${0%/*}}

# 同类字体模块互斥：安装本模块时，停用其他已安装的本项目字体模块（仅保留本次刷入的）。
# 机制同 Vector 停用原版 LSPosed —— Magisk 以 /data/adb/modules/<id>/disable 空文件标记停用。
MY_ID=$(grep_prop id "$MODPATH/module.prop" 2>/dev/null)
[ -z "$MY_ID" ] && MY_ID=$(basename "$MODPATH")
for d in /data/adb/modules/byte-me-labs-font-*; do
  [ -d "$d" ] || continue
  [ "$(basename "$d")" = "$MY_ID" ] && continue
  touch "$d/disable"
  ui_print "- 已停用同类字体模块: $(basename "$d")"
done

MANIFEST="$MODPATH/fontgen.json"
if [ ! -f "$MANIFEST" ]; then
  abort "缺少 $MANIFEST，无法生成字体配置"
fi

# 按架构挑选 fontgen 二进制（$ARCH 由 Magisk 安装器提供，取值 arm64/arm/x64）
ARCH="${ARCH:-$(getprop ro.product.cpu.abi)}"
BIN=""
case "$ARCH" in
  arm64|arm64-v8a)         BIN="$MODPATH/bin/arm64/fontgen" ;;
  arm|armeabi-v7a|armeabi) BIN="$MODPATH/bin/arm/fontgen" ;;
  x64|x86_64)              BIN="$MODPATH/bin/x64/fontgen" ;;
  *)                       abort "不支持的架构: $ARCH" ;;
esac

if [ ! -f "$BIN" ]; then
  abort "缺少 fontgen 二进制: $BIN"
fi

# Magisk 安装时 set_default_perm 会把模块内所有文件 chmod 0644（去掉可执行位），
# 这里必须显式恢复，否则 exec 会报 Permission denied（退出码 126）。
chmod 755 "$BIN"

"$BIN" generate --system /system --out "$MODPATH/system" --manifest "$MANIFEST" \
  || abort "fontgen 生成字体配置失败"
