// Renders the demo images in ../screenshots:
//   * tablet screens: the REAL html/ tablet UI driven by tablet-mock.js, over an in-game office backdrop
//   * a few ox_lib-style scenes from scenes.js (job offer pop-up, driving HUD)
//   * 00-overview.jpg contact sheet
// Usage (from this folder): node shoot.js   (needs `playwright` + Chromium)
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const TABLET = [
  ['01-dashboard', 'home'],
  ['02-finances', 'finance'],
  ['03-bid-board', 'board'],
  ['04-loads', 'loads'],
  ['05-assign', 'loads', async (p) => { await p.getByRole('button', { name: 'Assign' }).first().click(); }],
  ['06-staff', 'employees', async (p) => { await p.getByText('Dale Kowalski').click(); }],
  ['07-hiring', 'hire'],
  ['08-fleet', 'fleet'],
  ['09-truck-dealer', 'fleet', async (p) => { await p.getByRole('button', { name: 'Buy a truck' }).click(); }],
  ['10-office-upgrades', 'upgrades'],
  ['11-dispatch', 'dispatch'],
  ['12-my-shift', 'driver'],
  ['13-buy-property', 'listing'],
];

(async () => {
  const dir = __dirname;
  const root = path.join(dir, '..', '..');
  const out = path.join(dir, '..', 'screenshots');
  fs.mkdirSync(out, { recursive: true });
  for (const f of fs.readdirSync(out)) if (f.endsWith('.jpg') && f !== '17-job-panel.jpg') fs.unlinkSync(path.join(out, f));

  const browser = await chromium.launch();
  const mock = fs.readFileSync(path.join(dir, 'tablet-mock.js'), 'utf8');
  const bg = 'data:image/jpeg;base64,' + fs.readFileSync(path.join(dir, 'bg-office.jpg')).toString('base64');

  for (const [name, app, prep] of TABLET) {
    const page = await browser.newPage({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1.2 });
    await page.addInitScript(mock);
    await page.goto('file://' + path.join(root, 'html', 'index.html') + '?app=' + app);
    await page.addStyleTag({ content: `html,body{background:#000 url(${bg}) center/cover no-repeat !important}
      body::before{content:'';position:fixed;inset:0;background:rgba(0,0,0,.35)}
      @keyframes rise{from{}to{}}` });
    await page.evaluate(() => document.fonts.ready);
    await page.waitForSelector('#content .head, #content .hero', { timeout: 10000 });
    if (prep) { await prep(page); await page.waitForTimeout(300); }
    await page.waitForTimeout(700); // images (truck renders) + fonts
    await page.screenshot({ path: path.join(out, name + '.jpg'), type: 'jpeg', quality: 88 });
    await page.close();
    console.log('rendered', name);
  }

  const src = fs.readFileSync(path.join(dir, 'scenes.js'), 'utf8');
  const names = [...src.matchAll(/^  '([\w-]+)': \{/gm)].map((m) => m[1]);
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1.5 });
  for (const n of names) {
    await page.goto('file://' + path.join(dir, 'index.html') + '?s=' + n);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(400);
    await page.screenshot({ path: path.join(out, n + '.jpg'), type: 'jpeg', quality: 88 });
    console.log('rendered', n);
  }

  const sheet = await browser.newPage({ viewport: { width: 1600, height: 900 } });
  await sheet.goto('file://' + path.join(dir, 'sheet.html'));
  await sheet.evaluate(() => document.fonts.ready);
  await sheet.waitForFunction(() => [...document.images].every((i) => i.complete));
  await sheet.waitForTimeout(300);
  await sheet.screenshot({ path: path.join(out, '00-overview.jpg'), type: 'jpeg', quality: 88, fullPage: true });
  console.log('rendered 00-overview');
  await browser.close();
})();
