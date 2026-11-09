import test from 'node:test'
import assert from 'node:assert/strict'
import { gate, ruleText, stateFromPick } from '../index.js'

test('rule: 戴着时说出窗口名和 hwnd', () => {
  const t = ruleText({ on: true, hwnd: 42, title: '微信', size: [320, 180] })
  assert.match(t, /现在戴着眼镜/)
  assert.match(t, /微信/)
  assert.match(t, /42/)
  assert.match(t, /320×180/)
  assert.match(t, /read_text/)
})

test('rule: 没戴（自用版）说明可以读整屏', () => {
  const t = ruleText({ on: false })
  assert.match(t, /没戴眼镜/)
  assert.match(t, /整屏/)
})

test('rule: 戴着和没戴给出的规则不一样', () => {
  assert.notEqual(ruleText({ on: true, hwnd: 1, title: 'a' }), ruleText({ on: false }))
})

const pub = { internal: false }
const worn = { on: true, hwnd: 1234, title: 'x', rect: [0, 0, 800, 600] }

test('没戴：一律拒绝', () => {
  const g = gate({ on: false }, {}, pub)
  assert.equal(g.ok, false)
  assert.match(g.error, /没戴/)
})

test('没戴：连传了 window 也拒绝（摘掉=放任，不偷偷读）', () => {
  const g = gate({ on: false }, { window: '1234' }, pub)
  assert.equal(g.ok, false)
})

test('戴着时指名别的窗口：拒绝（排他）', () => {
  const g = gate(worn, { window: '99', crop: '0,0,10,10' }, pub)
  assert.equal(g.ok, false)
  assert.match(g.error, /只读/)
})

test('显式 window（同一个）：via=explicit', () => {
  const g = gate(worn, { window: '1234', crop: '0,0,10,10' }, pub)
  assert.equal(g.ok, true)
  assert.equal(g.via, 'explicit')
  assert.equal(g.mode, 'window')
  assert.equal(g.args.window, '1234')
  assert.equal(g.args.crop, '0,0,10,10')
})

test('不传 window：落到戴着的那个窗口', () => {
  const g = gate(worn, {}, pub)
  assert.equal(g.ok, true)
  assert.equal(g.via, 'glasses')
  assert.equal(g.args.window, '1234')
  assert.equal(g.args.crop, undefined)
})

test('戴着且有 crop：自动带上', () => {
  const g = gate({ ...worn, crop: [10, 20, 320, 180] }, {}, pub)
  assert.equal(g.args.crop, '10,20,320,180')
})

test('已有 crop：不被 state.crop 覆盖', () => {
  const g = gate({ ...worn, crop: [10, 20, 320, 180] }, { crop: '0,0,5,5' }, pub)
  assert.equal(g.args.crop, '0,0,5,5')
})

test('戴了但没记 hwnd：拒绝并提示重选', () => {
  const g = gate({ on: true }, {}, pub)
  assert.equal(g.ok, false)
  assert.match(g.error, /重新选/)
})

test('不改调用方传进来的 args', () => {
  const args = {}
  gate(worn, args, pub)
  assert.deepEqual(args, {})
})

test('自用版：没戴也能整屏', () => {
  const g = gate({ on: false }, { crop: '0,0,10,10' }, { internal: true })
  assert.equal(g.ok, true)
  assert.equal(g.mode, 'fullscreen')
  assert.equal(g.via, 'internal')
  assert.equal(g.args.crop, '0,0,10,10')
})

test('选整个窗口：size 就是窗口宽高，没有 crop', () => {
  const s = stateFromPick({ ok: true, hwnd: 7, title: '微信', pid: 9, rect: [100, 200, 1296, 828] })
  assert.equal(s.on, true)
  assert.equal(s.hwnd, 7)
  assert.deepEqual(s.rect, [100, 200, 1296, 828])
  assert.equal(s.crop, undefined)
  assert.deepEqual(s.size, [1296, 828])
})

test('框一块：crop 和 size 跟着变', () => {
  const s = stateFromPick({ ok: true, hwnd: 7, title: '微信', rect: [100, 200, 1296, 828], crop: [10, 20, 320, 180] })
  assert.deepEqual(s.crop, [10, 20, 320, 180])
  assert.deepEqual(s.size, [320, 180])
})

test('框一块：送来的是字符串也转换成数字', () => {
  const s = stateFromPick({ ok: true, hwnd: 7, title: 'x', rect: ['1', '2', '300', '200'], crop: ['5', '6', '64', '32'] })
  assert.deepEqual(s.crop, [5, 6, 64, 32])
  assert.deepEqual(s.size, [64, 32])
})
