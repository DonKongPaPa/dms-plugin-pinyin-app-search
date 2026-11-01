// 纯匹配逻辑 —— 不依赖任何 QML 对象，便于用 node 直接单测。
// QML 里 `import "./data/match.js" as Match`；node 里 require() 也能用。

function normalizeQuery(q) {
    return String(q || "").toLowerCase().replace(/[\s\-_]+/g, "");
}

function normalizeAlias(a) {
    return String(a || "").toLowerCase().replace(/[^a-z0-9]/g, "");
}

// 用户自定义别名的匹配分：精确 > 前缀 > 包含
function aliasScore(variants, q) {
    var best = 0;
    for (var i = 0; i < variants.length; i++) {
        var v = variants[i];
        if (!v || !v.alias || !v.py)
            continue;
        var s = 0;
        if (v.py === q)
            s = 1040;
        else if (v.py.indexOf(q) === 0)
            s = 1020;
        else if (v.py.indexOf(q) !== -1)
            s = 1000;
        if (s > best)
            best = s;
    }
    return best;
}

// 自动生成的拼音/首字母候选：首字母完全 > 首字母前缀 > 全拼完全 > 全拼前缀 > 包含
function variantScore(variants, q) {
    var best = 0;
    for (var i = 0; i < variants.length; i++) {
        var v = variants[i];
        if (!v || v.alias)
            continue;
        var s = 0;
        if (v.ini === q)
            s = 1000;
        else if (v.ini.indexOf(q) === 0)
            s = 960;
        else if (v.py === q)
            s = 940;
        else if (v.py.indexOf(q) === 0)
            s = 920;
        else if (v.ini.indexOf(q) !== -1)
            s = 880;
        else if (v.py.indexOf(q) !== -1)
            s = 850;
        if (s > best)
            best = s;
    }
    return best;
}

// 逐字混合匹配：允许每个音节只取前 k 个字母，于是
//   ji + s + q   -> "jisq"，ji + suan + q -> "jisuanq"
// 只有在自动候选全都匹配不上时才用。DP 覆盖 reach[i][j] = 用前 i 个音节吃掉前 j 个查询字符。
function hybridScore(sylls, q) {
    if (!sylls || sylls.length === 0 || !q)
        return 0;
    var n = sylls.length;
    var m = q.length;
    var reach = [];
    var score = [];
    for (var i = 0; i <= n; i++) {
        reach.push([]);
        score.push([]);
        for (var j = 0; j <= m; j++) {
            reach[i].push(false);
            score[i].push(-9999);
        }
    }
    reach[0][0] = true;
    score[0][0] = 0;

    var best = 0;
    for (i = 0; i < n; i++) {
        var syl = sylls[i];
        if (!syl)
            continue;
        for (j = 0; j <= m; j++) {
            if (!reach[i][j])
                continue;
            var maxK = Math.min(syl.length, m - j);
            for (var k = 1; k <= maxK; k++) {
                if (q.substr(j, k) !== syl.substr(0, k))
                    break;
                var gain = (k === syl.length) ? 2 : -1;   // 吃满一个音节加分，吃掉半截扣分
                var nj = j + k;
                var ni = i + 1;
                if (!reach[ni][nj] || score[ni][nj] < score[i][j] + gain) {
                    reach[ni][nj] = true;
                    score[ni][nj] = score[i][j] + gain;
                }
                if (nj === m) {
                    var s = 760 + (score[i][j] + gain) * 5;
                    if (s > best)
                        best = s;
                }
            }
        }
    }
    return best;
}

// 名字 -> 候选串数组（多音字展开，最多 cap 个组合）。返回 [{py, ini}, ...]
function buildVariants(text, charReadings, cap) {
    var limit = cap || 6;
    var chars = String(text || "").split("");
    var combos = [{
        py: "",
        ini: ""
    }];

    for (var i = 0; i < chars.length; i++) {
        var ch = chars[i];
        var code = ch.codePointAt(0);
        var isCjk = (code >= 0x3400 && code <= 0x4DBF) || (code >= 0x4E00 && code <= 0x9FFF);
        var options;
        if (isCjk) {
            var readings = charReadings[ch];
            if (!readings)
                continue;                       // 字典里没有的生僻字跳过，不影响其余部分
            options = readings.slice(0, 3);
        } else if (/[a-zA-Z0-9]/.test(ch)) {
            options = [ch.toLowerCase()];
        } else {
            continue;                           // 空格、标点、符号忽略
        }

        var next = [];
        var full = false;
        for (var c = 0; c < combos.length && !full; c++) {
            for (var o = 0; o < options.length; o++) {
                next.push({
                    py: combos[c].py + options[o],
                    ini: combos[c].ini + options[o].charAt(0)
                });
                if (next.length >= limit) {
                    full = true;
                    break;
                }
            }
        }
        if (next.length === 0)
            return [];
        combos = next;
    }
    return dedupeVariants(combos);
}

function dedupeVariants(variants) {
    var seen = {};
    var out = [];
    for (var i = 0; i < variants.length; i++) {
        var v = variants[i];
        if (!v.py || seen[v.py])
            continue;
        seen[v.py] = true;
        out.push(v);
    }
    return out;
}

// 名字 -> 音节数组（每字一个音节；拉丁字母/数字单独成音节；标点空格跳过）
function syllables(text, charReadings) {
    var out = [];
    var chars = String(text || "").split("");
    for (var i = 0; i < chars.length; i++) {
        var ch = chars[i];
        var code = ch.codePointAt(0);
        var isCjk = (code >= 0x3400 && code <= 0x4DBF) || (code >= 0x4E00 && code <= 0x9FFF);
        if (isCjk) {
            var readings = charReadings[ch];
            if (readings && readings.length)
                out.push(readings[0]);
        } else if (/[a-zA-Z0-9]/.test(ch)) {
            out.push(ch.toLowerCase());
        }
    }
    return out;
}

// 把别名目标（应用名或 desktop id）解析成应用下标。
// 优先级：id 完全 → 名字完全 → 名字包含 → id 包含
function findAliasTarget(apps, target) {
    var t = String(target || "").trim().toLowerCase();
    if (!t || !apps || !apps.length)
        return -1;
    var i;
    for (i = 0; i < apps.length; i++)
        if (String(apps[i].id).toLowerCase() === t)
            return i;
    for (i = 0; i < apps.length; i++)
        if (String(apps[i].name).toLowerCase() === t)
            return i;
    for (i = 0; i < apps.length; i++)
        if (String(apps[i].name).toLowerCase().indexOf(t) !== -1)
            return i;
    for (i = 0; i < apps.length; i++)
        if (String(apps[i].id).toLowerCase().indexOf(t) !== -1)
            return i;
    return -1;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        normalizeQuery: normalizeQuery,
        normalizeAlias: normalizeAlias,
        aliasScore: aliasScore,
        variantScore: variantScore,
        hybridScore: hybridScore,
        buildVariants: buildVariants,
        dedupeVariants: dedupeVariants,
        syllables: syllables,
        findAliasTarget: findAliasTarget
    };
}
