import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "./data/pinyin-dict.js" as PinyinDict
import "./data/match.js" as Match

// 拼音应用搜索 —— 把「拼音/首字母/混拼」查询映射到已安装应用的 DesktopEntry。
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
    property var aliases: []

    // ---- 内部状态 ----
    property var _charReadings: ({})   // 汉字 -> [读音...]（首个为常用读音）
    property var _index: []            // [{ id, entry, name, variants, sylls, ... }]
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

        const maxR = parseInt(pluginService.loadPluginData(pluginId, "maxResults", 8), 10);
        const minL = parseInt(pluginService.loadPluginData(pluginId, "minQueryLength", 2), 10);
        maxResults = (maxR >= 1 && maxR <= 20) ? maxR : 8;
        minQueryLength = (minL >= 1 && minL <= 5) ? minL : 2;
        matchGenericName = pluginService.loadPluginData(pluginId, "matchGenericName", false) === true;
        matchComment = pluginService.loadPluginData(pluginId, "matchComment", false) === true;

        const rawAliases = pluginService.loadPluginData(pluginId, "aliases", []);
        aliases = Array.isArray(rawAliases) ? rawAliases : [];
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

    function _hasCjk(text) {
        return /[\u3400-\u9fff]/.test(String(text || ""));
    }

    // ---------------- 索引 ----------------

    function _rebuildIndex() {
        const entries = (DesktopEntries.applications && DesktopEntries.applications.values) || [];
        const index = [];
        const byId = {};
        const targets = [];                 // 供别名解析：[{ id, name, item }]

        for (let i = 0; i < entries.length; i++) {
            const app = entries[i];
            if (!app || app.noDisplay || !app.id)
                continue;
            const name = app.name || "";
            const generic = app.genericName || "";
            const cjkInName = _hasCjk(name);
            const cjkInGeneric = matchGenericName && _hasCjk(generic);

            let variants = [];
            if (cjkInName)
                variants = Match.buildVariants(name, _charReadings, 6);
            if (cjkInGeneric)
                variants = variants.concat(Match.buildVariants(generic, _charReadings, 3));

            const item = {
                id: app.id,
                entry: app,
                name: name,
                generic: generic,
                comment: app.comment || "",
                icon: app.icon || "",
                keywords: (app.keywords || []).map(k => String(k).toLowerCase()),
                variants: Match.dedupeVariants(variants),
                sylls: Match.syllables(name, _charReadings),
                cjk: cjkInName || cjkInGeneric
            };
            index.push(item);
            byId[app.id] = item;
            targets.push({
                id: item.id,
                name: item.name,
                item: item
            });
        }

        // 用户自定义别名：alias -> 应用（应用名或 desktop id）
        let aliasCount = 0;
        for (let a = 0; a < aliases.length; a++) {
            const entry = aliases[a];
            if (!entry)
                continue;
            const aliasKey = Match.normalizeAlias(entry.alias);
            if (!aliasKey)
                continue;
            const pos = Match.findAliasTarget(targets.map(t => ({
                id: t.id,
                name: t.name
            })), entry.target);
            if (pos < 0)
                continue;
            const target = targets[pos].item;
            target.variants = target.variants.concat([{
                py: aliasKey,
                ini: aliasKey,
                alias: true
            }]);
            if (!target.sylls.length)
                target.sylls = aliasKey.split("");
            aliasCount++;
        }

        _index = index;
        _byId = byId;
        _stats = index.length + " 个应用 / " + aliasCount + " 别名";
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

    // ---------------- 启动器接口 ----------------

    function getItems(query) {
        const q = Match.normalizeQuery(query);
        if (!_ready || q.length < minQueryLength)
            return [];
        if (!/[a-z0-9]/.test(q))
            return [];

        const hits = [];
        for (let i = 0; i < _index.length; i++) {
            const item = _index[i];

            // 自定义别名优先，且不受「原生已命中就跳过」的限制（用户是显式指定）
            let score = Match.aliasScore(item.variants, q);
            if (score === 0) {
                if (_nativeHits(item, q))
                    continue;
                score = Match.variantScore(item.variants, q);
                if (score === 0)
                    score = Match.hybridScore(item.sylls, q);   // 混拼兜底：jisq -> 计算器
            }
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
            const subtitle = item.generic || item.comment || item.id;
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
