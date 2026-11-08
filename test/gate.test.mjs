import assert from 'node:assert/strict'
import test from 'node:test'

import { gate, stateFromPick } from '../index.js'

const worn = { on: true, hwnd: 4242, title: '微信' }

test('没戴：一律拒绝', () => {
  const g = gate({ on: false }, {})
  assert.equal(g.ok, false)
  assert.match(g.error, /眼镜没戴/)
})

test('没戴：连传了 window 也拒绝（摘掉=放任，不偷偷读）', () => {
  const g = gate({ on: false }, { window: '1234' })
  assert.equal(g.ok, false)
})

test('戴着 + 显式 window：照用，via=explicit', () => {
  const g = gate(worn, { window: '99', crop: '0,0,10,10' })
  assert.equal(g.ok, true)
  assert.equal(g.via, 'explicit')
  assert.equal(g.args.window, '99')
  assert.equal(g.args.crop, '0,0,10,10')
})

test('戴着 + 不传 window：落到戴着的那个，绝不整屏', () => {
  const g = gate(worn, {})
  assert.equal(g.ok, true)
  assert.equal(g.via, 'glasses')
  assert.equal(g.args.window, '4242')
})

test('戴着 + 存过 crop：不传 crop 时用它', () => {
  const g = gate({ ...worn, crop: [10, 20, 320, 180] }, {})
  assert.equal(g.args.crop, '10,20,320,180')
})

test('戴着 + 已经传了 crop：不覆盖人的意思', () => {
  const g = gate({ ...worn, crop: [10, 20, 320, 180] }, { crop: '0,0,5,5' })
  assert.equal(g.args.crop, '0,0,5,5')
})

test('戴着但没记住窗口：拒绝，别回退整屏', () => {
  const g = gate({ on: true }, {})
  assert.equal(g.ok, false)
  assert.match(g.error, /没记住窗口/)
})

test('不改调用方传进来的 args', () => {
  const args = {}
  gate(worn, args)
  assert.deepEqual(args, {})
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
