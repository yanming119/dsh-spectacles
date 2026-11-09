import assert from 'node:assert/strict'
import test from 'node:test'

import * as plugin from '../index.js'

/** 假装是宿主：只要 apply() 不抛、三样东西都注册上，就算能起来。 */
function fakeCtx() {
  const tools = []
  const routes = new Map()
  const sections = []
  const disposers = []
  const ctx = {
    effect(fn) {
      const d = fn()
      disposers.push(d)
    },
    systemPrompt: {
      section(s) {
        sections.push(s)
        return () => sections.pop()
      },
    },
    tools: {
      register(t) {
        tools.push(t)
        return () => tools.pop()
      },
    },
    webServer: {
      register(r) {
        routes.set(r.path, r.handler)
        return () => routes.delete(r.path)
      },
    },
  }
  return { ctx, tools, routes, sections, disposers }
}

function fakeRes() {
  const res = {
    headers: {},
    body: '',
    setHeader(k, v) {
      res.headers[k] = v
    },
    end(b) {
      res.body = b
    },
  }
  return res
}

test('apply() 能起来：系统提示 + 三个工具 + 四条路由', async () => {
  const { ctx, tools, routes, sections } = fakeCtx()
  await plugin.apply(ctx)
  assert.equal(sections.length, 1)
  assert.deepEqual(
    tools.map((t) => t.name).sort(),
    ['look', 'read_text', 'see'],
  )
  assert.deepEqual([...routes.keys()].sort(), ['/dsh-look/pick', '/dsh-look/ping', '/dsh-look/region', '/dsh-look/state'])
})

test('GET /dsh-look/state 回一份能用的状态', async () => {
  const { ctx, routes } = fakeCtx()
  await plugin.apply(ctx)
  const res = fakeRes()
  await routes.get('/dsh-look/state')({}, res)
  const j = JSON.parse(res.body)
  for (const k of ['on', 'title', 'hwnd', 'rect', 'crop', 'size', 'mode']) {
    assert.ok(k in j, 'state 里少了 ' + k)
  }
  assert.match(res.headers['content-type'], /json/)
})

test('每个工具的描述里都写着「只读」', async () => {
  const { ctx, tools } = fakeCtx()
  await plugin.apply(ctx)
  for (const t of tools) {
    assert.match(t.description, /只读/, t.name + ' 的描述里没有「只读」')
  }
})
