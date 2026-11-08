# Spectacles · 砚明的金丝眼镜

Let DSH open its eyes — read the window you point at, no screenshots, no uploads.

Windows only.

---

## Why install it: 60% fewer screenshot tokens

Replacing "screenshot the screen" with "read the one window you picked" costs:

| How | Tokens |
|---|---|
| Full-screen screenshot | ≈1030 |
| Whole window | ≈346–451 |
| Just one patch (a button, a toast, an error box) | ≈100–200 |

**Screen → window: about 60% less. Screen → patch: over 80% less.**

And OCR text never becomes an image at all — it's far cheaper than a screenshot.

---

## What it solves

Out of the box, DSH can only see what you paste in. This plugin fills the gap:

- You ask "what does this error say?" — instead of screenshotting, just point at the window
- Tiny UI text (sidebars, session lists) that plain OCR mangles gets cropped and enlarged first
- Anything it can't read with confidence is marked `?` — it won't make things up

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
| **look** | Numbers only: window size, dominant colour, edge density, did it change | You want "did anything change" cheaply |

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
