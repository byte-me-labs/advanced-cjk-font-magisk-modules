#!/system/bin/sh
# 安装时根据设备当前系统的字体配置，动态生成 fonts.xml 与 font_fallback.xml。
#
# 思路：完整保留设备原厂的所有字体族，仅把 CJK（中文 zh* / 日文 ja / 韩文 ko）族中的
# 字体文件替换为本模块携带的字体。生成的配置结构与原厂完全一致，避免 Android 15 上
# “极简”font_fallback.xml 缺少基础族，导致 FontManagerService 初始化时 Typeface.create()
# 收到 null 而抛 NPE，最终 Watchdog 杀掉 system_server 引起开机循环。
#
# 为什么在 customize.sh（安装时）而不是 post-fs-data.sh（开机时）生成：
#   安装时本模块尚未挂载到 /system，读到的 /system/etc/*.xml 仍是设备原厂文件；
#   开机后模块已覆盖挂载，再读只会读到我们自己生成的文件，无法拿到原厂配置。

MODPATH=${MODPATH:-${0%/*}}

MAP="$MODPATH/font_map.txt"
if [ ! -f "$MAP" ]; then
  echo "[!] 缺少 $MAP，跳过字体配置生成"
  exit 0
fi

# 行级替换：只把 CJK 族的 <font> 子项换成我们的字重映射，其余族原样保留。
# 仅匹配“行首（可带缩进）为 <family lang=...>”，对压缩成单行的原厂配置会匹配不到、
# 整份原样复制而不破坏结构（Android 原厂配置均为多行，这里仅作防御）。
gen() {
  cfg="$1"
  src="/system/etc/$cfg"
  dst="$MODPATH/system/etc/$cfg"
  [ -f "$src" ] || { echo "[!] 未找到 $src，跳过 $cfg"; return 0; }
  mkdir -p "$(dirname "$dst")"
  awk -v map="$MAP" '
    BEGIN {
      n = 0
      while ((getline < map) > 0) {
        if ($1 == "") continue
        n++
        weight[n] = $1
        file[n] = $2
      }
      close(map)
    }
    /^[[:space:]]*<family[^>]*lang="(zh[^"]*|ja|ko)"/ {
      print
      for (i = 1; i <= n; i++)
        printf "        <font weight=\"%s\" style=\"normal\">%s</font>\n", weight[i], file[i]
      skip = 1
      next
    }
    skip == 1 && /^[[:space:]]*<\/family>/ {
      print
      skip = 0
      next
    }
    skip == 1 { next }
    { print }
  ' "$src" > "$dst"
  echo "[i] 已生成 $dst"
}

echo "[i] 根据设备原厂字体配置生成 fonts.xml / font_fallback.xml ..."
gen fonts.xml
gen font_fallback.xml
echo "[i] 字体配置生成完成"
