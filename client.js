/**
 * dsh-spectacles（砚明的金丝眼镜）—— 浏览器半端：一枚「眼镜」按钮。
 *
 * 没戴 = 裸眼：看不清、容易读错。
 * 点一下 → 弹提示「请点击要指定的窗口」→ 人点窗口 → 变绿「金丝：微信」
 * 再点一下 → 摘下 → 提示「眼镜摘下来了」
 * 拖动 → 挪到任意位置，松手记住（localStorage），下次还在那儿。
 *
 * 样式照桌宠的气泡来：圆角、半透明白、柔和阴影、小尾巴。
 * 不依赖 slots，直接挂 DOM，免得 slot 名字变了就整块消失。
 */
window.__ModuleLoader__.load({
  id: 'dsh-look',
  factory: () => {
    const API_STATE = '/dsh-look/state'
    const API_PICK = '/dsh-look/pick'
    const POS_KEY = 'ym-look-pos-v1'

    const CSS = `
    .ym-look-btn {
      position: fixed; right: 22px; bottom: 118px; z-index: 9998;
      display: inline-flex; align-items: center; gap: 8px;
      max-width: 300px;
      padding: 10px 18px 10px 15px; border-radius: 999px;
      font: 600 15px/1 -apple-system, "Segoe UI", "Microsoft YaHei", sans-serif;
      letter-spacing: .2px;
      color: #2b3440; background: rgba(255,255,255,.93);
      border: 1px solid rgba(30,40,55,.10);
      box-shadow: 0 8px 22px rgba(20,30,45,.16), 0 1px 0 rgba(255,255,255,.7) inset;
      backdrop-filter: blur(10px);
      cursor: grab; user-select: none; touch-action: none;
      transition: background .15s ease, color .15s ease, box-shadow .15s ease;
    }
    .ym-look-btn:hover { box-shadow: 0 10px 26px rgba(20,30,45,.20), 0 1px 0 rgba(255,255,255,.7) inset; }
    .ym-look-btn.dragging { cursor: grabbing; transition: none; }
    .ym-look-btn.on {
      color: #0d5b3f; background: rgba(226,248,236,.96);
      border-color: rgba(22,120,80,.22);
      box-shadow: 0 8px 22px rgba(16,90,60,.18), 0 1px 0 rgba(255,255,255,.7) inset;
    }
    .ym-look-dot {
      width: 9px; height: 9px; border-radius: 50%;
      background: #b3bcc8; box-shadow: 0 0 0 3px rgba(179,188,200,.18);
      flex: none;
    }
    .ym-look-label {
      max-width: 240px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
      display: block;
    }
    .ym-look-btn.on .ym-look-dot { background: #17a56a; box-shadow: 0 0 0 3px rgba(23,165,106,.18); }

    .ym-look-toast {
      position: fixed; left: 50%; bottom: 152px; transform: translateX(-50%) translateY(6px);
      z-index: 9999; max-width: 62vw;
      padding: 10px 18px 11px; border-radius: 16px;
      font: 500 13.5px/1.35 -apple-system, "Segoe UI", "Microsoft YaHei", sans-serif;
      color: #26303b; background: rgba(255,255,255,.96);
      border: 1px solid rgba(30,40,55,.10);
      box-shadow: 0 10px 28px rgba(18,28,42,.18);
      opacity: 0; pointer-events: none;
      transition: opacity .18s ease, transform .18s ease;
    }
    .ym-look-toast::after {
      content: ""; position: absolute; left: 50%; bottom: -6px; width: 12px; height: 12px;
      margin-left: -6px; background: rgba(255,255,255,.96);
      border-right: 1px solid rgba(30,40,55,.10); border-bottom: 1px solid rgba(30,40,55,.10);
      transform: rotate(45deg); border-radius: 0 0 3px 0;
    }
    .ym-look-toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }
    `

    let styleEl = null
    let btn = null
    let toastEl = null
    let toastTimer = null
    let state = { on: false, title: null }
    let busy = false
    let suppressClick = false

    function toast(text, ms) {
      if (!toastEl) return
      toastEl.textContent = text
      toastEl.classList.add('show')
      if (toastTimer) clearTimeout(toastTimer)
      toastTimer = setTimeout(() => toastEl.classList.remove('show'), ms || 2600)
    }

    function shortTitle(t) {
      const s = String(t || '').replace(/\s+/g, ' ').trim()
      if (!s) return '已指定'
      return s.length > 16 ? s.slice(0, 16) + '…' : s
    }

    function paint() {
      if (!btn) return
      btn.classList.toggle('on', !!state.on)
      btn.querySelector('.ym-look-label').textContent = state.on ? '金丝：' + shortTitle(state.title) : '戴上眼镜'
      btn.title = state.on
        ? '正戴着：' + (state.title || '已指定') + '\n点一下摘下 · 拖到任意位置'
        : '点一下，再点你要 AI 看的窗口\n拖到任意位置'
    }

    // ---- 位置：拖到哪记哪 ----
    function clampPos(x, y) {
      const r = btn.getBoundingClientRect()
      const maxX = Math.max(0, window.innerWidth - r.width - 2)
      const maxY = Math.max(0, window.innerHeight - r.height - 2)
      return { x: Math.min(Math.max(0, x), maxX), y: Math.min(Math.max(0, y), maxY) }
    }

    function place(x, y, save) {
      if (!btn) return
      const p = clampPos(x, y)
      btn.style.left = p.x + 'px'
      btn.style.top = p.y + 'px'
      btn.style.right = 'auto'
      btn.style.bottom = 'auto'
      if (save) {
        try {
          localStorage.setItem(POS_KEY, JSON.stringify(p))
        } catch {
          /* 存不上就算了，下次回默认位 */
        }
      }
    }

    function restorePos() {
      let p = null
      try {
        p = JSON.parse(localStorage.getItem(POS_KEY) || 'null')
      } catch {
        p = null
      }
      if (p && Number.isFinite(p.x) && Number.isFinite(p.y)) place(p.x, p.y, false)
      else place(window.innerWidth - 22 - 96, window.innerHeight - 118 - 40, false)
    }

    function makeDraggable() {
      let down = null
      btn.addEventListener('pointerdown', (e) => {
        if (e.button !== 0) return
        const r = btn.getBoundingClientRect()
        down = { px: e.clientX, py: e.clientY, x: r.left, y: r.top, moved: false, id: e.pointerId }
        btn.setPointerCapture(e.pointerId)
      })
      btn.addEventListener('pointermove', (e) => {
        if (!down || e.pointerId !== down.id) return
        const dx = e.clientX - down.px
        const dy = e.clientY - down.py
        if (!down.moved && Math.abs(dx) + Math.abs(dy) < 4) return
        down.moved = true
        btn.classList.add('dragging')
        place(down.x + dx, down.y + dy, false)
      })
      const end = (e) => {
        if (!down || e.pointerId !== down.id) return
        const moved = down.moved
        down = null
        btn.classList.remove('dragging')
        try {
          btn.releasePointerCapture(e.pointerId)
        } catch {
          /* 已释放 */
        }
        if (moved) {
          const r = btn.getBoundingClientRect()
          place(r.left, r.top, true)
          suppressClick = true
          setTimeout(() => {
            suppressClick = false
          }, 0)
        }
      }
      btn.addEventListener('pointerup', end)
      btn.addEventListener('pointercancel', end)
      window.addEventListener('resize', () => {
        const r = btn.getBoundingClientRect()
        place(r.left, r.top, false)
      })
    }

    async function refresh() {
      try {
        const r = await fetch(API_STATE, { cache: 'no-store' })
        const j = await r.json()
        state = { on: !!j.on, title: j.title || null }
        paint()
      } catch {
        /* 宿主还没起来就下次再刷 */
      }
    }

    async function toggle() {
      if (busy) return
      busy = true
      if (!state.on) toast('请点击要戴上看清的那个窗口（30 秒内）', 3200)
      try {
        const r = await fetch(API_PICK, { method: 'POST' })
        const j = await r.json()
        if (j.on) {
          state = { on: true, title: j.title || '' }
          paint()
          toast('眼镜戴上了：' + (j.title || '已指定'))
        } else {
          state = { on: false, title: null }
          paint()
          toast(j.error ? '没戴上（超时或没点窗口）' : '眼镜摘下来了')
        }
      } catch (e) {
        toast('眼镜切换失败：' + (e && e.message ? e.message : e))
      } finally {
        busy = false
      }
    }

    return {
      inject: [],
      apply(ctx) {
        if (document.querySelector('.ym-look-btn')) return
        styleEl = document.createElement('style')
        styleEl.setAttribute('data-plugin-css', 'dsh-look')
        styleEl.textContent = CSS
        document.head.appendChild(styleEl)

        btn = document.createElement('button')
        btn.className = 'ym-look-btn'
        btn.innerHTML = '<span class="ym-look-dot"></span><span class="ym-look-label">戴上眼镜</span>'
        btn.addEventListener('click', () => {
          if (suppressClick) return
          toggle()
        })
        document.body.appendChild(btn)
        try {
          restorePos()
        } catch {
          /* 布局没好就下一帧再来 */
          requestAnimationFrame(() => {
            try {
              restorePos()
            } catch {
              /* 放弃，用默认位 */
            }
          })
        }
        makeDraggable()

        toastEl = document.createElement('div')
        toastEl.className = 'ym-look-toast'
        document.body.appendChild(toastEl)

        refresh()
        const t = setInterval(refresh, 5000)

        ctx.effect(() => () => {
          clearInterval(t)
          if (styleEl) styleEl.remove()
          if (btn) btn.remove()
          if (toastEl) toastEl.remove()
        }, 'dsh-look: 读屏按钮')
      },
    }
  },
})
