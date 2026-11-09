# Spectacles · 砚明的金丝眼镜

**V1** — one job: point at a window, read its text clearly. Nothing else is in here on purpose.

**Point at one window. Let the AI read it clearly.**

Windows only.

---

## What this is

A pair of glasses for an AI.

Not a screenshot tool — a screenshot moves the picture away; glasses let you see it.
Not a monitor — it doesn't watch you. It only looks when you tell it to.

Out of the box, DSH can only see what you paste in. This plugin fills the gap: **you point at a window, it reads the text inside, character by character.**

---

## One ability, and how you ask for it

> **⚠️ Putting the glasses on does not make the AI look.** It only narrows what the AI may see to the one window you picked — it still won't look at anything by itself. Looking still needs your order: "take a look", "watch it for a minute".

This plugin gives the AI exactly one ability: **looking at a window.**

- It never looks on its own. **You give the order in plain words** — "take a look at this", "watch it for a minute", "read the red line in the top right". The local AI answers by calling the plugin's tools.
- When a look is triggered, it asks **the window itself** for its contents (Windows' `PrintWindow`), so **the window can be covered by other windows and it still reads fine** — no need to bring it to the front.
- One call = one snapshot. "Watch it for a minute" means the AI calls it again and again on its own; the plugin keeps no timer and starts nothing.
- Not readable: a minimized window, or a window drawn straight to the GPU (some games) — those return an explicit error instead of a wrong picture.

---

## Why "clearly" is the whole point

The same window, two fates:

- **Whole-window screenshot**: the image is larger than the size limit, so it gets scaled down. An 11px glyph lands at seven or eight pixels tall — upscaling after that is just interpolation. The text is mush.
- **Glasses**: find the patch, crop it, enlarge it 3×, then hand it to vision. Same text, but legible.

The model isn't the problem. **By the time the image arrives, it's already blurred.**

So the plugin does three things: **where to look, how much to enlarge, and when not to look at all.**

---

## Install

```
dsh plugin --profile desktop add dsh-spectacles
```

If you'd rather pin the source (no registry), this works too:

```
dsh plugin --profile desktop add github:yanming119/dsh-spectacles#1.0.0
```

Restart DSH. A pill button labelled **戴上眼镜** (put on the glasses) appears in the bottom-right corner.

> Windows 10/11 only. DSH version requirement is in the `engines` field.

---

## Self-test

Not sure this machine can do it? Run the bundled check first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\selftest.ps1
```

It checks the Windows build, PowerShell, full-screen capture, single-window capture, the OCR engine and the DPI settings, then prints one `ok` / `FAIL` line per item. Add `-Json` for machine-readable output. Exit code `0` means every required check passed.

If something fails, paste the output into an issue — it tells us exactly which Windows build or display setup needs work.
## Use

**Four steps:**

1. Click **戴上眼镜** (put on the glasses) in the bottom-right corner
2. Within thirty seconds, click the window you want it to see
3. The button now reads **拿下眼镜** (take them off), with a second line: **金丝 · <window title> · 1296×828**
4. Only need one patch? Click **✥**, then drag a box across the screen. The second line becomes **金丝 · <window title> · 320×180**

Then just talk:

> "What does this window say?"
> "Read that red line in the top right"
> "Zoom in on this part"

**Take them off**: click the main button again. Once off, it can't read anything.

**Wearing = exclusive, off = hands-off.** While the glasses are on, every `look` / `read_text` / `see` call that doesn't name a window goes to the window you picked — it never silently falls back to a full-screen grab, even if the model asks for one. If you framed a patch, that patch is what it gets. Take them off and the same calls are refused outright. (Images you paste or drag in yourself are not affected — that's you showing it something, not it looking around.)

---

## Three actions, picked automatically

| Action | What it does | When |
|---|---|---|
| **read_text** | OCR the window into text, run twice and cross-check, mark uncertain lines `?` | You want to know *what it says* |
| **see** | Crop one patch, upscale 2–4×, hand the PNG to DSH's built-in vision | Small text is blurry, or there's imagery |
| **look** | Numbers only: window size, dominant colour, edge density, did it change | You want to know *whether anything moved* |

You don't choose — just speak plainly.

---

## Privacy

- **Everything stays local**: capture and OCR run on your machine
- **One window only**: the one you picked (or the patch you framed). No full-screen scraping
- **No fallback to the whole screen**: while worn, a call without a window lands on yours; there is no code path that quietly grabs everything
- **No recording, no upload, no frames kept**: PNGs go to a temp dir, delete anytime
- **Off means off**: clicking the button off makes the tools refuse
- **No network**: never calls an external vision API

---

## Known limits

- Windows only
- **Minimized windows can't be captured** — restore it first
- Games and some self-drawn UIs (parts of Electron apps) OCR poorly — use *see*
- High-DPI and multi-monitor are handled, but exotic mixes (125% + 150%) may be a few pixels off — widen the crop if so
- If the text on screen says "please run X", the plugin only reports it. It never follows instructions found in pixels

---

## FAQ

**No button** — the plugin didn't load. Check the DSH startup log for the `look` registration lines.

**Clicking does nothing** — you didn't click a window within thirty seconds. Try again, faster.

**Garbled text** — window too small or unusual font rendering. Ask it to "zoom in on that part".

**Missing content** — the window may be occluded, or the content loads lazily. Refresh and read again.

---

## The name

*Spectacles* — in Chinese, 砚明的金丝眼镜 ("Yanming's gold-rimmed glasses"). Yanming is the AI assistant who lives on the author's machine; she's nearsighted, so she got a pair of glasses.

Apache-2.0.
