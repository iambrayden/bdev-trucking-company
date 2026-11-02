// Renders every scene in scenes.js to ../screenshots/<name>.jpg, then builds the overview sheet.
// Usage (from this folder): node shoot.js        (requires `playwright` with Chromium installed)
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

(async () => {
  const dir = __dirname;
  const out = path.join(dir, '..', 'screenshots');
  fs.mkdirSync(out, { recursive: true });
  const src = fs.readFileSync(path.join(dir, 'scenes.js'), 'utf8');
  const names = [...src.matchAll(/^  '([\w-]+)': \{/gm)].map((m) => m[1]);
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 }, deviceScaleFactor: 1.5 });
  for (const n of names) {
    await page.goto('file://' + path.join(dir, 'index.html') + '?s=' + n);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(400);
    await page.screenshot({ path: path.join(out, n + '.jpg'), type: 'jpeg', quality: 90 });
    console.log('rendered', n);
  }
  const sheet = await browser.newPage({ viewport: { width: 1600, height: 900 } });
  await sheet.goto('file://' + path.join(dir, 'sheet.html'));
  await sheet.evaluate(() => document.fonts.ready);
  await sheet.waitForFunction(() => [...document.images].every((i) => i.complete));
  await sheet.waitForTimeout(300);
  await sheet.screenshot({ path: path.join(out, '00-overview.jpg'), type: 'jpeg', quality: 90, fullPage: true });
  console.log('rendered 00-overview');
  await browser.close();
})();
