import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "./data/pinyin-dict.js" as PinyinDict

// 拼音应用搜索 —— 把「拼音/首字母」查询映射到已安装应用的 DesktopEntry。
// 不修改任何 .desktop 文件：纯运行时索引，插件卸载即完全还原。
QtObject {
    id: root

    property var pluginService: null
    property string trigger: ""

    signal itemsChanged()

    readonly property string pluginId: "pinyinAppSearch"

    // ---- 设置 ----
    property int maxResults: 8
    property int minQueryLength: 2
    property bool matchGenericName: false
    property bool matchComment: false

    // ---- 内部状态 ----
    property var _charReadings: ({})   // 汉字 -> [读音...]（首个为常用读音）
    property var _index: []            // [{ id, entry, name, generic, comment, icon, variants: [{py, ini}] }]
    property var _byId: ({})
    property bool _ready: false
    property string _stats: ""

    Component.onCompleted: {
        _loadSettings();
        _buildCharReadings();
        _rebuildIndex();
        _ready = true;
    }

    function _loadSettings() {
        if (!pluginService)
            return;
        // 首次运行默认常驻：DMS 的 getPluginTrigger() 用 `plugin.trigger || "!"`，
        // 空 trigger 在 manifest 里会被回落成 "!"，那样注册表安装后打 jsq 什么都搜不到。
        // 只在用户从未设置过时写一次，之后尊重用户的显式选择。
        if (pluginService.loadPluginData(pluginId, "noTrigger", null) === null)
            pluginService.savePluginData(pluginId, "noTrigger", true);
        maxResults = pluginService.loadPluginData(pluginId, "maxResults", 8);
        minQueryLength = pluginService.loadPluginData(pluginId, "minQueryLength", 2);
        matchGenericName = pluginService.loadPluginData(pluginId, "matchGenericName", false);
        matchComment = pluginService.loadPluginData(pluginId, "matchComment", false);
    }

    // 注意：QtObject 没有默认属性，子对象必须挂在 property 上
    // pluginDataChanged 是 PluginService 的信号（SettingsData 没有这个信号）
    property Connections settingsConn: Connections {
        target: root.pluginService
        function onPluginDataChanged(id) {
            if (id !== root.pluginId)
                return;
            root._loadSettings();
            root._rebuildIndex();
            root.itemsChanged();
        }
    }

    property Connections entriesConn: Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            if (!root._ready)
                return;
            root._rebuildIndex();
            root.itemsChanged();
        }
    }

    // ---------------- 拼音字典 ----------------

    function _buildCharReadings() {
        const map = {};
        for (const syl in PinyinDict.syllables) {
            const chars = PinyinDict.syllables[syl];
            for (let i = 0; i < chars.length; i++)
                map[chars[i]] = [syl];
        }
        // 多音字：按常见度排序的多读音（覆盖上面的单读音）
        for (const ch in PinyinDict.polyphones)
            map[ch] = PinyinDict.polyphones[ch];
        _charReadings = map;
        _stats = Object.keys(map).length + " 字";
    }

    function _isCjk(ch) {
        const c = ch.codePointAt(0);
        return (c >= 0x3400 && c <= 0x4DBF) || (c >= 0x4E00 && c <= 0x9FFF);
    }

    // 把名字展开成若干候选 {py, ini}（多音字组合，最多 cap 个）
    function _variants(text, cap) {
        const chars = String(text || "").split("");
        let combos = [{
            py: "",
            ini: ""
        }];

        for (let i = 0; i < chars.length; i++) {
            const ch = chars[i];
            let options;
            if (_isCjk(ch)) {
                const readings = _charReadings[ch];
                if (!readings)
                    continue;               // 字典里没有的生僻字 -> 跳过，不影响其余部分
                options = readings.slice(0, 3);
            } else if (/[a-zA-Z0-9]/.test(ch)) {
                options = [ch.toLowerCase()];
            } else {
                continue;                   // 空格、标点、符号忽略
            }

            const next = [];
            for (let c = 0; c < combos.length; c++) {
                for (let o = 0; o < options.length; o++) {
                    next.push({
                        py: combos[c].py + options[o],
                        ini: combos[c].ini + options[o].charAt(0)
                    });
                    if (next.length >= cap)
                        break;
                }
                if (next.length >= cap)
                    break;
            }
            combos = next;
            if (combos.length === 0)
                return [];
        }
        return combos;
    }

    // ---------------- 索引 ----------------

    function _rebuildIndex() {
        const entries = (DesktopEntries.applications && DesktopEntries.applications.values) || [];
        const index = [];
        const byId = {};

        for (let i = 0; i < entries.length; i++) {
            const app = entries[i];
            if (!app || app.noDisplay || !app.id)
                continue;
            const name = app.name || "";
            const generic = app.genericName || "";
            const cjkInName = /[\u3400-\u9fff]/.test(name);
            const cjkInGeneric = matchGenericName && /[\u3400-\u9fff]/.test(generic);
            if (!cjkInName && !cjkInGeneric)
                continue;                   // 纯英文名的应用交给原生搜索

            let variants = cjkInName ? _variants(name, 6) : [];
            if (cjkInGeneric)
                variants = variants.concat(_variants(generic, 3));
            variants = _dedupeVariants(variants);
            if (variants.length === 0)
                continue;

            const item = {
                id: app.id,
                entry: app,
                name: name,
                generic: generic,
                comment: app.comment || "",
                icon: app.icon || "",
                keywords: (app.keywords || []).map(k => String(k).toLowerCase()),
                variants: variants
            };
            index.push(item);
            byId[app.id] = item;
        }

        _index = index;
        _byId = byId;
        _stats = index.length + " 个中文应用";
    }

    function _dedupeVariants(variants) {
        const seen = {};
        const out = [];
        for (let i = 0; i < variants.length; i++) {
            const v = variants[i];
            if (!v.py || seen[v.py])
                continue;
            seen[v.py] = true;
            out.push(v);
        }
        return out;
    }

    // 原生搜索（AppSearchService）会不会自己命中？命中就别重复展示
    function _nativeHits(item, q) {
        if (item.name && item.name.toLowerCase().includes(q))
            return true;
        if (item.generic && item.generic.toLowerCase().includes(q))
            return true;
        if (item.id.toLowerCase().includes(q))
            return true;
        for (let i = 0; i < item.keywords.length; i++) {
            if (item.keywords[i].includes(q))
                return true;
        }
        if (matchComment && item.comment)
            return item.comment.toLowerCase().includes(q);
        return false;
    }

    function _scoreVariants(variants, q) {
        let best = 0;
        for (let i = 0; i < variants.length; i++) {
            const v = variants[i];
            let s = 0;
            if (v.ini === q)
                s = 1000;
            else if (v.ini.startsWith(q))
                s = 960;
            else if (v.py === q)
                s = 940;
            else if (v.py.startsWith(q))
                s = 920;
            else if (v.ini.includes(q))
                s = 880;
            else if (v.py.includes(q))
                s = 850;
            if (s > best)
                best = s;
        }
        return best;
    }

    // ---------------- 启动器接口 ----------------

    function getItems(query) {
        const q = String(query || "").toLowerCase().replace(/[\s\-_]+/g, "");
        if (!_ready || q.length < minQueryLength)
            return [];
        if (!/[a-z0-9]/.test(q))
            return [];

        const hits = [];
        for (let i = 0; i < _index.length; i++) {
            const item = _index[i];
            if (_nativeHits(item, q))
                continue;
            const score = _scoreVariants(item.variants, q);
            if (score > 0)
                hits.push({
                    item: item,
                    score: score,
                    order: i
                });
        }

        hits.sort(function (a, b) {
            if (a.score !== b.score)
                return b.score - a.score;
            return a.order - b.order;
        });

        const limit = Math.max(1, Math.min(20, maxResults || 8));
        const out = [];
        for (let i = 0; i < hits.length && i < limit; i++) {
            const item = hits[i].item;
            const subtitle = item.generic || item.comment || hits[i].item.id;
            out.push({
                name: item.name,
                icon: item.icon || "application-x-executable",
                comment: subtitle,
                action: "app:" + item.id,
                categories: [I18n.tr("Pinyin Apps")],
                source: I18n.tr("Pinyin")
            });
        }
        return out;
    }

    function executeItem(item) {
        if (!item || !item.action)
            return;
        const action = String(item.action);
        if (!action.startsWith("app:"))
            return;
        const id = action.substring(4);
        let entry = _byId[id] ? _byId[id].entry : null;
        if (!entry && typeof DesktopEntries.heuristicLookup === "function")
            entry = DesktopEntries.heuristicLookup(id);
        if (!entry)
            return;
        // 走 DMS 原生启动路径（处理 runInTerminal、启动前缀、光标环境、nvidia 等）
        if (typeof SessionService !== "undefined" && typeof SessionService.launchDesktopEntry === "function")
            SessionService.launchDesktopEntry(entry);
        else
            entry.execute();
    }

    function getContextMenuActions(item) {
        if (!item || !item.action)
            return [];
        const id = String(item.action).substring(4);
        const itemData = _byId[id];
        const actions = [];
        if (itemData && itemData.entry && itemData.entry.execString) {
            actions.push({
                label: I18n.tr("Copy command"),
                action: function () {
                    Quickshell.execDetached(["dms", "cl", "copy", itemData.entry.execString]);
                    ToastService.showInfo(I18n.tr("Copied"), itemData.entry.execString);
                }
            });
        }
        return actions;
    }
}
