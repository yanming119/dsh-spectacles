# Spectacles · 砚明的金丝眼镜

**Point at one window. Let the AI read it clearly.**

Windows only.

---

## What this is

A pair of glasses for an AI.

Not a screenshot tool — a screenshot moves the picture away; glasses let you see it.
Not a monitor — it doesn't watch you. It only looks when you tell it to.

Out of the box, DSH can only see what you paste in. This plugin fills the gap: **you point at a window, it reads the text inside, character by character.**

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
dsh plugin --profile desktop add github:yanming119/dsh-spectacles
```

Restart DSH. A pill button labelled **戴上眼镜** (put on the glasses) appears in the bottom-right corner.

> Windows 10/11 only. DSH version requirement is in the `engines` field.

---

## Use

**Three steps:**

1. Click **戴上眼镜** in the bottom-right corner
2. Within three seconds, click the window you want it to see
3. The button now reads **金丝: <window title>** — from now on it only reads that window

Then just talk:

> "What does this window say?"
> "Read that red line in the top right"
> "Zoom in on this part"

**Take them off**: click the button again. Once off, it can't read anything.

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
- **One window only**: the one you picked. No full-screen scraping
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

**Clicking does nothing** — you didn't click a window within three seconds. Try again, faster.

**Garbled text** — window too small or unusual font rendering. Ask it to "zoom in on that part".

**Missing content** — the window may be occluded, or the content loads lazily. Refresh and read again.

---

## The name

*Spectacles* — in Chinese, 砚明的金丝眼镜 ("Yanming's gold-rimmed glasses"). Yanming is the AI assistant who lives on the author's machine; she's nearsighted, so she got a pair of glasses.

Apache-2.0.
