/* ============================================================
   巴食 · AI 食谱 — 高保真 HTML 原型
   像素风 × 现代 · 低饱和绿色主调
   覆盖 UI-001 ~ UI-013 关键页面与状态（见 README.md）
   ============================================================ */

/* ---------- 像素调色板（与 prototype.css token 对齐） ---------- */
const PAL = {
  '#': '#39423B', // ink
  'g': '#5F8F6E', // green
  'G': '#476B52', // green deep
  'w': '#F4F1E7', // warm white
  'o': '#E9E5D9', // paper-2
  'a': '#B9904D', // amber
  'y': '#D9C68F', // noodle yellow
  'r': '#B0685B', // muted red
  'R': '#8F4C40', // deep red
  'b': '#6E8697', // muted blue
};

/* ---------- 像素图标位图（'.'=透明，其余字符查 PAL） ---------- */
const ICONS = {
  home: [
    '.....##......',
    '....####.....',
    '...######....',
    '..########...',
    '.##########..',
    '############.',
    '.##......##..',
    '.##.####.##..',
    '.##.####.##..',
    '.##.####.##..',
    '.##########..',
  ],
  book: [
    '.##########.',
    '.##......##.',
    '.##.####.##.',
    '.##......##.',
    '.##.####.##.',
    '.##......##.',
    '.##.####.##.',
    '.##......##.',
    '.##########.',
  ],
  plus: [
    '....##....',
    '....##....',
    '....##....',
    '##########',
    '##########',
    '....##....',
    '....##....',
    '....##....',
  ],
  user: [
    '...####...',
    '..######..',
    '..######..',
    '...####...',
    '....##....',
    '.########.',
    '##########',
    '##########',
    '##########',
  ],
  link: [
    '..######....',
    '.##....##...',
    '.##....##...',
    '..######....',
    '....##......',
    '....######..',
    '...##....##.',
    '...##....##.',
    '....######..',
  ],
  clipboard: [
    '....####....',
    '....#..#....',
    '..########..',
    '..#......#..',
    '..#.####.#..',
    '..#......#..',
    '..#.####.#..',
    '..#......#..',
    '..########..',
  ],
  camera: [
    '....####......',
    '..##########..',
    '.############.',
    '.##..####..##.',
    '.##.######.##.',
    '.##.######.##.',
    '.##..####..##.',
    '.############.',
  ],
  video: [
    '.########.....',
    '.##......###..',
    '.##......####.',
    '.##......###..',
    '.########.....',
  ],
  pen: [
    '.......##.',
    '......###.',
    '.....####.',
    '....###.#.',
    '...###..#.',
    '..###...#.',
    '.###....#.',
    '.##.....#.',
    '.##....##.',
    '.#######..',
  ],
  heart: [
    '.##...##..',
    '####.####.',
    '#########.',
    '#########.',
    '.#######..',
    '..#####...',
    '...###....',
    '....#.....',
  ],
  clock: [
    '..######..',
    '.########.',
    '##...##..#',
    '##...##..#',
    '##...####.',
    '##........',
    '.########.',
    '..######..',
  ],
  flame: [
    '....##....',
    '...###....',
    '...####...',
    '..####.#..',
    '..#####...',
    '.######...',
    '.###.##...',
    '.###.##...',
    '..####....',
  ],
  timer: [
    '....##....',
    '....##....',
    '..######..',
    '.########.',
    '.###..###.',
    '.###..##..',
    '.###......',
    '.########.',
    '..######..',
  ],
  bell: [
    '....##....',
    '..######..',
    '.########.',
    '.########.',
    '.########.',
    '##########',
    '....##....',
  ],
  search: [
    '..####....',
    '.##..##...',
    '.##..##...',
    '..####....',
    '...###....',
    '....###...',
    '.....###..',
    '......##..',
  ],
  trash: [
    '....##....',
    '##########',
    '..######..',
    '..#....#..',
    '..#.##.#..',
    '..#.##.#..',
    '..#.##.#..',
    '..######..',
  ],
  gear: [
    '....##....',
    '..######..',
    '.###..###.',
    '.##....##.',
    '.##....##.',
    '.###..###.',
    '..######..',
    '....##....',
  ],
  key: [
    '..###.....',
    '.##.##....',
    '.##.##....',
    '..###.....',
    '...#......',
    '...###....',
    '...#......',
    '...###....',
  ],
  shield: [
    '.########.',
    '.##.##.##.',
    '.##.##.##.',
    '.##....##.',
    '.##....##.',
    '..##..##..',
    '...####...',
    '....##....',
  ],
  download: [
    '....##....',
    '....##....',
    '....##....',
    '.########.',
    '..######..',
    '...####...',
  ],
  check: [
    '........##',
    '.......##.',
    '......##..',
    '##...##...',
    '.##.##....',
    '..###.....',
    '...#......',
  ],
  warn: [
    '....##....',
    '...####...',
    '...#..#...',
    '..#.##.#..',
    '..#.##.#..',
    '.#......#.',
    '.#.####.#.',
    '.########.',
  ],
  x: [
    '##....##',
    '.##..##.',
    '..####..',
    '...##...',
    '...##...',
    '..####..',
    '.##..##.',
    '##....##',
  ],
  chevL: [
    '....##.',
    '...##..',
    '..##...',
    '.##....',
    '.##....',
    '..##...',
    '...##..',
    '....##.',
  ],
  chevR: [
    '.##....',
    '..##...',
    '...##..',
    '....##.',
    '....##.',
    '...##..',
    '..##...',
    '.##....',
  ],
  chef: [
    '...######...',
    '..########..',
    '.##########.',
    '.##########.',
    '.##########.',
    '..########..',
    '...######...',
    '...######...',
    '...######...',
  ],
  bowl: [
    '.....##.....',
    '....####....',
    '..########..',
    '.##########.',
    '.##########.',
    '..########..',
    '...######...',
    '....####....',
  ],
  folder: [
    '..####......',
    '##########..',
    '##########..',
    '##......##..',
    '##......##..',
    '##......##..',
    '##########..',
  ],
  cloud: [
    '...####.....',
    '..######.##.',
    '.##########.',
    '.##########.',
    '..########..',
  ],
  refresh: [
    '...#####..',
    '..##...##.',
    '.##....##.',
    '.##.......',
    '.##....##.',
    '..##...##.',
    '...#####..',
  ],
  doc: [
    '.########.',
    '.##....##.',
    '.##.##.##.',
    '.##....##.',
    '.##.##.##.',
    '.##....##.',
    '.########.',
  ],
  image: [
    '.##########.',
    '.##..##...#.',
    '.##.####..#.',
    '.##..##..##.',
    '.##....###..',
    '.##########.',
  ],
  info: [
    '...####...',
    '....##....',
    '....##....',
    '...####...',
    '....##....',
    '....##....',
    '....##....',
    '...####...',
  ],
  drag: [
    '.##..##.',
    '.##..##.',
    '.##..##.',
    '.##..##.',
    '.##..##.',
  ],
  play: [
    '.##......',
    '.####....',
    '.######..',
    '.########',
    '.######..',
    '.####....',
    '.##......',
  ],
  pause: [
    '.##..##.',
    '.##..##.',
    '.##..##.',
    '.##..##.',
    '.##..##.',
  ],
  more: [
    '..##..##..##..',
  ],
  signal: [
    '........##',
    '......####',
    '....######',
    '..########',
    '##########',
  ],
  wifi: [
    '..######..',
    '.########.',
    '##########',
    '...####...',
    '....##....',
  ],
  battery: [
    '##########.#',
    '#........#.#',
    '#.######..##',
    '#.######..##',
    '#........#.#',
    '##########.#',
  ],
  copy: [
    '....######..',
    '....#....#..',
    '####.#..##..',
    '#..#.####...',
    '#..#.#......',
    '#..#.#......',
    '####.#####..',
    '....#....#..',
    '....######..',
  ],
  fridge: [
    '.##########.',
    '.##......##.',
    '.##......##.',
    '.##.##...##.',
    '.##########.',
    '.##......##.',
    '.##.##...##.',
    '.##......##.',
    '.##########.',
  ],
  carrot: [
    '......gg..',
    '.....gggg.',
    '....ggg...',
    '...aa.gg..',
    '..aaa.....',
    '.aaaaa....',
    '.aaaaa....',
    '..aaa.....',
    '...a......',
  ],
  egg: [
    '...####...',
    '..######..',
    '.########.',
    '.########.',
    '.########.',
    '.########.',
    '..######..',
    '...####...',
  ],
  milk: [
    '...#####..',
    '...#...#..',
    '..######..',
    '.########.',
    '.##.##.##.',
    '.##....##.',
    '.##....##.',
    '.########.',
  ],
  fish: [
    '....####...',
    '..########.',
    '.##..##.###',
    '.##########',
    '.##..##.###',
    '..########.',
    '....####...',
  ],
  cart: [
    '.##........',
    '.##........',
    '.#########.',
    '.#.......#.',
    '.#.#####.#.',
    '.#.......#.',
    '..##...##..',
    '..##...##..',
  ],
  snow: [
    '..#..#..',
    '.##.##..',
    '..###...',
    '#######.',
    '..###...',
    '.##.##..',
    '..#..#..',
  ],
};

/* ---------- 像素食物封面（16×16，多色） ---------- */
const FOODS = {
  noodle: {
    bg: '#E7DFC8',
    px: [
      '................',
      '.......yy.......',
      '......yyyy......',
      '.......yy.......',
      '....yyyyyyyy....',
      '...yyyyyyyyyy...',
      '...y..y..y..y...',
      '...yyyyyyyyyy...',
      '..gggggggggggg..',
      '..gggggggggggg..',
      '..gggggggggggg..',
      '...gggggggggg...',
      '....gggggggg....',
      '.....gggggg.....',
      '................',
    ],
  },
  tomato: {
    bg: '#F0DEDA',
    px: [
      '................',
      '.......g........',
      '......ggg.......',
      '....rrrrrrrr....',
      '...rrrrrrrrrr...',
      '..rrrrrrrrrrrr..',
      '..rrRrrrrrrrrr..',
      '..rrrrrrrrrrrr..',
      '..rrrrrrrrrrrr..',
      '..rrrrrrrrrrrr..',
      '...rrrrrrrrrr...',
      '....rrrrrrrr....',
      '................',
    ],
  },
  broccoli: {
    bg: '#DDE7DC',
    px: [
      '................',
      '.....gggggg.....',
      '....gggggggg....',
      '...ggGgGgGGgg...',
      '...gggggggggg...',
      '....gggggggg....',
      '.....GGGGGG.....',
      '.......GG.......',
      '.......GG.......',
      '......GGGG......',
      '.......GG.......',
      '......yyyy......',
      '................',
    ],
  },
  chicken: {
    bg: '#F1E7CF',
    px: [
      '................',
      '......aaaa......',
      '....aaaaaaaa....',
      '...aaaaaaaaaa...',
      '...aaaaaaaaaa...',
      '...aaaaaaaaa....',
      '....aaaaaa......',
      '.....aaaa.......',
      '......aa........',
      '.....ww.........',
      '....w.ww........',
      '................',
    ],
  },
  cucumber: {
    bg: '#DFE6EA',
    px: [
      '................',
      '................',
      '..gggggggggggg..',
      '.gGgGgGgGgGgGgG.',
      '.ggggggggggggg..',
      '..gggggggggggg..',
      '................',
      '....gggggggg....',
      '...gGgGgGgGgG...',
      '...gggggggggg...',
      '....gggggggg....',
      '................',
    ],
  },
  plate: {
    bg: '#E9E5D9',
    px: [
      '................',
      '....wwwwwwww....',
      '..wwwwwwwwwwww..',
      '..ww........ww..',
      '..ww........ww..',
      '..ww........ww..',
      '..wwwwwwwwwwww..',
      '....wwwwwwww....',
      '................',
    ],
  },
};

/* ---------- 位图渲染器 ---------- */
function renderBitmap(rows, px, bg) {
  const h = rows.length;
  const w = Math.max(...rows.map(r => r.length));
  let rects = '';
  if (bg) rects += `<rect width="${w}" height="${h}" fill="${bg}"/>`;
  rows.forEach((row, y) => {
    for (let x = 0; x < row.length; x++) {
      const c = PAL[row[x]];
      if (c) rects += `<rect x="${x}" y="${y}" width="1.02" height="1.02" fill="${c}"/>`;
    }
  });
  return `<svg class="pixel-img" width="${px}" height="${Math.round(px * h / w)}" viewBox="0 0 ${w} ${h}" shape-rendering="crispEdges" xmlns="http://www.w3.org/2000/svg">${rects}</svg>`;
}
function icon(name, px = 14, ink) {
  if (!ink) return renderBitmap(ICONS[name], px);
  const old = PAL['#'];
  PAL['#'] = ink;
  const out = renderBitmap(ICONS[name], px);
  PAL['#'] = old;
  return out;
}
function food(name, px = 80) {
  const f = FOODS[name] || FOODS.plate;
  return renderBitmap(f.px, px, f.bg);
}

/* ---------- 通用小件 ---------- */
function statusbar() {
  return `<div class="statusbar"><span>9:41</span><span class="sicons">${icon('signal', 11)}${icon('wifi', 11)}${icon('battery', 15)}</span></div>`;
}
function navbar(title, right = '', backTo = 'back') {
  return `<div class="navbar">
    <button class="nb-btn" data-go="${backTo}" aria-label="返回">${icon('chevL', 13)}</button>
    <div class="nb-title">${title}</div>
    <div class="nb-right">${right}</div>
  </div>`;
}
function tabbar(active) {
  const t = (key, ic, label) => `
    <button class="tab ${active === key ? 'active' : ''}" data-go="${key}">
      ${icon(ic, 17)}<span>${label}</span>
    </button>`;
  return `<nav class="tabbar">
    ${t('home', 'home', '首页')}
    ${t('library', 'book', '菜谱库')}
    ${t('fridge', 'fridge', '冰箱')}
    ${t('mine', 'user', '我的')}
  </nav>`;
}
function srcBadge(type, text) {
  return `<span class="src-badge src-${type}">${text}</span>`;
}

/* ============================================================
   页面定义
   ============================================================ */
const screens = {

  /* ---------- UI-001 欢迎页 ---------- */
  welcome: {
    title: '欢迎页 / 会话入口', idTag: 'UI-001', stateTag: '默认态',
    html: `
      <div class="page">
        <div class="hero-scene anim-in">
          <span class="spark s1"></span><span class="spark s2"></span><span class="spark s3"></span><span class="spark s4"></span>
          <div class="hero-chef anim-float">${icon('chef', 64)}</div>
          <div class="hero-ground"></div>
        </div>

        <div class="tac anim-in anim-d1" style="margin-top:18px;">
          <h1 style="font-size:28px;letter-spacing:7px;font-weight:800;">拾&nbsp;味</h1>
          <div class="px-label mt8">TASTE&nbsp;PIXEL&nbsp;·&nbsp;AI&nbsp;RECIPE</div>
          <p class="small mt8">把小红书 / 抖音上的菜谱，收进你的口袋厨房</p>
        </div>

        <div class="feat-list anim-in anim-d2" style="margin-top:20px;">
          <div class="feat-row">
            <span class="feat-ic">${icon('link', 15)}</span>
            <div class="grow"><b>链接一键导入</b><div class="tiny">AI 把图文 / 视频整理成结构化菜谱，确认后才保存</div></div>
          </div>
          <div class="feat-row">
            <span class="feat-ic">${icon('key', 15)}</span>
            <div class="grow"><b>不登录也能用 AI</b><div class="tiny">支持自定义 LLM API，Key 只加密保存在本机</div></div>
          </div>
          <div class="feat-row">
            <span class="feat-ic">${icon('shield', 15)}</span>
            <div class="grow"><b>隐私优先</b><div class="tiny">游客数据仅保存在本机，可一键禁止任何上传</div></div>
          </div>
        </div>

        <div class="anim-in anim-d3" style="margin-top:22px;">
          <button class="btn btn-primary btn-block btn-lg" data-action="login">${icon('user', 15)} 登录 / 注册</button>
          <div class="mt12"><button class="btn btn-ghost btn-block" data-go="home">游客继续，先逛逛 ${icon('chevR', 12)}</button></div>
          <div class="tac"><span class="anim-blink mono" style="display:inline-block;margin-top:14px;font-size:10px;font-weight:700;letter-spacing:3px;color:var(--green-deep);">▶ PRESS START</span></div>
        </div>

        <details class="fold mt20 anim-in anim-d4">
          <summary>${icon('shield', 13)} 隐私说明（游客模式数据仅保存在本机）</summary>
          <div class="fold-body">
            我们非常重视你的隐私。游客模式下，菜谱、分类、LLM API Key 等全部数据仅加密保存在本机，
            不会上传到任何服务器。登录后开启云同步时，本地游客数据将以“合并不覆盖”的方式同步到你的账号。
            自定义 LLM API 的请求直接由你的设备发往你配置的服务商，不经过我们的中转。
            你可以在「我的 → 隐私与上传设置」中随时禁止图片上传，禁止后 App 不会展示任何诱导上传的入口。
          </div>
        </details>
      </div>`,
  },

  /* ---------- UI-002 首页（默认） ---------- */
  home: {
    title: '首页', idTag: 'UI-002', stateTag: '默认态 · 游客', tab: 'home',
    html: `
      <div class="page">
        <div class="flex">
          <div class="grow">
            <div class="px-label">TUESDAY 07/28</div>
            <div style="font-size:20px;font-weight:800;letter-spacing:1px;">晚上好，今天吃什么？</div>
          </div>
          <button class="ri-tag ok" data-go="mine" style="cursor:pointer;font-family:inherit;flex:none;">游客 · GUEST</button>
        </div>

        <div class="notice amber mt12" data-go="progress" style="cursor:pointer;">
          <span class="n-ic">${icon('timer', 16)}</span>
          <div class="grow"><b>有 1 个未完成的导入</b>
            <div class="tiny">番茄炖牛腩 · 解析进行中，点这里继续处理</div>
          </div>
          ${icon('chevR', 13)}
        </div>

        <div class="card card-pad tonal mt16">
          <div class="px-label mb8">QUICK IMPORT · 快速导入</div>
          <div class="quick-grid">
            <button class="quick-btn" data-go="import-link"><span class="qb-ic">${icon('link', 17)}</span>粘贴链接</button>
            <button class="quick-btn" data-action="clipboard"><span class="qb-ic">${icon('clipboard', 17)}</span>剪贴板</button>
            <button class="quick-btn" data-action="camera"><span class="qb-ic">${icon('camera', 18)}</span>拍照选图</button>
            <button class="quick-btn" data-go="edit"><span class="qb-ic">${icon('pen', 16)}</span>手动创建</button>
          </div>
        </div>

        <div class="sec-title">分类<span class="more">更多分类 ›</span></div>
        <div class="chip-row">
          <button class="chip active">全部</button><button class="chip">快手菜</button>
          <button class="chip">下饭菜</button><button class="chip">汤羹</button>
          <button class="chip">烘焙</button><button class="chip">减脂餐</button>
        </div>

        <div class="sec-title">最近菜谱<span class="more">共 12 道 · 查看全部</span></div>
        <div class="recipe-card mb12" data-go="detail">
          <div class="cover steam">${food('tomato', 76)}</div>
          <div class="rc-body">
            <div class="rc-top">
              ${srcBadge('xhs', '小红书')}
              <span class="rc-fav" style="color:var(--red);">${icon('heart', 13)}</span>
            </div>
            <div class="rc-name">番茄炖牛腩（软烂入味版）</div>
            <div class="rc-meta">${icon('clock', 11)} 70 分钟 · 中等 · 3-4 人份</div>
          </div>
        </div>
        <div class="recipe-card" data-go="detail">
          <div class="cover">${food('broccoli', 76)}</div>
          <div class="rc-body">
            <div class="rc-top">
              ${srcBadge('dy', '抖音')}
              <span class="rc-fav" style="color:var(--ink-3);">${icon('heart', 13)}</span>
            </div>
            <div class="rc-name">蒜香西兰花（3 分钟快手菜，厨房小白零失败）</div>
            <div class="rc-meta">${icon('clock', 11)} 10 分钟 · 简单 · 1-2 人份</div>
          </div>
        </div>

        <div class="sec-title">收藏</div>
        <button class="row-item" data-go="library">
          <span class="ri-ic" style="background:var(--red-soft);">${icon('heart', 18)}</span>
          <span class="ri-body"><span class="ri-title">收藏的菜谱</span><span class="ri-desc">5 道 · 最近收藏「照烧鸡腿」</span></span>
          <span class="ri-arrow">${icon('chevR', 13)}</span>
        </button>
      </div>`,
  },

  /* ---------- UI-002 首页（空状态） ---------- */
  'home-empty': {
    title: '首页', idTag: 'UI-002', stateTag: '空状态', tab: 'home',
    html: `
      <div class="page">
        <div class="flex">
          <div class="grow">
            <div class="px-label">TUESDAY 07/28</div>
            <div style="font-size:20px;font-weight:800;letter-spacing:1px;">晚上好，今天吃什么？</div>
          </div>
          <button class="ri-tag ok" data-go="mine" style="cursor:pointer;font-family:inherit;flex:none;">游客 · GUEST</button>
        </div>

        <div class="card card-pad tonal mt16">
          <div class="px-label mb8">QUICK IMPORT · 快速导入</div>
          <div class="quick-grid">
            <button class="quick-btn" data-go="import-link"><span class="qb-ic">${icon('link', 17)}</span>粘贴链接</button>
            <button class="quick-btn" data-action="clipboard"><span class="qb-ic">${icon('clipboard', 17)}</span>剪贴板</button>
            <button class="quick-btn" data-action="camera"><span class="qb-ic">${icon('camera', 18)}</span>拍照选图</button>
            <button class="quick-btn" data-go="edit"><span class="qb-ic">${icon('pen', 16)}</span>手动创建</button>
          </div>
        </div>

        <div class="state-box">
          <div class="sb-ic">${food('plate', 56)}</div>
          <h3>还没有菜谱</h3>
          <p>粘贴小红书 / 抖音链接，或手动创建第一道菜。</p>
          <button class="btn btn-primary btn-block" data-go="add">${icon('plus', 13)} 导入菜谱</button>
          <button class="btn btn-ghost btn-block" data-go="edit">手动创建</button>
        </div>
      </div>`,
  },

  /* ---------- UI-003 添加入口 ---------- */
  add: {
    title: '添加入口', idTag: 'UI-003', stateTag: '默认态', tab: 'add',
    html: `
      <div class="page">
        <div class="px-label">NEW RECIPE</div>
        <div style="font-size:20px;font-weight:800;letter-spacing:1px;margin-bottom:12px;">添加菜谱</div>

        <div class="notice green mb16">
          <span class="n-ic">${icon('clipboard', 15)}</span>
          <div class="grow"><b>检测到剪贴板里有链接</b>
            <div class="tiny mono">https://www.xiaohongshu.com/explore/66a1…</div>
          </div>
          <button class="btn btn-sm btn-primary" data-go="import-link">导入</button>
        </div>

        <button class="row-item" data-go="import-link">
          <span class="ri-ic">${icon('link', 18)}</span>
          <span class="ri-body"><span class="ri-title">粘贴链接</span><span class="ri-desc">小红书 / 抖音公开链接，AI 自动整理成菜谱</span></span>
          <span class="ri-tag ok">无需登录</span>
        </button>
        <button class="row-item" data-action="paste-text">
          <span class="ri-ic">${icon('doc', 17)}</span>
          <span class="ri-body"><span class="ri-title">粘贴文本</span><span class="ri-desc">手动复制正文，交给 AI 整理结构</span></span>
          <span class="ri-tag ok">无需登录</span>
        </button>
        <button class="row-item" data-action="camera">
          <span class="ri-ic">${icon('camera', 19)}</span>
          <span class="ri-body"><span class="ri-title">导入图片</span><span class="ri-desc">菜谱截图 / 食材图，需要 OCR 能力</span></span>
          <span class="ri-tag warn">本地 OCR 待启用</span>
        </button>
        <button class="row-item" data-action="video">
          <span class="ri-ic">${icon('video', 18)}</span>
          <span class="ri-body"><span class="ri-title">导入视频</span><span class="ri-desc">本地视频，需要 ASR / OCR / LLM 能力</span></span>
          <span class="ri-tag warn">视能力而定</span>
        </button>
        <button class="row-item" data-go="edit">
          <span class="ri-ic">${icon('pen', 17)}</span>
          <span class="ri-body"><span class="ri-title">手动创建</span><span class="ri-desc">从零编辑一道菜谱，不需要任何 AI 能力</span></span>
          <span class="ri-tag ok">无需登录</span>
        </button>

        <p class="tiny mt8">剪贴板内容只在你点击「导入」后才会被使用，App 不会自动读取并发起网络请求。</p>
      </div>`,
  },

  /* ---------- UI-004 链接导入页 ---------- */
  'import-link': {
    title: '链接导入页', idTag: 'UI-004', stateTag: '默认态', tab: null,
    html: navbar('链接导入') + `
      <div class="page">
        <div class="field">
          <label>链接 <span style="margin-left:6px;">${srcBadge('xhs', '已识别 · 小红书')}</span></label>
          <input class="input mono" value="https://www.xiaohongshu.com/explore/66a1f2c9…" />
        </div>
        <div class="field">
          <label>备注（可选）</label>
          <input class="input" placeholder="比如：周末家宴试试这道" />
        </div>
        <div class="field">
          <label>目标分类</label>
          <select class="select"><option>下饭菜</option><option>快手菜</option><option>汤羹</option><option>烘焙</option></select>
        </div>

        <div class="card card-pad mt8">
          <div class="px-label mb8">CAPABILITY ROUTE · 本次将使用</div>
          <div class="flex mb8">${icon('check', 13)}<div class="grow small"><b>自定义 LLM API</b> · 已配置<div class="tiny">你的 Key 仅保存在本机，请求直达你的服务商</div></div><span class="conf conf-ok">可用</span></div>
          <div class="flex mb8">${icon('warn', 13)}<div class="grow small"><b>本地 OCR</b> · 识别能力待启用<div class="tiny">本次将跳过图片文字识别，正文足够时不影响结果</div></div><span class="conf conf-low">跳过</span></div>
          <div class="tiny" style="border-top:1.5px dashed var(--line);padding-top:8px;">如需识别图片中的文字，可到「设置 → OCR」启用云 OCR，或改为粘贴正文。</div>
        </div>

        <div class="mt16"><button class="btn btn-primary btn-block btn-lg" data-go="progress">${icon('play', 13)} 开始解析</button></div>
        <div class="mt12"><button class="btn btn-ghost btn-block" data-go="edit">改为手动创建</button></div>
      </div>`,
  },

  /* ---------- UI-005 解析进度页 ---------- */
  progress: {
    title: '解析进度页', idTag: 'UI-005', stateTag: '进行中 → 成功', tab: null,
    html: navbar('解析中', '', 'import-link') + `
      <div class="page">
        <div class="card card-pad flex mb16">
          <span class="ri-ic" style="width:34px;height:34px;">${icon('link', 16)}</span>
          <div class="grow">
            <div class="small" style="font-weight:700;">小红书链接</div>
            <div class="tiny mono">xiaohongshu.com/explore/66a1f2c9…</div>
          </div>
        </div>

        <div class="px-label" id="pgStageLabel">STAGE 4 / 6 · OCR</div>
        <div style="font-size:18px;font-weight:800;margin:4px 0 10px;" id="pgStageText">正在识别图片中的文字</div>
        <div class="progress mb12"><i id="pgBar" style="width:52%;"></i><b id="pgPct">52%</b></div>
        <div class="px-loader-row mb16">
          <div class="px-loader"><i></i><i></i><i></i><i></i></div>
          <span class="tiny">AI 正在逐块拼装你的菜谱，稍等片刻</span>
        </div>

        <div class="card card-pad">
          <div class="stepper" id="stepper">
            <div class="stp done"><span class="stp-dot">${icon('check', 10)}</span><div><div class="stp-name">已加入解析队列</div></div></div>
            <div class="stp done"><span class="stp-dot">${icon('check', 10)}</span><div><div class="stp-name">正在获取公开内容</div><div class="stp-desc">已拿到正文、3 张图片与元数据</div></div></div>
            <div class="stp done"><span class="stp-dot">${icon('check', 10)}</span><div><div class="stp-name">正在整理正文、图片和视频信息</div></div></div>
            <div class="stp current"><span class="stp-dot"></span><div><div class="stp-name">正在识别图片中的文字</div><div class="stp-desc">第 2 / 3 张…</div></div></div>
            <div class="stp"><span class="stp-dot"></span><div><div class="stp-name">正在生成结构化菜谱</div></div></div>
            <div class="stp"><span class="stp-dot"></span><div><div class="stp-name">正在检查结果格式</div></div></div>
          </div>
        </div>

        <div class="notice mt16" id="pgNotice">
          <span class="n-ic">${icon('info', 15)}</span>
          <div>解析在本地队列中执行，<b>可以离开本页</b>，首页会保留「继续处理」入口。</div>
        </div>

        <div class="mt16"><button class="btn btn-ghost btn-block" data-action="cancel-parse">取消解析</button></div>
      </div>`,
    init() { startProgressDemo(); },
    destroy() { stopProgressDemo(); },
  },

  /* ---------- UI-005 解析失败 / 降级 ---------- */
  'progress-fail': {
    title: '解析进度页', idTag: 'UI-005', stateTag: '失败 · 降级路径', tab: null,
    html: navbar('解析失败', '', 'import-link') + `
      <div class="page">
        <div class="state-box" style="padding-top:30px;">
          <div class="sb-ic" style="background:var(--red-soft);">${icon('warn', 40)}</div>
          <h3>暂时无法获取公开内容</h3>
          <p>链接可能已失效，或平台限制了访问。<br>别担心，还有几种方式可以继续：</p>
        </div>
        <button class="btn btn-block mb12" data-action="paste-text">${icon('doc', 14)} 粘贴正文继续</button>
        <button class="btn btn-block mb12" data-action="camera">${icon('image', 15)} 上传截图继续</button>
        <button class="btn btn-block mb12" data-action="video">${icon('video', 15)} 上传视频继续</button>
        <button class="btn btn-block mb12" data-go="edit">${icon('pen', 14)} 手动创建菜谱</button>
        <button class="btn btn-ghost btn-block" data-action="retry">${icon('refresh', 14)} 稍后重试</button>
        <p class="tiny tac mt12">失败详情仅记录在本地，不会上传任何数据。</p>
      </div>`,
  },

  /* ---------- UI-006 AI 草稿确认页 ---------- */
  draft: {
    title: 'AI 草稿确认页', idTag: 'UI-006', stateTag: '待确认 · 3 处低置信', tab: null,
    html: navbar('确认草稿', '<span class="tag amber">待确认</span>', 'add') + `
      <div class="page">
        <div class="card card-pad">
          <div class="flex">
            <div class="cover steam" style="width:64px;height:64px;">${food('tomato', 60)}</div>
            <div class="grow">
              <div class="flex"><b style="font-size:15px;">番茄炖牛腩</b><span style="color:var(--ink-3);">${icon('pen', 12)}</span></div>
              <div class="flex mt8">${srcBadge('xhs', '小红书')}<span class="tiny mono">xiaohongshu.com/…</span></div>
            </div>
          </div>
        </div>

        <div class="notice amber mt12">
          <span class="n-ic">${icon('warn', 15)}</span>
          <div><b>有 <span id="confCount">3</span> 处内容需要确认</b>
            <div class="tiny">AI 可能会识别错误，请检查食材和步骤；点击标记字段可查看依据。</div>
          </div>
        </div>

        <div class="flex mt12" style="flex-wrap:wrap;">
          <span class="chip active">下饭菜</span>
          <span class="chip">3-4 人份</span>
          <span class="chip">约 70 分钟</span>
          <span class="chip">中等难度</span>
        </div>

        <div class="sec-title">食材 · 8</div>
        <div class="card">
          <div class="ing-row"><span class="ing-check"></span><span class="ing-name">牛腩</span><span class="ing-amt">500 g</span></div>
          <div class="ing-row"><span class="ing-check"></span><span class="ing-name">番茄</span><span class="ing-amt">3 个</span></div>
          <div class="ing-row"><span class="ing-check"></span><span class="ing-name">土豆</span><span class="ing-note">可选</span><span class="ing-amt">1 个</span></div>
          <div class="ing-row" style="background:var(--amber-soft);"><span class="ing-check"></span><span class="ing-name">冰糖</span><button class="conf conf-low" data-conf>${icon('warn', 9)} 低置信度</button><span class="ing-amt">10 g</span></div>
          <div class="ing-row"><span class="ing-check"></span><span class="ing-name">姜片</span><span class="ing-amt">4 片</span></div>
          <div class="ing-row"><span class="ing-check"></span><span class="ing-name">生抽</span><span class="ing-amt">2 勺</span></div>
          <div class="ing-row"><span class="ing-check"></span><span class="ing-name">八角</span><span class="ing-amt">1 颗</span></div>
          <div class="ing-row"><span class="ing-check"></span><span class="ing-name">盐</span><span class="ing-amt">适量</span></div>
        </div>

        <div class="sec-title">步骤 · 6</div>
        <div class="step-card"><span class="sc-no">1</span><div class="sc-body">牛腩切大块，冷水下锅焯水，撇去浮沫后捞出。<div class="sc-tags"><span class="mini-tag">${icon('clock', 9)} 8 分钟</span><span class="mini-tag">${icon('flame', 9)} 大火</span></div></div></div>
        <div class="step-card"><span class="sc-no">2</span><div class="sc-body">番茄顶部划十字，开水烫 30 秒去皮，切块备用。</div></div>
        <div class="step-card" style="background:var(--amber-soft);"><span class="sc-no">3</span><div class="sc-body">冰糖炒出糖色，下牛腩翻炒均匀。<div class="sc-tags"><button class="conf conf-low" data-conf>${icon('warn', 9)} 时间待确认</button><span class="mini-tag">${icon('clock', 9)} 约 5 分钟</span></div></div></div>
        <div class="step-card"><span class="sc-no">4</span><div class="sc-body">加番茄块炒出沙，倒入热水没过食材，加生抽、八角、姜片。</div></div>
        <div class="step-card" style="background:var(--amber-soft);"><span class="sc-no">5</span><div class="sc-body">转小火慢炖。<div class="sc-tags"><button class="conf conf-low" data-conf>${icon('warn', 9)} 时长待确认</button><span class="mini-tag">${icon('clock', 9)} 40 分钟</span><span class="mini-tag">${icon('flame', 9)} 小火</span></div></div></div>
        <div class="step-card"><span class="sc-no">6</span><div class="sc-body">大火收汁，尝味补盐，出锅。</div></div>

        <details class="fold mt12">
          <summary>${icon('doc', 13)} 原始证据 · 来源文本 / OCR 片段</summary>
          <div class="fold-body">
            <p style="border-left:3px solid var(--green);padding-left:8px;margin-bottom:8px;">「…牛腩焯水后，冰糖炒糖色，下番茄炒出沙，小火咕嘟 40 分钟，软烂入味…」</p>
            <p class="tiny mono">OCR 片段（第 2 张图）：小火 40 分钟 · 冰糖 10g</p>
            <p class="tiny mt8">「冰糖 10g」来自图片 OCR，正文中未出现，因此标记为低置信度。</p>
          </div>
        </details>

        <div style="height:8px;"></div>
      </div>
      <div class="bottom-bar">
        <button class="btn btn-sm btn-danger" data-action="discard-draft">放弃</button>
        <button class="btn btn-sm btn-ghost" data-action="regen">重新生成</button>
        <button class="btn btn-sm" data-go="edit">继续编辑</button>
        <button class="btn btn-sm btn-primary grow" data-action="save-draft">${icon('check', 12)} 保存菜谱</button>
      </div>`,
  },

  /* ---------- UI-007 菜谱详情页 ---------- */
  detail: {
    title: '菜谱详情页', idTag: 'UI-007', stateTag: '默认态', tab: null,
    html: navbar('菜谱详情', `<button class="nb-btn" data-action="fav">${icon('heart', 13)}</button><button class="nb-btn" data-action="more">${icon('more', 13)}</button>`) + `
      <div class="steam-big" style="border-bottom:1px solid var(--line);display:flex;align-items:center;justify-content:center;padding:14px 0;background:var(--card-2);">${food('tomato', 150)}</div>
      <div class="page">
        <div class="flex">
          <div class="grow" style="font-size:19px;font-weight:800;letter-spacing:.5px;">番茄炖牛腩<span class="tiny" style="font-weight:400;">（软烂入味版）</span></div>
        </div>
        <div class="flex mt8" style="flex-wrap:wrap;">
          <span class="chip active">下饭菜</span><span class="chip">宴客</span>
          <span class="mini-tag">${icon('user', 9)} 3-4 人份</span>
          <span class="mini-tag">${icon('clock', 9)} 70 分钟</span>
          <span class="mini-tag">中等难度</span>
        </div>
        <div class="tiny mt8">来源：小红书 · 导入于 2026-07-20 · <span class="mono">查看原链接 ›</span></div>

        <div class="sec-title">食材 · 8</div>
        <div class="card">
          <div class="ing-row"><span class="ing-check">${icon('check', 9)}</span><span class="ing-name">牛腩</span><span class="ing-amt">500 g</span></div>
          <div class="ing-row"><span class="ing-check">${icon('check', 9)}</span><span class="ing-name">番茄</span><span class="ing-amt">3 个</span></div>
          <div class="ing-row"><span class="ing-check"></span><span class="ing-name">土豆</span><span class="ing-note">可选</span><span class="ing-amt">1 个</span></div>
          <div class="ing-row"><span class="ing-check"></span><span class="ing-name">冰糖</span><span class="ing-amt">10 g</span></div>
          <div class="ing-row"><span class="ing-check"></span><span class="ing-name">姜片</span><span class="ing-amt">4 片</span></div>
          <div class="ing-row"><span class="ing-check"></span><span class="ing-name">生抽</span><span class="ing-amt">2 勺</span></div>
          <div class="ing-row"><span class="ing-check"></span><span class="ing-name">八角</span><span class="ing-amt">1 颗</span></div>
          <div class="ing-row"><span class="ing-check"></span><span class="ing-name">盐</span><span class="ing-amt">适量</span></div>
        </div>

        <div class="sec-title">步骤 · 6</div>
        <div class="step-card"><span class="sc-no">1</span><div class="sc-body">牛腩切大块，冷水下锅焯水，撇去浮沫后捞出。<div class="sc-tags"><span class="mini-tag">${icon('clock', 9)} 8 分钟</span><span class="mini-tag">${icon('flame', 9)} 大火</span></div></div></div>
        <div class="step-card"><span class="sc-no">2</span><div class="sc-body">番茄顶部划十字，开水烫 30 秒去皮，切块备用。</div></div>
        <div class="step-card"><span class="sc-no">3</span><div class="sc-body">冰糖炒出糖色，下牛腩翻炒均匀。<div class="sc-tags"><span class="mini-tag">${icon('clock', 9)} 5 分钟</span><span class="mini-tag">${icon('flame', 9)} 中火</span></div></div></div>
        <div class="step-card"><span class="sc-no">4</span><div class="sc-body">加番茄块炒出沙，倒入热水没过食材，加生抽、八角、姜片。</div></div>
        <div class="step-card"><span class="sc-no">5</span><div class="sc-body">转小火慢炖 40 分钟，期间注意水量。<div class="sc-tags"><span class="mini-tag">${icon('clock', 9)} 40 分钟</span><span class="mini-tag">${icon('flame', 9)} 小火</span></div></div></div>
        <div class="step-card"><span class="sc-no">6</span><div class="sc-body">大火收汁，尝味补盐，出锅。</div></div>

        <div class="notice green mt12">
          <span class="n-ic">${icon('info', 15)}</span>
          <div><b>小贴士</b><div class="tiny">番茄分两次放：一半炒沙、一半最后 10 分钟放，口感更有层次。</div></div>
        </div>
        <div style="height:8px;"></div>
      </div>
      <div class="bottom-bar">
        <button class="icon-btn" data-go="edit" title="编辑">${icon('pen', 13)}</button>
        <button class="icon-btn" data-action="copy" title="复制">${icon('copy', 13)}</button>
        <button class="icon-btn" data-action="del" title="删除">${icon('trash', 13)}</button>
        <button class="btn btn-primary grow" data-go="cooking">${icon('flame', 13)} 开始烹饪</button>
      </div>`,
  },

  /* ---------- UI-008 编辑菜谱页 ---------- */
  edit: {
    title: '编辑菜谱页', idTag: 'UI-008', stateTag: '默认态 · 未保存提示', tab: null,
    html: navbar('编辑菜谱', '<span class="tag">手动模式</span>') + `
      <div class="page">
        <div class="field"><label>菜名</label><input class="input" value="番茄炖牛腩" /></div>
        <div class="field">
          <label>分类</label>
          <div class="flex" style="flex-wrap:wrap;"><span class="chip active">下饭菜</span><span class="chip">快手菜</span><span class="chip">汤羹</span><span class="chip">烘焙</span><span class="chip">${icon('plus', 9)} 新建</span></div>
        </div>
        <div class="field"><label>标签</label><input class="input" value="宴客、秋冬暖胃" /></div>
        <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:8px;">
          <div class="field"><label>份量</label><input class="input" value="3-4 人份" /></div>
          <div class="field"><label>总耗时</label><input class="input" value="70 分钟" /></div>
          <div class="field"><label>难度</label><select class="select"><option>中等</option><option>简单</option><option>困难</option></select></div>
        </div>

        <div class="sec-title">食材</div>
        <div id="ingList">
          <div class="edit-row"><span class="drag">${icon('drag', 10)}</span><input class="input grow" value="牛腩" /><input class="input" style="width:76px;" value="500 g" /><button class="icon-btn" data-action="del-row">${icon('x', 10)}</button></div>
          <div class="edit-row"><span class="drag">${icon('drag', 10)}</span><input class="input grow" value="番茄" /><input class="input" style="width:76px;" value="3 个" /><button class="icon-btn" data-action="del-row">${icon('x', 10)}</button></div>
          <div class="edit-row"><span class="drag">${icon('drag', 10)}</span><input class="input grow" value="冰糖" /><input class="input" style="width:76px;" value="10 g" /><button class="icon-btn" data-action="del-row">${icon('x', 10)}</button></div>
        </div>
        <button class="btn btn-sm" data-action="add-ing">${icon('plus', 10)} 添加食材</button>

        <div class="sec-title">步骤</div>
        <div id="stepList">
          <div class="edit-row" style="align-items:flex-start;"><span class="drag" style="margin-top:8px;">${icon('drag', 10)}</span><textarea class="textarea grow">牛腩切大块，冷水下锅焯水，撇去浮沫后捞出。</textarea><button class="icon-btn" data-action="del-row" style="margin-top:4px;">${icon('x', 10)}</button></div>
          <div class="edit-row" style="align-items:flex-start;"><span class="drag" style="margin-top:8px;">${icon('drag', 10)}</span><textarea class="textarea grow">冰糖炒出糖色，下牛腩翻炒均匀。</textarea><button class="icon-btn" data-action="del-row" style="margin-top:4px;">${icon('x', 10)}</button></div>
        </div>
        <button class="btn btn-sm" data-action="add-step">${icon('plus', 10)} 添加步骤</button>

        <div class="field mt16"><label>来源链接</label><input class="input mono" value="https://www.xiaohongshu.com/explore/66a1f2c9…" /></div>

        <div class="notice mt8">
          <span class="n-ic">${icon('info', 14)}</span>
          <div class="tiny">手动创建不需要任何 AI 能力；未保存离开时会二次确认，保存失败不会丢失已输入内容。</div>
        </div>
        <div style="height:8px;"></div>
      </div>
      <div class="bottom-bar">
        <button class="btn btn-ghost" data-action="cancel-edit">取消</button>
        <button class="btn btn-primary grow" data-action="save-edit">${icon('check', 12)} 保存菜谱</button>
      </div>`,
  },

  /* ---------- UI-009 菜谱库 ---------- */
  library: {
    title: '菜谱库 / 分类 / 搜索', idTag: 'UI-009', stateTag: '默认态（可实时搜索）', tab: 'library',
    html: `
      <div class="page">
        <div class="flex">
          <div class="grow" style="position:relative;">
            <span style="position:absolute;left:10px;top:50%;transform:translateY(-50%);color:var(--ink-3);">${icon('search', 14)}</span>
            <input class="input" id="libSearch" style="padding-left:32px;" placeholder="搜索菜名 / 食材 / 标签 / 备注" />
          </div>
          <select class="select" style="width:118px;flex:none;"><option>最近更新</option><option>最近查看</option><option>创建时间</option><option>名称</option></select>
        </div>
        <div class="chip-row mt12">
          <button class="chip active">全部 12</button><button class="chip">♥ 收藏 5</button>
          <button class="chip">快手菜</button><button class="chip">下饭菜</button>
          <button class="chip">汤羹</button><button class="chip">烘焙</button>
        </div>

        <div class="grid2 mt12" id="libGrid">
          <div class="tile-card" data-name="番茄炖牛腩 牛肉 宴客" data-go="detail"><div class="cover steam">${food('tomato', 120)}</div><div class="tc-body"><div class="tc-name">番茄炖牛腩（软烂入味版）</div><div class="tc-meta">${srcBadge('xhs', '小红书')} 70 分钟</div></div></div>
          <div class="tile-card" data-name="蒜香西兰花 快手菜 素菜" data-go="detail"><div class="cover">${food('broccoli', 120)}</div><div class="tc-body"><div class="tc-name">蒜香西兰花（3 分钟快手菜）</div><div class="tc-meta">${srcBadge('dy', '抖音')} 10 分钟</div></div></div>
          <div class="tile-card" data-name="照烧鸡腿 下饭 鸡肉" data-go="detail"><div class="cover">${food('chicken', 120)}</div><div class="tc-body"><div class="tc-name">照烧鸡腿饭</div><div class="tc-meta">${srcBadge('manual', '手动')} 25 分钟</div></div></div>
          <div class="tile-card" data-name="凉拌黄瓜 凉菜 快手菜" data-go="detail"><div class="cover">${food('cucumber', 120)}</div><div class="tc-body"><div class="tc-name">凉拌黄瓜（酸辣脆口）</div><div class="tc-meta">${srcBadge('img', '图片导入')} 8 分钟</div></div></div>
          <div class="tile-card" data-name="红烧排骨 宴客 猪肉" data-go="detail"><div class="cover">${food('noodle', 120)}</div><div class="tc-body"><div class="tc-name">红烧排骨（先炒糖色再炖）</div><div class="tc-meta">${srcBadge('xhs', '小红书')} 50 分钟</div></div></div>
          <div class="tile-card" data-name="葱油拌面 面食 快手菜" data-go="detail"><div class="cover">${food('plate', 120)}</div><div class="tc-body"><div class="tc-name">葱油拌面</div><div class="tc-meta">${srcBadge('dy', '抖音')} 12 分钟</div></div></div>
        </div>
        <p class="tiny tac mt12" id="libEmpty" style="display:none;">没有匹配的菜谱，换个关键词试试？</p>

        <button class="row-item mt16" data-action="recycle">
          <span class="ri-ic" style="background:var(--red-soft);">${icon('trash', 17)}</span>
          <span class="ri-body"><span class="ri-title">回收站</span><span class="ri-desc">2 个菜谱 · 保留 30 天，可恢复或彻底删除</span></span>
          <span class="ri-arrow">${icon('chevR', 13)}</span>
        </button>
      </div>`,
    init() {
      const input = document.getElementById('libSearch');
      if (!input) return;
      input.addEventListener('input', () => {
        const q = input.value.trim().toLowerCase();
        let visible = 0;
        document.querySelectorAll('#libGrid .tile-card').forEach(c => {
          const hit = !q || (c.dataset.name || '').toLowerCase().includes(q);
          c.style.display = hit ? '' : 'none';
          if (hit) visible++;
        });
        document.getElementById('libEmpty').style.display = visible ? 'none' : '';
      });
    },
  },

  /* ---------- UI-010 烹饪模式 ---------- */
  cooking: {
    title: '烹饪模式', idTag: 'UI-010', stateTag: '进行中 · 双计时器', tab: null,
    html: `<div class="cook-wrap">
      <div class="flex" style="padding:12px 16px;background-image:linear-gradient(90deg, rgba(255,255,255,.18) 50%, transparent 50%);background-size:8px 2px;background-repeat:repeat-x;background-position:bottom;">
        <button class="nb-btn cook-exit" data-action="exit-cook" aria-label="退出烹饪模式">${icon('x', 12, '#EDEAE0')}</button>
        <div class="px-label">COOKING MODE</div>
        <div style="margin-left:auto;font-size:12px;font-weight:700;">番茄炖牛腩</div>
      </div>

      <div class="page" style="flex:1;">
        <div class="flex">
          <span class="cook-step-no" id="cookStepNo">STEP 3 / 6</span>
          <span style="margin-left:auto;" class="cook-chip">${icon('flame', 11)} <span id="cookFlame">中火</span></span>
        </div>

        <div class="cook-card mt12" style="padding:20px 18px;">
          <div class="cook-big" id="cookText">冰糖炒出糖色，下牛腩翻炒均匀。</div>
          <div class="flex mt12" style="flex-wrap:wrap;" id="cookTags">
            <span class="cook-chip">${icon('clock', 11)} 5 分钟</span>
          </div>
        </div>

        <div class="px-label mt16 mb8">本步所需食材</div>
        <div class="flex" style="flex-wrap:wrap;" id="cookIngs">
          <span class="cook-chip">冰糖 10 g</span><span class="cook-chip">牛腩 500 g</span>
        </div>

        <div class="px-label mt16 mb8">TIMERS · 计时器</div>
        <div class="flex" style="flex-wrap:wrap;" id="timerArea"></div>
      </div>

      <div class="flex" style="padding:12px 14px 18px;background-image:linear-gradient(90deg, rgba(255,255,255,.18) 50%, transparent 50%);background-size:8px 2px;background-repeat:repeat-x;background-position:top;">
        <button class="cook-nav-btn" data-action="cook-prev">${icon('chevL', 13)} 上一步</button>
        <button class="cook-nav-btn primary" data-action="cook-next">下一步 ${icon('chevR', 13)}</button>
      </div>
    </div>`,
    init() { initCooking(); },
    destroy() { stopCooking(); },
  },

  /* ---------- UI-011 我的 ---------- */
  mine: {
    title: '我的 / 设置', idTag: 'UI-011', stateTag: '游客态', tab: 'mine',
    html: `
      <div class="page">
        <div class="card card-pad flex">
          <div class="avatar">${icon('user', 26)}</div>
          <div class="grow">
            <div style="font-size:16px;font-weight:800;">游客</div>
            <div class="tiny">本地数据仅保存在本机</div>
          </div>
          <button class="btn btn-sm btn-primary" data-action="login">登录 / 注册</button>
        </div>

        <div class="notice mt12">
          <span class="n-ic">${icon('cloud', 16)}</span>
          <div class="tiny"><b>游客模式下数据仅保存在本机。</b>登录后可开启云同步，游客数据会合并进账号，不会覆盖已有内容。</div>
        </div>

        <div class="sec-title">能力配置</div>
        <button class="row-item" data-go="llm">
          <span class="ri-ic">${icon('key', 17)}</span>
          <span class="ri-body"><span class="ri-title">LLM API 设置</span><span class="ri-desc">OpenAI-compatible · 模型 gpt-4o-mini</span></span>
          <span class="ri-tag ok">已配置</span>
        </button>
        <button class="row-item" data-go="ocr">
          <span class="ri-ic">${icon('image', 18)}</span>
          <span class="ri-body"><span class="ri-title">OCR 设置</span><span class="ri-desc">本地运行时健康检查已通过，识别能力待启用</span></span>
          <span class="ri-tag warn">待启用</span>
        </button>

        <div class="sec-title">隐私与数据</div>
        <button class="row-item" data-action="privacy">
          <span class="ri-ic">${icon('shield', 17)}</span>
          <span class="ri-body"><span class="ri-title">隐私与上传设置</span><span class="ri-desc">当前：禁止上传图片到云端</span></span>
          <span class="ri-arrow">${icon('chevR', 13)}</span>
        </button>
        <button class="row-item" data-action="export">
          <span class="ri-ic">${icon('download', 16)}</span>
          <span class="ri-body"><span class="ri-title">数据导出 / 备份</span><span class="ri-desc">导出全部菜谱为本地文件</span></span>
          <span class="ri-tag">P1</span>
        </button>
        <button class="row-item" data-action="about">
          <span class="ri-ic">${icon('info', 15)}</span>
          <span class="ri-body"><span class="ri-title">关于巴食</span><span class="ri-desc">v0.1.0 · 设计原型</span></span>
          <span class="ri-arrow">${icon('chevR', 13)}</span>
        </button>
      </div>`,
  },

  /* ---------- UI-012 LLM API 设置 ---------- */
  llm: {
    title: 'LLM API 设置页', idTag: 'UI-012', stateTag: '默认 + 测试失败态', tab: null,
    html: navbar('LLM API 设置', '', 'mine') + `
      <div class="page">
        <div class="field">
          <label>协议类型</label>
          <div class="flex" style="flex-wrap:wrap;">
            <span class="chip active">OpenAI-compatible</span><span class="chip">Gemini</span><span class="chip">其他兼容协议</span>
          </div>
        </div>
        <div class="field"><label>API Base URL</label><input class="input mono" value="https://api.your-llm.com/v1" /></div>
        <div class="field">
          <label>API Key</label>
          <div class="flex"><input class="input mono grow" value="••••••••••••••••" /><button class="btn btn-sm" data-action="clear-key">清空</button></div>
          <div class="hint">已保存的 Key 不会明文回显；重新输入即可更换，仅加密保存在本机。</div>
        </div>
        <div class="field"><label>模型名称</label><input class="input mono" value="gpt-4o-mini" /></div>
        <div class="field"><label>请求超时</label><select class="select"><option>60 秒</option><option>30 秒</option><option>120 秒</option></select></div>

        <button class="btn btn-block" data-action="test-conn">${icon('refresh', 13)} 测试连接</button>
        <div class="notice red mt12" id="testResult" style="display:none;">
          <span class="n-ic">${icon('warn', 15)}</span>
          <div class="tiny"><b>连接失败：无法访问该 Base URL。</b>请检查网络与地址是否正确。出于安全考虑，这里不会展示 Key、请求头或完整响应。</div>
        </div>

        <div class="notice green mt16">
          <span class="n-ic">${icon('info', 14)}</span>
          <div class="tiny">游客也可以配置自定义 LLM API，无需登录就能使用 AI 生成。</div>
        </div>
        <div style="height:8px;"></div>
      </div>
      <div class="bottom-bar">
        <button class="btn btn-primary btn-block" data-action="save-llm">${icon('check', 12)} 保存设置</button>
      </div>`,
  },

  /* ---------- UI-013 OCR 设置 ---------- */
  ocr: {
    title: 'OCR 设置页', idTag: 'UI-013', stateTag: '本地识别能力待启用', tab: null,
    html: navbar('OCR 设置', '', 'mine') + `
      <div class="page">
        <div class="card card-pad">
          <div class="px-label mb8">CURRENT ROUTE · 当前 OCR 路线</div>
          <div class="flex">
            <b style="font-size:15px;">本地 OCR</b>
            <span class="conf conf-low" style="margin-left:auto;">${icon('warn', 10)} 识别能力待启用</span>
          </div>
          <div class="tiny mt8">当前版本仅完成 ONNX Runtime 健康检查，真实图片识别尚未开放。在能力开放前，本页不会把本地 OCR 展示为「可识别图片」。</div>
        </div>

        <div class="sec-title">本地 OCR 插件</div>
        <div class="card">
          <div class="ing-row"><span class="ing-check">${icon('check', 9)}</span><div class="grow"><span class="ing-name">ONNX Runtime 健康检查</span><div class="tiny">运行时 v1.17 · 设备兼容</div></div><span class="conf conf-ok">通过</span></div>
          <div class="ing-row"><span class="ing-check"></span><div class="grow"><span class="ing-name">图片文字识别</span><div class="tiny">recognitionSupported = false</div></div><span class="conf conf-low">未启用</span></div>
        </div>

        <div class="sec-title">识别模型</div>
        <div class="card card-pad">
          <div class="flex"><b>中文印刷体模型</b><span class="tiny mono" style="margin-left:auto;">v0.3 · 46 MB</span></div>
          <div class="progress mt12"><i id="ocrDlBar" style="width:0%;"></i><b id="ocrDlPct">0%</b></div>
          <div class="flex mt12">
            <button class="btn btn-sm btn-primary grow" data-action="ocr-dl" id="ocrDlBtn">${icon('download', 12)} 下载模型</button>
            <button class="btn btn-sm btn-ghost" data-action="ocr-dl-cancel" id="ocrDlCancel" style="display:none;">取消</button>
          </div>
          <div class="tiny mt8">模型仅保存在本机；空间不足或下载失败时可重试。</div>
        </div>

        <div class="sec-title">云 OCR</div>
        <div class="card card-pad">
          <div class="flex"><b>云端文字识别</b><span class="ri-tag warn" style="margin-left:auto;">需登录</span></div>
          <div class="tiny mt8">按次计费，图片将上传到云端处理。登录后可在「隐私与上传设置」中随时关闭。</div>
          <button class="btn btn-sm btn-ghost mt12" data-action="login">登录后开启</button>
        </div>

        <div class="notice mt16">
          <span class="n-ic">${icon('shield', 14)}</span>
          <div class="tiny">隐私设置为「禁止上传图片」时，App 不会展示诱导开启云 OCR 的入口，只会建议使用本地 OCR 或手动录入。</div>
        </div>
        <div style="height:8px;"></div>
      </div>`,
  },

  /* ---------- UI-014 冰箱库存（轻拟物分区冰箱） ---------- */
  fridge: {
    title: '冰箱 · 库存', idTag: 'UI-014', stateTag: '分区冰箱 · 可筛选展开', tab: 'fridge',
    html: `
      <div class="page">
        <div class="seg mb12">
          <button class="seg-btn active">库存</button>
          <button class="seg-btn" data-go="fridge-reco">推荐</button>
        </div>

        <div class="flex mb12">
          <div class="grow">
            <b style="font-size:17px;">我的冰箱</b>
            <div class="tiny">10 种食材 · 9 个可用批次</div>
          </div>
          <button class="ri-tag ok" data-go="fridge-reco" style="cursor:pointer;font-family:inherit;flex:none;">去选择食材推荐</button>
        </div>

        <div class="notice amber mb12">
          <span class="n-ic">${icon('warn', 14)}</span>
          <div class="tiny"><b>2 样食材临期</b>：牛奶（08-05）、番茄批次 1（08-06），建议优先消耗。</div>
        </div>

        <div class="stat-grid cols4 mb12">
          <div class="stat-card"><div class="num">9</div><div class="tiny">可用批次</div></div>
          <div class="stat-card warn"><div class="num">2</div><div class="tiny">临期</div></div>
          <div class="stat-card exp"><div class="num">1</div><div class="tiny">已过期</div></div>
          <div class="stat-card"><div class="num" style="color:var(--blue);">1</div><div class="tiny">数量未知</div></div>
        </div>

        <div class="chip-row" id="fridgeFilters">
          <button class="chip active" data-filter="all">全部</button>
          <button class="chip" data-filter="soon">临期</button>
          <button class="chip" data-filter="expired">已过期</button>
          <button class="chip" data-filter="unknown">数量未知</button>
          <button class="chip" data-filter="chilled">冷藏</button>
          <button class="chip" data-filter="frozen">冷冻</button>
          <button class="chip" data-filter="room">常温</button>
          <button class="chip" data-filter="other">其他</button>
        </div>

        <div class="fridge-body" id="invList">
          <div class="fridge-door-line"></div>

          <details class="fridge-zone" data-zone="chilled" open>
            <summary class="zone-head">
              <span class="zone-ic">${icon('fridge', 14)}</span><b>冷藏区</b><span class="tiny">层架 · 5 种</span>
              <button class="icon-btn zone-add" data-go="fridge-add" title="放入冷藏区">${icon('plus', 10)}</button>
              <span class="agg-arrow">${icon('chevR', 11)}</span>
            </summary>
            <div class="zone-body">
              <div class="chip-grid">
                <div class="chip-wrap" data-f="soon chilled">
                  <button class="food-chip soon" data-action="chip-batches">
                    <span class="fc-ic">${icon('carrot', 15)}</span>
                    <span class="fc-text"><span class="fc-name">番茄</span><span class="fc-qty">共 3 个 · 2 批次</span></span>
                    <span class="conf conf-low">临期</span>
                  </button>
                  <div class="chip-batches" hidden>
                    <div class="batch-row">
                      <div class="grow"><b>2 个</b> <span class="tiny">· 购买 07-30 · 到期 08-06</span></div>
                      <span class="conf conf-low">临期</span>
                      <button class="icon-btn" data-go="fridge-add" title="编辑批次">${icon('pen', 11)}</button>
                      <button class="icon-btn" data-action="use-up" title="标记用完">${icon('check', 11)}</button>
                      <button class="icon-btn" data-action="discard" title="标记丢弃">${icon('trash', 11)}</button>
                    </div>
                    <div class="batch-row">
                      <div class="grow"><b>1 个</b> <span class="tiny">· 购买 08-02 · 到期 08-12</span></div>
                      <span class="conf conf-ok">正常</span>
                      <button class="icon-btn" data-go="fridge-add" title="编辑批次">${icon('pen', 11)}</button>
                      <button class="icon-btn" data-action="use-up" title="标记用完">${icon('check', 11)}</button>
                      <button class="icon-btn" data-action="discard" title="标记丢弃">${icon('trash', 11)}</button>
                    </div>
                  </div>
                </div>
                <div class="chip-wrap" data-f="ok chilled">
                  <button class="food-chip" data-go="fridge-add">
                    <span class="fc-ic">${icon('egg', 15)}</span>
                    <span class="fc-text"><span class="fc-name">鸡蛋</span><span class="fc-qty">6 枚 · 到期 08-12</span></span>
                    <span class="conf conf-ok">正常</span>
                  </button>
                </div>
                <div class="chip-wrap" data-f="soon chilled">
                  <button class="food-chip soon" data-go="fridge-add">
                    <span class="fc-ic">${icon('milk', 15)}</span>
                    <span class="fc-text"><span class="fc-name">牛奶</span><span class="fc-qty">1 盒 · 到期 08-05</span></span>
                    <span class="conf conf-low">临期</span>
                  </button>
                </div>
                <div class="chip-wrap" data-f="nodate chilled">
                  <button class="food-chip" data-go="fridge-add">
                    <span class="fc-ic">${icon('carrot', 15)}</span>
                    <span class="fc-text"><span class="fc-name">西兰花</span><span class="fc-qty">1 颗 · 未设置日期</span></span>
                    <span class="conf conf-gray">未设置日期</span>
                  </button>
                </div>
                <div class="chip-wrap" data-f="expired chilled">
                  <button class="food-chip expired" data-go="fridge-add">
                    <span class="fc-ic">${icon('carrot', 15)}</span>
                    <span class="fc-text"><span class="fc-name">菠菜</span><span class="fc-qty">1 把 · 已过期 · 不参与匹配</span></span>
                    <span class="conf conf-exp">已过期</span>
                  </button>
                </div>
              </div>
            </div>
          </details>

          <details class="fridge-zone zone-frozen" data-zone="frozen" open>
            <summary class="zone-head">
              <span class="zone-ic">${icon('snow', 13)}</span><b>冷冻区</b><span class="tiny">抽屉 · 2 种</span>
              <button class="icon-btn zone-add" data-go="fridge-add" title="放入冷冻区">${icon('plus', 10)}</button>
              <span class="agg-arrow">${icon('chevR', 11)}</span>
            </summary>
            <div class="zone-body">
              <div class="chip-grid">
                <div class="chip-wrap" data-f="ok frozen">
                  <button class="food-chip" data-go="fridge-add">
                    <span class="fc-ic">${icon('fish', 15)}</span>
                    <span class="fc-text"><span class="fc-name">牛腩</span><span class="fc-qty">500 g · 到期 09-15</span></span>
                    <span class="conf conf-ok">正常</span>
                  </button>
                </div>
                <div class="chip-wrap" data-f="ok frozen">
                  <button class="food-chip" data-go="fridge-add">
                    <span class="fc-ic">${icon('bowl', 14)}</span>
                    <span class="fc-text"><span class="fc-name">速冻饺子</span><span class="fc-qty">1 袋 · 未设置日期</span></span>
                    <span class="conf conf-gray">未设置日期</span>
                  </button>
                </div>
              </div>
              <div class="drawer-handle"></div>
            </div>
          </details>

          <details class="fridge-zone" data-zone="room" open>
            <summary class="zone-head">
              <span class="zone-ic">${icon('bowl', 14)}</span><b>常温区</b><span class="tiny">米面粮油 · 2 种</span>
              <button class="icon-btn zone-add" data-go="fridge-add" title="放入常温区">${icon('plus', 10)}</button>
              <span class="agg-arrow">${icon('chevR', 11)}</span>
            </summary>
            <div class="zone-body">
              <div class="chip-grid">
                <div class="chip-wrap" data-f="unknown room">
                  <button class="food-chip unknown" data-go="fridge-add">
                    <span class="fc-ic">${icon('bowl', 14)}</span>
                    <span class="fc-text"><span class="fc-name">冰糖</span><span class="fc-qty">数量未知 · 未设置日期</span></span>
                    <span class="conf conf-unknown">数量未知</span>
                  </button>
                </div>
                <div class="chip-wrap" data-f="nodate room">
                  <button class="food-chip" data-go="fridge-add">
                    <span class="fc-ic">${icon('bowl', 14)}</span>
                    <span class="fc-text"><span class="fc-name">大米</span><span class="fc-qty">2 kg · 未设置日期</span></span>
                    <span class="conf conf-gray">未设置日期</span>
                  </button>
                </div>
              </div>
            </div>
          </details>

          <details class="fridge-zone" data-zone="other" open>
            <summary class="zone-head">
              <span class="zone-ic">${icon('folder', 14)}</span><b>其他区</b><span class="tiny">待整理 · 0 种</span>
              <button class="icon-btn zone-add" data-go="fridge-add" title="放入其他区">${icon('plus', 10)}</button>
              <span class="agg-arrow">${icon('chevR', 11)}</span>
            </summary>
            <div class="zone-body">
              <div class="zone-empty">
                <div class="tiny">这个分区还是空的</div>
                <button class="btn btn-sm mt8" data-go="fridge-add">${icon('plus', 10)} 放入这个区域</button>
              </div>
            </div>
          </details>
        </div>
        <p class="tiny tac mt12" id="invEmpty" style="display:none;">该筛选下暂时没有食材。</p>
        <div style="height:8px;"></div>
      </div>`,
    init() {
      const chips = document.querySelectorAll('#fridgeFilters .chip');
      chips.forEach(c => c.addEventListener('click', () => {
        chips.forEach(x => x.classList.remove('active'));
        c.classList.add('active');
        const f = c.dataset.filter;
        let visible = 0;
        document.querySelectorAll('#invList .chip-wrap').forEach(w => {
          const hit = f === 'all' || (w.dataset.f || '').includes(f);
          w.style.display = hit ? '' : 'none';
          if (hit) visible++;
        });
        document.querySelectorAll('#invList .fridge-zone').forEach(z => {
          if (f === 'all' || f === 'other') { z.style.display = ''; return; }
          const any = [...z.querySelectorAll('.chip-wrap')].some(w => w.style.display !== 'none');
          z.style.display = any ? '' : 'none';
        });
        document.getElementById('invEmpty').style.display = visible || f === 'other' ? 'none' : '';
      }));
    },
  },

  /* ---------- UI-014 冰箱库存（空状态） ---------- */
  'fridge-empty': {
    title: '冰箱 · 库存', idTag: 'UI-014', stateTag: '空状态', tab: 'fridge',
    html: `
      <div class="page">
        <div class="seg mb16">
          <button class="seg-btn active">库存</button>
          <button class="seg-btn" data-go="fridge-reco">推荐</button>
        </div>
        <div class="state-box">
          <div class="sb-ic">${icon('fridge', 44)}</div>
          <h3>冰箱还是空的</h3>
          <p>添加第一样食材后，就能按库存推荐「现在就能做」的菜，并跟踪临期食材。</p>
          <button class="btn btn-primary btn-block" data-go="fridge-add">${icon('plus', 12)} 添加第一样食材</button>
          <button class="btn btn-ghost btn-block" data-go="library">先去看看菜谱库</button>
        </div>
      </div>`,
  },

  /* ---------- UI-015 库存批次新增 / 编辑 ---------- */
  'fridge-add': {
    title: '库存批次 · 新增 / 编辑', idTag: 'UI-015', stateTag: '默认态（同名提示）', tab: null,
    html: navbar('添加食材', '', 'fridge') + `
      <div class="page">
        <div class="field">
          <label>食材名称（必填）</label>
          <input class="input" id="batchName" placeholder="比如：番茄" />
          <div class="notice amber mt8" id="dupNotice" style="display:none;">
            <span class="n-ic">${icon('info', 13)}</span>
            <div class="tiny">已有同名食材的其他批次。保存后会<b>新增一个批次</b>，不会自动合并。</div>
          </div>
        </div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;">
          <div class="field"><label>数量（可为空）</label><input class="input" placeholder="比如：2" /></div>
          <div class="field"><label>单位（可为空）</label><select class="select"><option>个</option><option>克 g</option><option>毫升 ml</option><option>枚</option><option>颗</option><option>盒</option></select></div>
        </div>
        <div class="hint" style="margin:-6px 0 12px;">数量为空时保存为「数量未知」，不会默认写 0。</div>
        <div class="field"><label>分类</label><select class="select"><option>蔬菜</option><option>肉禽水产</option><option>蛋奶</option><option>水果</option><option>调味品</option><option>其他</option></select></div>
        <div class="field">
          <label>存放位置</label>
          <div class="flex" style="flex-wrap:wrap;"><span class="chip active">冷藏区</span><span class="chip">冷冻区</span><span class="chip">常温区</span><span class="chip">其他区</span></div>
          <div class="hint">默认跟随你点击「添加」的分区，可修改。</div>
        </div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;">
          <div class="field"><label>购买日期（可为空）</label><input class="input mono" placeholder="2026-08-04" /></div>
          <div class="field"><label>到期日期（可为空）</label><input class="input mono" placeholder="未设置则不提醒" /></div>
        </div>
        <div class="field"><label>备注</label><textarea class="textarea" placeholder="比如：菜市场买的小番茄，更甜"></textarea></div>

        <div class="notice mt8">
          <span class="n-ic">${icon('info', 13)}</span>
          <div class="tiny">编辑、标记用完和标记丢弃都只作用于当前批次；未保存离开会二次确认。</div>
        </div>
        <div style="height:8px;"></div>
      </div>
      <div class="bottom-bar">
        <button class="btn btn-ghost" data-go="fridge">取消</button>
        <button class="btn btn-primary grow" data-action="save-batch">${icon('check', 12)} 保存批次</button>
      </div>`,
    init() {
      const input = document.getElementById('batchName');
      const notice = document.getElementById('dupNotice');
      if (!input) return;
      input.addEventListener('input', () => {
        const dup = ['番茄', '鸡蛋', '牛奶', '牛腩', '西兰花', '冰糖'].includes(input.value.trim());
        notice.style.display = dup ? '' : 'none';
      });
    },
  },

  /* ---------- UI-016 选择食材推荐 ---------- */
  'fridge-reco': {
    title: '冰箱 · 选择食材推荐', idTag: 'UI-016', stateTag: '选择制 · 四分组', tab: 'fridge',
    html: `
      <div class="page">
        <div class="seg mb12">
          <button class="seg-btn" data-go="fridge">库存</button>
          <button class="seg-btn active">推荐</button>
        </div>

        <div class="px-label mb8">SELECT INGREDIENTS · 选择本次想用的食材</div>
        <div class="chip-row">
          <button class="chip" data-action="reco-all">全部</button>
          <button class="chip" data-action="reco-soon">临期优先</button>
          <button class="chip" data-action="reco-chilled">冷藏区</button>
          <button class="chip" data-action="reco-clear">清空选择</button>
        </div>

        <div class="sel-group">
          <div class="tiny mb8">冷藏区</div>
          <div class="chip-grid">
            <button class="food-chip soon selectable selected" data-f="soon chilled" data-action="reco-toggle"><span class="fc-ic">${icon('carrot', 15)}</span><span class="fc-text"><span class="fc-name">番茄</span><span class="fc-qty">3 个</span></span></button>
            <button class="food-chip selectable" data-f="ok chilled" data-action="reco-toggle"><span class="fc-ic">${icon('egg', 15)}</span><span class="fc-text"><span class="fc-name">鸡蛋</span><span class="fc-qty">6 枚</span></span></button>
            <button class="food-chip soon selectable" data-f="soon chilled" data-action="reco-toggle"><span class="fc-ic">${icon('milk', 15)}</span><span class="fc-text"><span class="fc-name">牛奶</span><span class="fc-qty">1 盒</span></span></button>
            <button class="food-chip selectable" data-f="nodate chilled" data-action="reco-toggle"><span class="fc-ic">${icon('carrot', 15)}</span><span class="fc-text"><span class="fc-name">西兰花</span><span class="fc-qty">1 颗</span></span></button>
            <button class="food-chip expired" disabled title="已过期，不参与匹配"><span class="fc-ic">${icon('carrot', 15)}</span><span class="fc-text"><span class="fc-name">菠菜</span><span class="fc-qty">已过期</span></span></button>
          </div>
        </div>
        <div class="sel-group">
          <div class="tiny mb8">冷冻区</div>
          <div class="chip-grid">
            <button class="food-chip selectable selected" data-f="ok frozen" data-action="reco-toggle"><span class="fc-ic">${icon('fish', 15)}</span><span class="fc-text"><span class="fc-name">牛腩</span><span class="fc-qty">500 g</span></span></button>
            <button class="food-chip selectable" data-f="ok frozen" data-action="reco-toggle"><span class="fc-ic">${icon('bowl', 14)}</span><span class="fc-text"><span class="fc-name">速冻饺子</span><span class="fc-qty">1 袋</span></span></button>
          </div>
        </div>
        <div class="sel-group">
          <div class="tiny mb8">常温区</div>
          <div class="chip-grid">
            <button class="food-chip unknown selectable" data-f="unknown room" data-action="reco-toggle"><span class="fc-ic">${icon('bowl', 14)}</span><span class="fc-text"><span class="fc-name">冰糖</span><span class="fc-qty">数量未知</span></span></button>
            <button class="food-chip selectable" data-f="nodate room" data-action="reco-toggle"><span class="fc-ic">${icon('bowl', 14)}</span><span class="fc-text"><span class="fc-name">大米</span><span class="fc-qty">2 kg</span></span></button>
          </div>
        </div>

        <div id="recoResults">
          <div class="sec-title">已具备 · 现在就能做 · 2</div>
          <div class="card card-pad mb12">
            <div class="flex">
              <div class="cover steam" style="width:56px;height:56px;">${food('tomato', 52)}</div>
              <div class="grow"><b style="font-size:14px;">番茄炖牛腩</b><div class="tiny">70 分钟 · 中等</div></div>
              <span class="conf conf-ok">匹配 5/5</span>
            </div>
            <div class="flex mt8" style="flex-wrap:wrap;">
              <span class="mini-tag hit">已选命中 · 番茄</span>
              <span class="mini-tag hit">已选命中 · 牛腩</span>
            </div>
            <div class="tiny mt8">推荐原因：主要食材全部在已选库存中</div>
            <div class="flex mt8" style="justify-content:flex-end;">
              <button class="btn btn-sm" data-go="detail">查看详情</button>
              <button class="btn btn-sm btn-primary" data-go="cooking">开始烹饪</button>
            </div>
          </div>
          <div class="card card-pad mb12">
            <div class="flex">
              <div class="cover steam" style="width:56px;height:56px;">${food('tomato', 52)}</div>
              <div class="grow"><b style="font-size:14px;">番茄炒蛋</b><div class="tiny">15 分钟 · 简单</div></div>
              <span class="conf conf-ok">匹配 2/2</span>
            </div>
            <div class="flex mt8" style="flex-wrap:wrap;">
              <span class="mini-tag hit">已选命中 · 番茄</span>
              <span class="mini-tag have">冰箱已有 · 可补选 · 鸡蛋</span>
            </div>
            <div class="tiny mt8">推荐原因：你只选了番茄；鸡蛋在库存中，虽未选择也可使用</div>
            <div class="flex mt8" style="justify-content:flex-end;">
              <button class="btn btn-sm" data-go="detail">查看详情</button>
              <button class="btn btn-sm btn-primary" data-go="cooking">开始烹饪</button>
            </div>
          </div>

          <div class="sec-title">缺 1 样 · 1</div>
          <div class="card card-pad mb12">
            <div class="flex">
              <div class="cover" style="width:56px;height:56px;">${food('chicken', 52)}</div>
              <div class="grow"><b style="font-size:14px;">照烧鸡腿饭</b><div class="tiny">25 分钟 · 简单</div></div>
              <span class="conf conf-low">匹配 3/4</span>
            </div>
            <div class="flex mt8" style="flex-wrap:wrap;">
              <span class="mini-tag miss">缺失 · 鸡腿 400 g</span>
              <span class="mini-tag have">冰箱已有 · 冰糖（数量需确认）</span>
            </div>
            <div class="tiny mt8">冰糖：有该食材，数量是否足够需确认</div>
            <div class="flex mt8" style="justify-content:flex-end;">
              <button class="btn btn-sm" data-action="shop-add">${icon('cart', 12)} 加入购物清单</button>
              <button class="btn btn-sm" data-go="detail">查看详情</button>
            </div>
          </div>

          <div class="sec-title">缺 2 样 · 1</div>
          <div class="card card-pad mb12">
            <div class="flex">
              <div class="cover" style="width:56px;height:56px;">${food('noodle', 52)}</div>
              <div class="grow"><b style="font-size:14px;">红烧排骨</b><div class="tiny">50 分钟 · 中等</div></div>
              <span class="conf conf-low">匹配 4/6</span>
            </div>
            <div class="flex mt8" style="flex-wrap:wrap;">
              <span class="mini-tag miss">缺失 · 排骨 500 g</span>
              <span class="mini-tag miss">缺失 · 生姜 1 块</span>
            </div>
            <div class="flex mt8" style="justify-content:flex-end;">
              <button class="btn btn-sm" data-action="shop-add">${icon('cart', 12)} 加入购物清单</button>
              <button class="btn btn-sm" data-go="detail">查看详情</button>
            </div>
          </div>

          <div class="sec-title">优先清库存 · 1</div>
          <div class="card card-pad mb12">
            <div class="flex">
              <div class="cover steam" style="width:56px;height:56px;">${food('tomato', 52)}</div>
              <div class="grow"><b style="font-size:14px;">糖拌番茄</b><div class="tiny">5 分钟 · 简单</div></div>
              <span class="conf conf-low">临期 ×2</span>
            </div>
            <div class="tiny mt8">推荐原因：优先消耗临期食材「番茄」（08-06 到期）、「牛奶」可作餐后</div>
            <div class="flex mt8" style="justify-content:flex-end;">
              <button class="btn btn-sm" data-go="detail">查看详情</button>
              <button class="btn btn-sm btn-primary" data-go="cooking">开始烹饪</button>
            </div>
          </div>

          <details class="fold mb12">
            <summary>${icon('more', 12)} 更多缺失（缺 3 样以上 · 2）</summary>
            <div class="fold-body">
              <p>宫保鸡丁 — 缺 鸡腿、花生、干辣椒、葱（4 样）</p>
              <p class="mt8">酸菜鱼 — 缺 草鱼、酸菜、泡椒（3 样）</p>
              <p class="tiny mt8">缺失超过 2 样默认折叠，不虚假标记为「能做」。</p>
            </div>
          </details>

          <div class="card card-pad tonal mt16">
            <div class="flex"><b>用现有食材生成新菜谱</b><span class="ri-tag ok" style="margin-left:auto;">LLM 已配置</span></div>
            <div class="tiny mt8">由你的自定义 LLM 生成，结果进入草稿确认页，不自动保存，也不与上方本地推荐混排。</div>
            <button class="btn btn-sm mt12" data-go="draft">${icon('refresh', 12)} 生成菜谱草稿</button>
          </div>
        </div>
        <div style="height:8px;"></div>
      </div>
      <div class="bottom-bar">
        <button class="btn btn-primary btn-block" id="recoCta" data-action="reco-run">${icon('check', 12)} 用已选食材推荐（2）</button>
      </div>`,
    init() { updateRecoCta(); },
  },

  /* ---------- UI-016 推荐分组样式 · 方案对比 ---------- */
  'reco-variants': {
    title: '推荐分组 · 方案对比', idTag: 'UI-016', stateTag: 'A / B / C / D 四方案', tab: null,
    html: `
      <div class="page">
        <div class="px-label mb8">GROUPING OPTIONS · 推荐结果分组样式</div>
        <p class="tiny">四个方案共用同一套色板与像素语法，仅分组承载形式不同。示例卡片内容相同，便于对比。</p>

        <!-- 方案 A -->
        <div class="opt-block">
          <div class="opt-label">方案 A · 像素旗标带</div>
          <div class="rg-ribbon rg-c-green">
            <span class="rg-band">已具备 · 现在就能做</span><span class="rg-count">2</span><span class="rg-line"></span>
          </div>
          <div class="card card-pad">
            <div class="flex">
              <div class="cover steam" style="width:48px;height:48px;">${food('tomato', 44)}</div>
              <div class="grow"><b style="font-size:13.5px;">番茄炖牛腩</b><div class="tiny">70 分钟 · 中等</div></div>
              <span class="conf conf-ok">匹配 5/5</span>
            </div>
          </div>
          <div class="rg-ribbon rg-c-amber">
            <span class="rg-band">缺 1 样</span><span class="rg-count">1</span><span class="rg-line"></span>
          </div>
          <div class="opt-note">色带即语义：绿=能做、琥珀=缺一点。扫读最快，游戏感最强。</div>
        </div>

        <!-- 方案 B -->
        <div class="opt-block">
          <div class="opt-label">方案 B · 大号像素编号</div>
          <div class="rg-num rg-c-green">
            <span class="rg-no">01</span>
            <div><div class="rg-name">已具备 · 现在就能做</div><div class="rg-en">READY TO COOK</div></div>
            <span class="rg-count">2 道</span>
          </div>
          <div class="rg-num-rule rg-c-green"></div>
          <div class="card card-pad">
            <div class="flex">
              <div class="cover steam" style="width:48px;height:48px;">${food('tomato', 44)}</div>
              <div class="grow"><b style="font-size:13.5px;">番茄炖牛腩</b><div class="tiny">70 分钟 · 中等</div></div>
              <span class="conf conf-ok">匹配 5/5</span>
            </div>
          </div>
          <div class="rg-num rg-c-amber">
            <span class="rg-no">02</span>
            <div><div class="rg-name">缺 1 样</div><div class="rg-en">MISSING ONE</div></div>
            <span class="rg-count">1 道</span>
          </div>
          <div class="rg-num-rule rg-c-amber"></div>
          <div class="opt-note">编号 + 英文眉题，杂志/菜单的编辑感，最“高级克制”。</div>
        </div>

        <!-- 方案 C -->
        <div class="opt-block">
          <div class="opt-label">方案 C · 货架吊牌</div>
          <div class="rg-tag rg-c-green">
            <span class="rg-tag-body"><i class="rg-hole"></i>${icon('check', 11)} 已具备 · 现在就能做</span>
            <span class="rg-string"></span><span class="rg-count">2</span>
          </div>
          <div class="rg-thread rg-c-green">
            <div class="card card-pad">
              <div class="flex">
                <div class="cover steam" style="width:48px;height:48px;">${food('tomato', 44)}</div>
                <div class="grow"><b style="font-size:13.5px;">番茄炖牛腩</b><div class="tiny">70 分钟 · 中等</div></div>
                <span class="conf conf-ok">匹配 5/5</span>
              </div>
            </div>
          </div>
          <div class="rg-tag rg-c-amber">
            <span class="rg-tag-body"><i class="rg-hole"></i>${icon('cart', 11)} 缺 1 样</span>
            <span class="rg-string"></span><span class="rg-count">1</span>
          </div>
          <div class="opt-note">吊牌打孔 + 挂绳 + 卡片沿牵引线垂下，和冰箱分区同属“生活器物”隐喻。</div>
        </div>

        <!-- 方案 D -->
        <div class="opt-block">
          <div class="opt-label">方案 D · 色条面板</div>
          <div class="rg-panel rg-c-green">
            <div class="rg-head"><b>已具备 · 现在就能做</b><span class="rg-count">2</span></div>
            <div class="card card-pad">
              <div class="flex">
                <div class="cover steam" style="width:48px;height:48px;">${food('tomato', 44)}</div>
                <div class="grow"><b style="font-size:13.5px;">番茄炖牛腩</b><div class="tiny">70 分钟 · 中等</div></div>
                <span class="conf conf-ok">匹配 5/5</span>
              </div>
            </div>
          </div>
          <div class="rg-panel rg-c-amber">
            <div class="rg-head"><b>缺 1 样</b><span class="rg-count">1</span></div>
            <div class="tiny">整组一个色调容器，分组边界最强，但页面色块最多。</div>
          </div>
          <div class="opt-note">分组感最强、最整齐；代价是色彩面积最大，组多时页面偏花。</div>
        </div>
        <div style="height:8px;"></div>
      </div>`,
  },

  /* ---------- UI-016 下厨后扣减确认 ---------- */
  'fridge-deduct': {
    title: '扣减确认面板', idTag: 'UI-016', stateTag: '面板 · 默认到期更早批次', tab: null,
    html: navbar('扣减确认', '', 'cooking') + `
      <div class="page">
        <div class="notice green">
          <span class="n-ic">${icon('check', 14)}</span>
          <div><b>「番茄炖牛腩」已完成！</b><div class="tiny">确认本次消耗的食材后，才会更新冰箱库存。</div></div>
        </div>

        <div class="sec-title">预计消耗 · 3</div>
        <div class="card">
          <div class="ing-row deduct-row">
            <button class="ing-check" data-action="deduct-toggle">${icon('check', 9)}</button>
            <div class="grow"><b>番茄</b><div class="tiny">默认消耗到期更早批次</div></div>
            <input class="input qty-input" value="2 个" />
            <select class="select batch-sel"><option>冷藏 · 08-06 临期</option><option>冷藏 · 08-12</option></select>
          </div>
          <div class="ing-row deduct-row">
            <button class="ing-check" data-action="deduct-toggle">${icon('check', 9)}</button>
            <div class="grow"><b>牛腩</b><div class="tiny">仅 1 个批次</div></div>
            <input class="input qty-input" value="500 g" />
            <select class="select batch-sel"><option>冷冻 · 09-15</option></select>
          </div>
          <div class="ing-row deduct-row">
            <button class="ing-check" data-action="deduct-toggle">${icon('check', 9)}</button>
            <div class="grow"><b>冰糖</b><div class="tiny" style="color:var(--amber);">数量未知，请确认用量</div></div>
            <input class="input qty-input" value="10 g" />
            <select class="select batch-sel"><option>常温 · 数量未知</option></select>
          </div>
        </div>

        <p class="tiny mt12">可逐项取消、修改数量或更换批次；取消、关闭或「暂不更新」时库存保持不变，不会产生负库存。</p>
        <div style="height:8px;"></div>
      </div>
      <div class="bottom-bar">
        <button class="btn btn-ghost" data-go="detail">暂不更新</button>
        <button class="btn btn-primary grow" data-action="deduct-confirm">${icon('check', 12)} 确认并更新冰箱</button>
      </div>`,
  },
};

/* ============================================================
   解析进度演示
   ============================================================ */
const PROGRESS_STAGES = [
  { label: 'STAGE 4 / 6 · OCR', text: '正在识别图片中的文字', pct: 52 },
  { label: 'STAGE 5 / 6 · LLM', text: '正在生成结构化菜谱', pct: 74 },
  { label: 'STAGE 6 / 6 · VALIDATE', text: '正在检查结果格式', pct: 92 },
  { label: 'READY FOR REVIEW', text: '解析完成，请确认后保存', pct: 100 },
];
let pgTimer = null;
function startProgressDemo() {
  let i = 0;
  pgTimer = setInterval(() => {
    i++;
    const label = document.getElementById('pgStageLabel');
    if (!label) { stopProgressDemo(); return; }
    if (i >= PROGRESS_STAGES.length) {
      stopProgressDemo();
      const notice = document.getElementById('pgNotice');
      if (notice) {
        notice.className = 'notice green mt16';
        notice.innerHTML = `<span class="n-ic">${icon('check', 14)}</span><div><b>解析完成，请确认后保存。</b>正在为你打开草稿确认页…</div>`;
      }
      setTimeout(() => go('draft'), 1100);
      return;
    }
    const s = PROGRESS_STAGES[i];
    label.textContent = s.label;
    document.getElementById('pgStageText').textContent = s.text;
    document.getElementById('pgBar').style.width = s.pct + '%';
    document.getElementById('pgPct').textContent = s.pct + '%';
    const steps = document.querySelectorAll('#stepper .stp');
    const currentIdx = 3 + i;
    steps.forEach((el, idx) => {
      el.classList.remove('current');
      if (idx < currentIdx) { el.classList.add('done'); el.querySelector('.stp-dot').innerHTML = icon('check', 10); }
      if (idx === currentIdx) { el.classList.add('current'); el.classList.remove('done'); el.querySelector('.stp-dot').innerHTML = ''; }
    });
  }, 1400);
}
function stopProgressDemo() { if (pgTimer) { clearInterval(pgTimer); pgTimer = null; } }

/* 推荐页：已选计数与 CTA */
function updateRecoCta() {
  const cta = document.getElementById('recoCta');
  if (!cta) return;
  const n = document.querySelectorAll('.food-chip.selectable.selected').length;
  cta.innerHTML = n
    ? `${icon('check', 12)} 用已选食材推荐（${n}）`
    : `${icon('refresh', 12)} 一键用全部库存推荐`;
}

/* ============================================================
   烹饪模式演示
   ============================================================ */
const COOK_STEPS = [
  { text: '牛腩切大块，冷水下锅焯水，撇去浮沫后捞出。', flame: '大火', time: 8 * 60, tags: [`${icon('clock', 11)} 8 分钟`], ings: ['牛腩 500 g', '姜片 2 片'] },
  { text: '番茄顶部划十字，开水烫 30 秒去皮，切块备用。', flame: '大火', time: 60, tags: [`${icon('clock', 11)} 1 分钟`], ings: ['番茄 3 个'] },
  { text: '冰糖炒出糖色，下牛腩翻炒均匀。', flame: '中火', time: 5 * 60, tags: [`${icon('clock', 11)} 5 分钟`], ings: ['冰糖 10 g', '牛腩 500 g'] },
  { text: '加番茄块炒出沙，倒入热水没过食材，加生抽、八角、姜片。', flame: '中火', time: 3 * 60, tags: [`${icon('clock', 11)} 3 分钟`], ings: ['番茄', '生抽 2 勺', '八角 1 颗'] },
  { text: '转小火慢炖 40 分钟，期间注意水量。', flame: '小火', time: 40 * 60, tags: [`${icon('clock', 11)} 40 分钟`], ings: ['热水适量'] },
  { text: '大火收汁，尝味补盐，出锅。', flame: '大火', time: 5 * 60, tags: [`${icon('clock', 11)} 5 分钟`], ings: ['盐适量'] },
];
let cookIdx = 2;
let cookTimers = {}; // stepIdx -> {left, running, done}
let cookTick = null;

function fmt(sec) {
  const m = String(Math.floor(sec / 60)).padStart(2, '0');
  const s = String(sec % 60).padStart(2, '0');
  return `${m}:${s}`;
}
function renderCookStep() {
  const st = COOK_STEPS[cookIdx];
  document.getElementById('cookStepNo').textContent = `STEP ${cookIdx + 1} / ${COOK_STEPS.length}`;
  document.getElementById('cookFlame').textContent = st.flame;
  document.getElementById('cookText').textContent = st.text;
  document.getElementById('cookTags').innerHTML = st.tags.map(t => `<span class="cook-chip">${t}</span>`).join('');
  document.getElementById('cookIngs').innerHTML = st.ings.map(i => `<span class="cook-chip">${i}</span>`).join('');
  renderTimers();
  const card = document.querySelector('.cook-card');
  if (card) { card.classList.remove('anim-in'); void card.offsetWidth; card.classList.add('anim-in'); }
}
function renderTimers() {
  const area = document.getElementById('timerArea');
  if (!area) return;
  const entries = Object.entries(cookTimers);
  let html = '';
  entries.forEach(([idx, t]) => {
    const label = t.done ? '完成' : fmt(t.left);
    html += `<span class="timer-chip ${t.done ? 'done' : ''}">${icon('timer', 13)} 步骤${Number(idx) + 1} · ${label}
      <button class="btn btn-sm" style="box-shadow:none;padding:2px 8px;" data-action="timer-toggle" data-idx="${idx}">${t.done ? '清除' : (t.running ? '暂停' : '继续')}</button></span>`;
  });
  const st = COOK_STEPS[cookIdx];
  if (!cookTimers[cookIdx]) {
    html += `<button class="timer-chip" style="cursor:pointer;border-style:dashed;" data-action="timer-start">${icon('play', 11)} 启动本步计时 · ${fmt(st.time)}</button>`;
  }
  area.innerHTML = html || '<span class="cook-chip">暂无计时器</span>';
}
function initCooking() {
  cookTimers = { 4: { left: 39 * 60 + 42, running: true, done: false } };
  renderCookStep();
  cookTick = setInterval(() => {
    let changed = false;
    Object.values(cookTimers).forEach(t => {
      if (t.running && !t.done) {
        t.left--;
        if (t.left <= 0) { t.left = 0; t.done = true; t.running = false; toast('计时结束：请回到对应步骤'); }
        changed = true;
      }
    });
    if (changed) renderTimers();
  }, 1000);
}
function stopCooking() { if (cookTick) { clearInterval(cookTick); cookTick = null; } }

/* ============================================================
   OCR 模型下载演示
   ============================================================ */
let ocrTimer = null;
function startOcrDownload() {
  const bar = document.getElementById('ocrDlBar');
  const pct = document.getElementById('ocrDlPct');
  const btn = document.getElementById('ocrDlBtn');
  const cancel = document.getElementById('ocrDlCancel');
  if (!bar) return;
  let p = 0;
  btn.style.display = 'none';
  cancel.style.display = '';
  ocrTimer = setInterval(() => {
    p = Math.min(100, p + Math.ceil(Math.random() * 9));
    bar.style.width = p + '%';
    pct.textContent = p + '%';
    if (p >= 100) {
      clearInterval(ocrTimer); ocrTimer = null;
      btn.style.display = '';
      btn.innerHTML = `${icon('check', 11)} 已下载（识别能力开放后可用）`;
      btn.classList.remove('btn-primary');
      cancel.style.display = 'none';
      toast('模型已下载到本机');
    }
  }, 260);
}
function cancelOcrDownload() {
  if (ocrTimer) { clearInterval(ocrTimer); ocrTimer = null; }
  const bar = document.getElementById('ocrDlBar');
  const pct = document.getElementById('ocrDlPct');
  const btn = document.getElementById('ocrDlBtn');
  const cancel = document.getElementById('ocrDlCancel');
  if (bar) { bar.style.width = '0%'; pct.textContent = '0%'; }
  if (btn) btn.style.display = '';
  if (cancel) cancel.style.display = 'none';
  toast('已取消下载');
}

/* ============================================================
   导航 / 工作台
   ============================================================ */
const GROUPS = [
  { label: '设计规范', items: [['spec', '设计规范 · TOKENS', 'v0']] },
  { label: 'UI-001 · 欢迎', items: [['welcome', '欢迎页 / 会话入口', '默认']] },
  {
    label: 'DESIGN-002 · 首页与菜谱管理', items: [
      ['home', '首页', '默认'],
      ['home-empty', '首页', '空状态'],
      ['library', '菜谱库 / 搜索', '默认'],
      ['detail', '菜谱详情页', '默认'],
      ['edit', '编辑菜谱页', '默认'],
    ],
  },
  {
    label: 'DESIGN-001 · 链接导入全流程', items: [
      ['add', '添加入口', '默认'],
      ['import-link', '链接导入页', '默认'],
      ['progress', '解析进度页', '进行中'],
      ['progress-fail', '解析进度页', '失败降级'],
      ['draft', 'AI 草稿确认页', '待确认'],
    ],
  },
  { label: 'DESIGN-004 · 烹饪模式', items: [['cooking', '烹饪模式', '计时中']] },
  {
    label: 'DESIGN-005 · 冰箱与推荐', items: [
      ['fridge', '冰箱库存', '分区冰箱'],
      ['fridge-empty', '冰箱库存', '空状态'],
      ['fridge-add', '批次新增/编辑', '默认'],
      ['fridge-reco', '选择食材推荐', '四分组'],
      ['reco-variants', '推荐分组 · 方案对比', 'A/B/C/D'],
      ['fridge-deduct', '扣减确认', '面板'],
    ],
  },
  {
    label: 'DESIGN-003 · 设置', items: [
      ['mine', '我的 / 设置', '游客态'],
      ['llm', 'LLM API 设置', '错误态'],
      ['ocr', 'OCR 设置', '待启用'],
    ],
  },
];

let history = ['home'];
let current = 'home';
let currentScreenObj = null;

function toast(msg) {
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(el._t);
  el._t = setTimeout(() => el.classList.remove('show'), 2200);
}

function go(key) {
  if (key === 'back') {
    if (history.length > 1) { history.pop(); key = history[history.length - 1]; }
    else key = 'home';
  } else {
    if (history[history.length - 1] !== key) history.push(key);
  }
  render(key);
}

function render(key) {
  if (currentScreenObj && currentScreenObj.destroy) currentScreenObj.destroy();
  cancelOcrDownloadSilent();
  current = key;

  document.querySelectorAll('.nav-item').forEach(n => n.classList.toggle('active', n.dataset.screen === key));

  const stageBody = document.getElementById('stageBody');
  const stageTitle = document.getElementById('stageTitle');
  const stageMeta = document.getElementById('stageMeta');

  if (key === 'spec') {
    stageTitle.textContent = '设计规范 · Design Tokens';
    stageMeta.innerHTML = `<span class="tag green">像素风 × 现代</span><span class="tag">低饱和绿</span><span class="tag">v0</span>`;
    stageBody.innerHTML = `<div class="spec">${specHtml()}</div>`;
    currentScreenObj = null;
    return;
  }

  const s = screens[key];
  if (!s) return;
  stageTitle.textContent = s.title;
  stageMeta.innerHTML = `<span class="tag green">${s.idTag}</span><span class="tag">${s.stateTag}</span><span class="tag">390px · 竖屏</span>`;

  const fabGo = key === 'fridge' ? 'fridge-add' : 'add';
  const fabLabel = key === 'fridge' ? '添加食材' : '添加菜谱';
  const phoneHtml = statusbar()
    + `<div class="screen">${s.html}</div>`
    + (s.tab ? tabbar(s.tab) : '')
    + ((s.tab && key !== 'add' && key !== 'fridge-reco') ? `<button class="fab-add" data-go="${fabGo}" aria-label="${fabLabel}">${icon('plus', 20, '#FDFDFB')}</button>` : '');
  stageBody.innerHTML = `<div class="phone">${phoneHtml}</div>`;
  currentScreenObj = s;
  if (s.init) s.init();
}
function cancelOcrDownloadSilent() { if (ocrTimer) { clearInterval(ocrTimer); ocrTimer = null; } }

/* ---------- 全局动作委托 ---------- */
document.addEventListener('click', (e) => {
  const navEl = e.target.closest('.nav-item');
  if (navEl) { go(navEl.dataset.screen); return; }

  const goEl = e.target.closest('[data-go]');
  if (goEl) { go(goEl.dataset.go); return; }

  const actEl = e.target.closest('[data-action]');
  if (!actEl) return;
  const a = actEl.dataset.action;

  switch (a) {
    case 'login': toast('演示环境：登录接口未接入，可先使用游客模式'); break;
    case 'clipboard': toast('已读取剪贴板（需用户确认后才会解析）'); go('import-link'); break;
    case 'camera': toast('本地 OCR 识别能力待启用，可在「我的 → OCR 设置」查看'); break;
    case 'video': toast('视频导入需要 ASR / OCR / LLM 能力，演示环境未接入'); break;
    case 'paste-text': toast('演示：打开文本粘贴面板'); break;
    case 'retry': toast('已重新加入解析队列'); go('progress'); break;
    case 'cancel-parse': toast('已取消，本次内容未保存'); go('import-link'); break;
    case 'discard-draft':
      if (confirm('确定放弃这份草稿吗？AI 生成内容将被丢弃。')) { toast('已放弃草稿'); go('add'); }
      break;
    case 'regen': {
      const old = actEl.innerHTML;
      actEl.innerHTML = `<span class="px-loader sm"><i></i><i></i><i></i></span>`;
      actEl.disabled = true;
      setTimeout(() => {
        actEl.innerHTML = old;
        actEl.disabled = false;
        toast('已重新生成，请再次确认');
      }, 1300);
      break;
    }
    case 'save-draft': toast('菜谱已保存'); go('detail'); break;
    case 'save-edit': toast('菜谱已保存'); go('detail'); break;
    case 'cancel-edit':
      if (confirm('有未保存的修改，确定离开吗？')) go('detail');
      break;
    case 'fav': {
      const on = actEl.classList.toggle('faved');
      actEl.innerHTML = icon('heart', 13, on ? '#AF6859' : null);
      actEl.classList.remove('anim-pop');
      void actEl.offsetWidth;
      actEl.classList.add('anim-pop');
      toast(on ? '已加入收藏' : '已取消收藏');
      break;
    }
    case 'more': toast('更多操作：移动分类 / 复制 / 删除'); break;
    case 'copy': toast('已复制为新菜谱（演示）'); break;
    case 'del':
      if (confirm('删除后将移入回收站，30 天内可恢复。确定删除吗？')) toast('已移入回收站');
      break;
    case 'add-ing': {
      const list = document.getElementById('ingList');
      if (list) list.insertAdjacentHTML('beforeend',
        `<div class="edit-row"><span class="drag">${icon('drag', 10)}</span><input class="input grow" placeholder="食材名" /><input class="input" style="width:76px;" placeholder="用量" /><button class="icon-btn" data-action="del-row">${icon('x', 10)}</button></div>`);
      break;
    }
    case 'add-step': {
      const list = document.getElementById('stepList');
      if (list) list.insertAdjacentHTML('beforeend',
        `<div class="edit-row" style="align-items:flex-start;"><span class="drag" style="margin-top:8px;">${icon('drag', 10)}</span><textarea class="textarea grow" placeholder="这一步要做什么？"></textarea><button class="icon-btn" data-action="del-row" style="margin-top:4px;">${icon('x', 10)}</button></div>`);
      break;
    }
    case 'del-row': actEl.closest('.edit-row').remove(); break;
    case 'test-conn': {
      const old = actEl.innerHTML;
      actEl.innerHTML = `<span class="px-loader sm"><i></i><i></i><i></i></span> 测试中`;
      actEl.disabled = true;
      const r0 = document.getElementById('testResult');
      if (r0) r0.style.display = 'none';
      setTimeout(() => {
        actEl.innerHTML = old;
        actEl.disabled = false;
        const r = document.getElementById('testResult');
        if (r) { r.style.display = ''; r.classList.add('anim-in'); }
        toast('测试失败：无法访问该 Base URL');
      }, 1500);
      break;
    }
    case 'clear-key': toast('已清空保存的 Key'); actEl.previousElementSibling.value = ''; break;
    case 'save-llm': toast('LLM 设置已保存'); break;
    case 'ocr-dl': startOcrDownload(); break;
    case 'ocr-dl-cancel': cancelOcrDownload(); break;
    case 'privacy': toast('隐私与上传设置（演示）：当前禁止上传图片'); break;
    case 'export': toast('数据导出为 P1 功能，暂未开放'); break;
    case 'about': toast('巴食 v0.1.0 · 高保真设计原型'); break;
    case 'recycle': toast('回收站：可恢复或二次确认后彻底删除（演示）'); break;
    case 'use-up': {
      const row = actEl.closest('.agg-item, .batch-row');
      if (row) row.remove();
      toast('已标记用完（仅当前批次）');
      break;
    }
    case 'discard':
      if (confirm('确认丢弃该批次？此操作只影响当前批次，不会删除同名食材的其他批次。')) {
        const row = actEl.closest('.agg-item, .batch-row');
        if (row) row.remove();
        toast('已标记丢弃');
      }
      break;
    case 'save-batch': toast('批次已保存'); go('fridge'); break;
    case 'shop-add': toast('已加入购物清单（按名称与单位尝试合并，演示）'); break;
    case 'chip-batches': {
      const wrap = actEl.closest('.chip-wrap');
      const list = wrap ? wrap.querySelector('.chip-batches') : null;
      if (list) list.hidden = !list.hidden;
      break;
    }
    case 'reco-toggle': actEl.classList.toggle('selected'); updateRecoCta(); break;
    case 'reco-all':
      document.querySelectorAll('.food-chip.selectable').forEach(c => c.classList.add('selected'));
      updateRecoCta(); break;
    case 'reco-soon':
      document.querySelectorAll('.food-chip.selectable').forEach(c => c.classList.toggle('selected', (c.dataset.f || '').includes('soon')));
      updateRecoCta(); break;
    case 'reco-chilled':
      document.querySelectorAll('.food-chip.selectable').forEach(c => c.classList.toggle('selected', (c.dataset.f || '').includes('chilled')));
      updateRecoCta(); break;
    case 'reco-clear':
      document.querySelectorAll('.food-chip.selectable').forEach(c => c.classList.remove('selected'));
      updateRecoCta(); break;
    case 'reco-run': {
      const n = document.querySelectorAll('.food-chip.selectable.selected').length;
      toast(n ? `已按 ${n} 种已选食材重新匹配（演示）` : '已用全部库存推荐（演示）');
      const r = document.getElementById('recoResults');
      if (r) { r.classList.remove('anim-in'); void r.offsetWidth; r.classList.add('anim-in'); }
      break;
    }
    case 'deduct-toggle': {
      const row = actEl.closest('.deduct-row');
      const on = actEl.dataset.on !== 'off';
      actEl.dataset.on = on ? 'off' : 'on';
      actEl.innerHTML = on ? '' : icon('check', 9);
      if (row) row.style.opacity = on ? '.45' : '';
      break;
    }
    case 'deduct-confirm': toast('冰箱库存已更新'); go('fridge'); break;
    case 'pop-demo':
      actEl.classList.remove('anim-pop');
      void actEl.offsetWidth;
      actEl.classList.add('anim-pop');
      break;
    case 'exit-cook':
      if (confirm('是否退出烹饪模式？进行中的计时器会保留在后台。')) go('detail');
      break;
    case 'cook-prev':
      if (cookIdx > 0) { cookIdx--; renderCookStep(); } else toast('已经是第一步');
      break;
    case 'cook-next':
      if (cookIdx < COOK_STEPS.length - 1) { cookIdx++; renderCookStep(); }
      else { toast('全部步骤完成，出锅吧'); setTimeout(() => go('fridge-deduct'), 600); }
      break;
    case 'timer-start': {
      cookTimers[cookIdx] = { left: COOK_STEPS[cookIdx].time, running: true, done: false };
      renderTimers();
      toast(`已启动步骤 ${cookIdx + 1} 的计时器`);
      break;
    }
    case 'timer-toggle': {
      const idx = actEl.dataset.idx;
      const t = cookTimers[idx];
      if (t) {
        if (t.done) { delete cookTimers[idx]; }
        else t.running = !t.running;
        renderTimers();
      }
      break;
    }
  }

  // 草稿页：低置信度 → 已确认
  const confEl = e.target.closest('[data-conf]');
  if (confEl) {
    if (confEl.classList.contains('conf-low')) {
      confEl.classList.remove('conf-low');
      confEl.classList.add('conf-ok');
      confEl.innerHTML = `${icon('check', 9)} 已确认`;
      const row = confEl.closest('.ing-row, .step-card');
      if (row) row.style.background = '';
      const c = document.getElementById('confCount');
      if (c) c.textContent = Math.max(0, Number(c.textContent) - 1);
    } else {
      toast('依据：原文「冰糖炒糖色」/ OCR 片段「冰糖 10g」');
    }
  }
});

/* ============================================================
   设计规范页
   ============================================================ */
function specHtml() {
  const sw = (name, hex, color) => `<div class="swatch"><div class="sw-color" style="background:${color};"></div><div class="sw-info"><div class="sw-name">${name}</div><div class="sw-hex">${hex}</div></div></div>`;
  return `
    <div class="card card-pad mt12">
      <div class="px-label mb8">DESIGN PRINCIPLES · 设计原则</div>
      <p class="small">像素风作为视觉语言（硬边投影、位图图标、抖动纹理、等宽字体标签），现代布局作为骨架（卡片、留白、层级）。
      主色为低饱和青灰绿，全局降饱和，保证厨房场景长时间使用不疲劳。颜色从不作为唯一状态提示——所有状态都伴随图标或文字标签。</p>
    </div>

    <h3>色板 · 低饱和绿色系</h3>
    <div class="swatch-grid">
      ${sw('主色 GREEN', '#5F8F6E', '#5F8F6E')}
      ${sw('深绿 DEEP', '#476B52', '#476B52')}
      ${sw('墨绿文字 INK', '#39423B', '#39423B')}
      ${sw('浅绿底 SOFT', '#DDE7DC', '#DDE7DC')}
      ${sw('纸面 PAPER', '#F2EFE7', '#F2EFE7')}
      ${sw('卡片 CARD', '#FBFAF4', '#FBFAF4')}
      ${sw('辅助琥珀 AMBER', '#B9904D', '#B9904D')}
      ${sw('辅助红 RED', '#B0685B', '#B0685B')}
      ${sw('辅助蓝灰 BLUE', '#6E8697', '#6E8697')}
      ${sw('分隔线 LINE', '#D5D0C1', '#D5D0C1')}
    </div>

    <h3>字体</h3>
    <div class="card card-pad">
      <div style="font-size:22px;font-weight:800;">巴食 · 标题 20-28px / 800</div>
      <div style="font-size:14px;margin-top:6px;">正文 13-14px / PingFang SC · 行高 1.6，支持系统字体缩放，不依赖固定高度。</div>
      <div class="px-label mt8">PIXEL LABEL · COURIER NEW 10PX · 等宽字体用于阶段、编号、时间</div>
    </div>

    <h3>组件</h3>
    <div class="card demo-box">
      <button class="btn btn-primary btn-sm">主按钮</button>
      <button class="btn btn-sm">次按钮</button>
      <button class="btn btn-ghost btn-sm">幽灵按钮</button>
      <button class="btn btn-danger btn-sm">危险操作</button>
      <span class="chip active">分类 Chip</span>
      <span class="chip">未选中</span>
      ${srcBadge('xhs', '小红书')}${srcBadge('dy', '抖音')}${srcBadge('manual', '手动')}${srcBadge('img', '图片导入')}
      <span class="conf conf-low">${icon('warn', 9)} 低置信度</span>
      <span class="conf conf-ok">${icon('check', 9)} 已确认</span>
    </div>
    <div class="card demo-box mt12">
      <div style="width:220px;"><div class="px-label mb8">PROGRESS</div><div class="progress"><i style="width:64%;"></i><b>64%</b></div></div>
      <div style="width:150px;"><div class="px-label mb8">SWITCH</div><span class="switch on"><i></i></span> <span class="switch"><i></i></span></div>
      <div><div class="px-label mb8">ICONS</div><div class="flex">${icon('home', 18)}${icon('book', 18)}${icon('timer', 18)}${icon('flame', 18)}${icon('heart', 18)}${icon('search', 18)}${icon('shield', 18)}${icon('key', 18)}</div></div>
    </div>

    <h3>像素语法</h3>
    <div class="card demo-box">
      <div>
        <div class="px-label mb8">阶梯缺角 · 外收矩形角</div>
        <div class="flex">
          <div style="width:64px;height:44px;background:var(--green-soft);clip-path:var(--pxc-lg);box-shadow:inset 0 0 0 2px var(--green-deep);"></div>
          <div style="width:52px;height:36px;background:var(--green-soft);clip-path:var(--pxc-sm);box-shadow:inset 0 0 0 2px var(--green-deep);"></div>
          <div style="width:40px;height:28px;background:var(--green-soft);clip-path:var(--pxc-xs);box-shadow:inset 0 0 0 2px var(--green-deep);"></div>
        </div>
        <div class="tiny mt8">大 8px 双阶梯（卡片）/ 中 4px（按钮、输入）/ 小 3px（徽标）</div>
      </div>
      <div><div class="px-label mb8">硬边投影（跟随缺角）</div><button class="btn btn-sm">DROP-SHADOW 3 3 0</button></div>
      <div><div class="px-label mb8">抖动纹理</div><div class="card dither" style="width:110px;height:64px;"></div></div>
      <div><div class="px-label mb8">位图食物封面</div><div class="flex">${food('tomato', 44)}${food('noodle', 44)}${food('broccoli', 44)}${food('chicken', 44)}</div></div>
    </div>

    <h3>像素动效 · STEPS 阶梯缓动</h3>
    <div class="card demo-box">
      <div><div class="px-label mb8">蒸汽 px-steam</div><div class="cover steam" style="width:64px;height:64px;">${food('tomato', 64)}</div></div>
      <div><div class="px-label mb8">闪烁 px-blink</div><span class="anim-blink mono" style="font-weight:700;letter-spacing:2px;color:var(--green-deep);">▶ PRESS START</span></div>
      <div><div class="px-label mb8">浮动 px-float</div><span class="anim-float" style="display:inline-block;">${icon('chef', 34)}</span></div>
      <div style="width:200px;"><div class="px-label mb8">斜纹流动 px-stripes</div><div class="progress"><i style="width:64%;"></i><b>64%</b></div></div>
      <div><div class="px-label mb8">弹跳 px-pop（点击）</div><button class="btn btn-sm" data-action="pop-demo">点我试试</button></div>
      <div><div class="px-label mb8">加载 px-jump</div><div class="px-loader"><i></i><i></i><i></i><i></i></div></div>
      <div class="tiny" style="width:100%;">所有动效均使用 steps() 阶梯缓动，模拟逐帧像素动画；系统开启「减弱动态效果」时全部自动关闭。</div>
    </div>`;
}

/* ---------- 启动 ---------- */
(function boot() {
  const nav = document.getElementById('navList');
  nav.innerHTML = GROUPS.map(g => `
    <div class="nav-group"><span class="px-label">${g.label}</span>
      ${g.items.map(([key, name, state]) => `
        <button class="nav-item" data-screen="${key}"><span class="dot"></span>${name}<span class="state-tag">${state}</span></button>`).join('')}
    </div>`).join('');
  history = ['welcome'];
  render('welcome');
})();
