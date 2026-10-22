#!/usr/bin/env bash
# 把插件安装到 DMS 插件目录并启用。
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/plugins/pinyinAppSearch"
SETTINGS="${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/plugin_settings.json"

echo "==> 安装到 $DEST"
mkdir -p "$DEST"
cp -a "$SRC"/plugin.json "$SRC"/*.qml "$DEST"/
mkdir -p "$DEST/data" "$DEST/tools"
cp -a "$SRC"/data/. "$DEST"/data/
[ -d "$SRC/tools" ] && cp -a "$SRC"/tools/. "$DEST"/tools/

echo "==> 启用 (plugin_settings.json)"
python3 - "$SETTINGS" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
data = {}
if p.exists() and p.read_text().strip():
    try:
        data = json.loads(p.read_text())
    except Exception:
        data = {}
data.setdefault("pinyinAppSearch", {}).update({"enabled": True, "noTrigger": True})
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(data, indent=2, ensure_ascii=False))
print("   enabled=True noTrigger=True")
PY

if systemctl --user is-active --quiet dms.service; then
    echo "==> 重启 dms.service 以加载插件"
    systemctl --user restart dms.service
    sleep 3
fi

echo
echo "完成。打开启动器输入 'jsq' 应该能看到「计算器」。"
echo "若想让它只在「全部」标签页生效：按 Ctrl+1 切到「全部」（DMS 限制，插件项不参与「应用」页搜索）。"
