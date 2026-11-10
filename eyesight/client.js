/**
 * dsh-eyesight（一眼看清）—— 浏览器半端：一枚「眼睛」按钮。
 *
 * 睁开 = 看清档（默认）：sight_see 正常工作，按块 1:1 看清。
 * 闭上 = 回到「整屏一张糊图」的老办法：sight_see 一律拒绝，不花一个 token。
 *
 * 只做开关，不碰对话、不往上下文塞东西。
 * 样式照 dsh-look 的两个小挂件来：圆角、半透明白、柔和阴影。
 */
window.__ModuleLoader__.load({
  id: 'dsh-eyesight',
  factory: () => {
    const API_STATE = '/dsh-eyesight/state'
    const API_TOGGLE = '/dsh-eyesight/toggle'
    const POS_KEY = 'ym-eyesight-pos-v1'

    const CSS = `
    .ym-eye-btn {
      position: fixed; right: 22px; bottom: 172px; z-index: 9998;
      width: 42px; height: 42px; padding: 0; border-radius: 50%;
      display: inline-flex; align-items: center; justify-content: center;
      color: #2b3440; background: rgba(255,255,255,.93);
      border: 1px solid rgba(30,40,55,.10);
      box-shadow: 0 8px 22px rgba(20,30,45,.16), 0 1px 0 rgba(255,255,255,.7) inset;
      backdrop-filter: blur(10px);
      cursor: grab; user-select: none; touch-action: none;
      transition: background .15s ease, color .15s ease, box-shadow .15s ease, opacity .15s ease;
    }
    .ym-eye-btn:hover { box-shadow: 0 10px 26px rgba(20,30,45,.20), 0 1px 0 rgba(255,255,255,.7) inset; }
    .ym-eye-btn:active { transform: scale(.96); }
    .ym-eye-btn.dragging { cursor: grabbing; transition: none; }
    .ym-eye-btn.on {
      color: #0d5b3f; background: rgba(226,248,236,.96);
      border-color: rgba(22,120,80,.24);
      box-shadow: 0 8px 22px rgba(16,90,60,.18), 0 1px 0 rgba(255,255,255,.7) inset;
    }
    .ym-eye-btn.off { color: #8a94a2; background: rgba(245,246,248,.94); }
    .ym-eye-btn.busy { opacity: .55; pointer-events: none; }
    .ym-eye-btn svg { width: 22px; height: 22px; display: block; }
    `

    const EYE_OPEN =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round">' +
      '<path d="M1.8 12S5.4 5.4 12 5.4 22.2 12 22.2 12 18.6 18.6 12 18.6 1.8 12 1.8 12Z"/>' +
      '<circle cx="12" cy="12" r="3.1" fill="currentColor" stroke="none"/></svg>'

    const EYE_SHUT =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round">' +
      '<path d="M2.4 10.2c1.4 3.1 5.1 5.6 9.6 5.6s8.2-2.5 9.6-5.6"/>' +
      '<path d="M4.2 14.6 3 16.6"/><path d="M9 16.6l-.5 2.2"/><path d="M15 16.6l.5 2.2"/><path d="M19.8 14.6 21 16.6"/></svg>'

    let on = false
    let busy = false
    let btn = null
    let styleEl = null

    function paint() {
      if (!btn) return
      btn.classList.toggle('on', on)
      btn.classList.toggle('off', !on)
      btn.innerHTML = on ? EYE_OPEN : EYE_SHUT
      btn.title = on
        ? '一眼看清：睁开（按块看清，贵但准）——点一下关掉'
        : '一眼看清：关着（默认，省 token）——点一下睁开'
      btn.setAttribute('aria-pressed', on ? 'true' : 'false')
    }

    async function refresh() {
      try {
        const r = await fetch(API_STATE, { cache: 'no-store' })
        const j = await r.json()
        if (typeof j.on === 'boolean' && j.on !== on) {
          on = j.on
          paint()
        }
      } catch {
        /* 宿主还没起好，下次再来 */
      }
    }

    async function toggle() {
      if (busy) return
      busy = true
      btn.classList.add('busy')
      try {
        const r = await fetch(API_TOGGLE, { method: 'POST' })
        const j = await r.json()
        if (typeof j.on === 'boolean') {
          on = j.on
          paint()
        }
      } catch {
        /* 失败就保持原样，不弹东西 */
      } finally {
        busy = false
        btn.classList.remove('busy')
      }
    }

    function restorePos() {
      let pos = null
      try {
        pos = JSON.parse(localStorage.getItem(POS_KEY) || 'null')
      } catch {
        pos = null
      }
      if (!pos || typeof pos.left !== 'number') return
      btn.style.left = pos.left + 'px'
      btn.style.top = pos.top + 'px'
      btn.style.right = 'auto'
      btn.style.bottom = 'auto'
    }

    function makeDraggable() {
      let sx = 0
      let sy = 0
      let ox = 0
      let oy = 0
      let moved = false
      btn.addEventListener('pointerdown', (e) => {
        if (e.button !== 0) return
        moved = false
        const r = btn.getBoundingClientRect()
        sx = e.clientX
        sy = e.clientY
        ox = r.left
        oy = r.top
        btn.classList.add('dragging')
        btn.setPointerCapture(e.pointerId)
      })
      btn.addEventListener('pointermove', (e) => {
        if (!btn.hasPointerCapture(e.pointerId)) return
        const dx = e.clientX - sx
        const dy = e.clientY - sy
        if (!moved && Math.abs(dx) + Math.abs(dy) < 4) return
        moved = true
        const left = Math.max(4, Math.min(window.innerWidth - 46, ox + dx))
        const top = Math.max(4, Math.min(window.innerHeight - 46, oy + dy))
        btn.style.left = left + 'px'
        btn.style.top = top + 'px'
        btn.style.right = 'auto'
        btn.style.bottom = 'auto'
      })
      btn.addEventListener('pointerup', (e) => {
        btn.classList.remove('dragging')
        try {
          btn.releasePointerCapture(e.pointerId)
        } catch {
          /* 已经释放了 */
        }
        if (moved) {
          const r = btn.getBoundingClientRect()
          try {
            localStorage.setItem(POS_KEY, JSON.stringify({ left: Math.round(r.left), top: Math.round(r.top) }))
          } catch {
            /* 存不上就下次回默认位 */
          }
        }
      })
      // 拖过就别当点击
      btn.addEventListener('click', (e) => {
        if (moved) {
          e.preventDefault()
          e.stopPropagation()
          return
        }
        toggle()
      })
    }

    return {
      inject: [],
      apply(ctx) {
        if (document.querySelector('.ym-eye-btn')) return

        styleEl = document.createElement('style')
        styleEl.setAttribute('data-plugin-css', 'dsh-eyesight')
        styleEl.textContent = CSS
        document.head.appendChild(styleEl)

        btn = document.createElement('button')
        btn.className = 'ym-eye-btn off'
        btn.innerHTML = EYE_SHUT
        btn.title = '一眼看清：关着（默认）——点一下睁开，按块看清'
        document.body.appendChild(btn)
        paint()
        try {
          restorePos()
        } catch {
          /* 布局没好就算了，用默认位 */
        }
        makeDraggable()

        refresh()
        const t = setInterval(refresh, 8000)

        ctx.effect(() => () => {
          clearInterval(t)
          if (styleEl) styleEl.remove()
          if (btn) btn.remove()
        }, 'dsh-eyesight: 眼睛开关')
      },
    }
  },
})
