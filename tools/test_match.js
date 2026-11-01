// 用真实字典 + 真实 match.js 跑匹配用例（node 直接跑，不依赖 QML）
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = require('path').resolve(__dirname, '..');
const dictSrc = fs.readFileSync(path.join(root, 'data/pinyin-dict.js'), 'utf8')
    .replace(/^\.pragma library\s*$/m, '');          // node 不认这个 QML 指令
const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(dictSrc + '\nthis.__syl = syllables; this.__poly = polyphones;', sandbox);

const charReadings = {};
for (const syl of Object.keys(sandbox.__syl)) {
    for (const ch of sandbox.__syl[syl]) charReadings[ch] = [syl];
}
Object.assign(charReadings, sandbox.__poly);           // 多音字覆盖为多读音数组

const M = require(path.join(root, 'data/match.js'));

function index(name) {
    return {
        name,
        variants: M.buildVariants(name, charReadings, 6),
        sylls: M.syllables(name, charReadings),
    };
}
function best(app, q) {
    const qq = M.normalizeQuery(q);
    const v = M.variantScore(app.variants, qq);
    return v > 0 ? { score: v, how: 'variant' }
                 : { score: M.hybridScore(app.sylls, qq), how: 'hybrid' };
}

const cases = [
    ['计算器', 'jsq', 'variant'],
    ['计算器', 'jisuanqi', 'variant'],
    ['计算器', 'jisq', 'hybrid'],            // ← 用户问的混拼
    ['计算器', 'jisuanq', 'variant'],
    ['计算器', 'jis', 'variant'],
    ['计算器', 'suq', 'none'],               // 不从首字开始不该命中
    ['文件', 'wenjian', 'variant'],
    ['文件', 'wj', 'variant'],
    ['黑神话：悟空', 'hshwk', 'variant'],
    ['黑神话：悟空', 'heishenhua', 'variant'],
    ['网易云音乐', 'yinyue', 'variant'],      // 多音字：乐 必须同时有 le / yue
    ['网易云音乐', 'wyyy', 'variant'],
    ['WPS 文字', 'wpswz', 'variant'],
    ['WPS 文字', 'wpswenz', 'variant'],
    ['计算器', 'xyz', 'none'],
];

let fail = 0;
for (const [name, q, expect] of cases) {
    const app = index(name);
    const r = best(app, q);
    const got = r.score > 0 ? r.how : 'none';
    const ok = got === expect;
    if (!ok) fail++;
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${name.padEnd(10)} ${q.padEnd(10)} expect=${expect.padEnd(8)} got=${got.padEnd(8)} score=${r.score}`);
}

// 别名
const aliases = [{ py: 'jisq2', ini: 'jisq2', alias: true }];
console.log(`\nalias exact  jisq2 -> ${M.aliasScore(aliases, 'jisq2')} (期望 1040)`);
console.log(`alias prefix jisq  -> ${M.aliasScore(aliases, 'jisq')} (期望 1020)`);
console.log(`alias miss   jsq   -> ${M.aliasScore(aliases, 'jsq')} (期望 0)`);

const apps = [
    { id: 'org.gnome.Calculator', name: '计算器' },
    { id: 'com.tencent.WeChat', name: '微信' },
    { id: 'brave-browser', name: 'Brave' },
];
console.log('\nfindAliasTarget 计算器 ->', M.findAliasTarget(apps, '计算器'));
console.log('findAliasTarget org.gnome.Calculator ->', M.findAliasTarget(apps, 'org.gnome.Calculator'));
console.log('findAliasTarget wechat ->', M.findAliasTarget(apps, 'wechat'));
console.log('findAliasTarget 不存在 ->', M.findAliasTarget(apps, '不存在的应用'));

console.log(`\n${fail === 0 ? 'ALL PASS' : fail + ' FAILED'}`);
process.exit(fail === 0 ? 0 : 1);
