// Run after scripts/build_web.sh, with Playwright available on NODE_PATH.
// All accounts, credentials, and server records here belong to a local fixture.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { webkit, chromium, devices } = require('playwright');

const webRoot = path.resolve(__dirname, '../build/web');
const output = path.resolve(__dirname, '../build/web-checks');
fs.mkdirSync(output, { recursive: true });
const userIds = { user1: '00000000-0000-4000-8000-000000000001', user2: '00000000-0000-4000-8000-000000000002' };
const records = new Map();
const calls = [];
let cursor = 0;
let holdPull = false;
let releasePull;
let pullGate;
let heldPulls = 0;
const server = http.createServer(async (request, response) => {
  const url = new URL(request.url, 'http://localhost');
  const json = value => { response.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); response.end(JSON.stringify(value)); };
  if (url.pathname.startsWith('/auth/') || url.pathname.startsWith('/sync/')) {
    calls.push(url.pathname);
    let body = '';
    for await (const chunk of request) body += chunk;
    const data = body ? JSON.parse(body) : {};
    const username = request.headers.authorization?.endsWith('user2') ? 'user2' : 'user1';
    if (url.pathname === '/auth/login') {
      assert.equal(data.platform, 'web');
      return json({ access_token: `fixture-access-${data.username}`, refresh_token: `fixture-refresh-${data.username}`, token_type: 'bearer', user_id: userIds[data.username], device_id: data.device_id });
    }
    if (url.pathname === '/sync/bootstrap') return json({ cursor: String(cursor), tasks: [...records.values()].filter(record => record.owner_user_id === userIds[username] || record.visibility === 'shared') });
    if (url.pathname === '/sync/tasks' && request.method === 'POST') {
      const accepted = data.changes.map(change => {
        const record = { ...change.record, version: (records.get(change.record.id)?.version ?? 0) + 1 };
        records.set(record.id, record);
        cursor++;
        return record;
      });
      return json({ cursor: String(cursor), accepted, rejected: [], purged_ids: [] });
    }
    if (holdPull) {
      heldPulls++;
      await pullGate;
    }
    return json({ cursor: String(cursor), changes: [], has_more: false });
  }
  if (!url.pathname.startsWith('/app/')) { response.writeHead(404); return response.end(); }
  const relative = decodeURIComponent(url.pathname.slice('/app/'.length)) || 'index.html';
  const filename = path.resolve(webRoot, relative);
  if (!filename.startsWith(webRoot + path.sep) || !fs.existsSync(filename) || !fs.statSync(filename).isFile()) { response.writeHead(404); return response.end(); }
  const mime = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.ttf': 'font/ttf', '.png': 'image/png' }[path.extname(filename)] ?? 'application/octet-stream';
  response.writeHead(200, { 'Content-Type': mime, 'Cache-Control': 'no-cache' });
  fs.createReadStream(filename).pipe(response);
});

async function enableSemantics(page) {
  await page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 60000 });
  await page.locator('flt-semantics-placeholder').evaluate(element => element.click());
}

async function addTask(page, title) {
  await page.getByRole('button', { name: /^할\s+일 추가$/ }).tap();
  // The editor route ignores pointer events during its entrance animation.
  await page.waitForTimeout(600);
  await page.getByRole('textbox', { name: '제목', exact: true }).tap();
  await page.waitForTimeout(200);
  await page.getByRole('textbox', { name: '제목', exact: true }).fill(title);
  await page.getByRole('button', { name: '할 일 저장', exact: true }).tap();
  await page.getByRole('checkbox', { name: title, exact: true }).waitFor();
}

(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${server.address().port}/app/`;
  const cases = [
    ['iphone', webkit, devices['iPhone 13']],
    ['ipad', webkit, devices['iPad Pro 11']],
    ['chromium', chromium, { viewport: { width: 390, height: 844 }, hasTouch: true }],
  ];
  for (const [name, engine, device] of cases) {
    const browser = await engine.launch({ headless: true });
    const { defaultBrowserType, ...options } = device;
    const context = await browser.newContext(options);
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (message.type() === 'error') console.log(name, 'console:', message.text()); });
    try {
      await page.goto(url);
      await enableSemantics(page);
      await page.getByRole('button', { name: 'User 1', exact: true }).tap();
      await page.waitForTimeout(400);
      await page.getByLabel('비밀번호', { exact: true }).tap();
      await page.waitForTimeout(200);
      await page.keyboard.type('fixture-password', { delay: 15 });
      await page.getByRole('button', { name: '로그인', exact: true }).tap();
      await page.getByRole('button', { name: /^할\s+일 추가$/ }).waitFor();
      console.log(name, 'login passed');
      const title = `${name} 온라인 할 일`;
      await addTask(page, title);
      console.log(name, 'task save passed');
      await page.waitForFunction(() => navigator.serviceWorker.controller !== null);
      await page.evaluate(() => navigator.serviceWorker.ready);
      const deadline = Date.now() + 15000;
      while (![...records.values()].some(record => record.title === title)) {
        assert.ok(Date.now() < deadline, 'Online task did not upload');
        await new Promise(resolve => setTimeout(resolve, 100));
      }
      await page.screenshot({ path: path.join(output, `${name}-online.png`) });
      await context.setOffline(true);
      const offlineTitle = `${name} 오프라인 할 일`;
      await addTask(page, offlineTitle);
      await page.reload({ waitUntil: 'domcontentloaded' });
      await enableSemantics(page);
      await page.getByRole('checkbox', { name: offlineTitle, exact: true }).waitFor();
      console.log(name, 'offline restart passed');
      await page.screenshot({ path: path.join(output, `${name}-offline.png`) });
      await context.setOffline(false);
      await page.evaluate(() => window.dispatchEvent(new Event('online')));
      await page.reload();
      await enableSemantics(page);
      const retryDeadline = Date.now() + 15000;
      while (![...records.values()].some(record => record.title === offlineTitle)) {
        assert.ok(Date.now() < retryDeadline, 'Offline task did not upload after reopening online');
        await new Promise(resolve => setTimeout(resolve, 100));
      }
      await page.getByRole('checkbox', { name: title, exact: true }).tap();
      await page.waitForFunction(title => [...document.querySelectorAll('[role="checkbox"]')].some(element => element.getAttribute('aria-label') === title && element.getAttribute('aria-checked') === 'true'), title);
      const completionDeadline = Date.now() + 15000;
      while (![...records.values()].some(record => record.title === title && record.is_completed)) {
        assert.ok(Date.now() < completionDeadline, 'Checkbox completion did not upload');
        await new Promise(resolve => setTimeout(resolve, 100));
      }
      assert.deepEqual(errors, [], 'Uncaught browser errors');
      const databases = await page.evaluate(() => indexedDB.databases());
      assert.ok(databases.some(database => database.name === 'personaltodo'));
      const cachePaths = await page.evaluate(async () => {
        const all = [];
        for (const name of await caches.keys()) {
          if (!name.startsWith('personaltodo-')) continue;
          for (const request of await (await caches.open(name)).keys()) all.push(new URL(request.url).pathname);
        }
        return all;
      });
      assert.ok(cachePaths.length > 10);
      assert.ok(cachePaths.every(path => path.startsWith('/app/')), 'API data was cached');

      if (name === 'chromium') {
        holdPull = true;
        pullGate = new Promise(resolve => { releasePull = resolve; });
        await page.reload();
        await enableSemantics(page);
        await page.waitForFunction(async () => (await navigator.locks.query()).held.some(lock => lock.name.startsWith('personaltodo-sync:')));
        const pullDeadline = Date.now() + 10000;
        while (heldPulls === 0) {
          assert.ok(Date.now() < pullDeadline, 'First tab did not reach the held request');
          await new Promise(resolve => setTimeout(resolve, 50));
        }
        const before = calls.filter(call => call.startsWith('/sync/')).length;
        const second = await context.newPage();
        await second.goto(url);
        await enableSemantics(second);
        await second.getByRole('checkbox', { name: offlineTitle, exact: true }).waitFor();
        await new Promise(resolve => setTimeout(resolve, 1500));
        assert.equal(calls.filter(call => call.startsWith('/sync/')).length, before, 'Second tab synced while the first held the lock');
        releasePull();
        holdPull = false;
        await second.close();
      }
      console.log(`${name}: login, local save, online upload, offline restart, queued upload, checkbox completion, and shell cache passed`);
    } catch (error) {
      await page.screenshot({ path: path.join(output, `${name}-failure.png`) }).catch(() => {});
      fs.writeFileSync(path.join(output, `${name}-failure.html`), await page.content());
      throw error;
    } finally {
      releasePull?.();
      holdPull = false;
      await context.close();
      await browser.close();
    }
  }
  console.log('Cross-tab sync lock passed. No production accounts or API data were used.');
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => server.close());
