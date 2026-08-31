# Tags and the three ways to tap

## What to buy

Short version: **search "NTAG215 stickers" and buy those.** Roughly $0.30 each
in packs of 10–50. 504 bytes of user memory, and the chip iOS Shortcuts is
most reliable with. NTAG213 (144 bytes) and NTAG216 (888 bytes) are fine too —
the Shortcuts route only reads the tag's UID, so capacity barely matters.

"Amiibo blank" stickers are NTAG215 sold under a different name and are often
the cheapest listing on the page. They work perfectly.

### Two listings that will not work

**125 kHz tags.** Amazon sells a lot of "RFID key fobs" and "proximity cards"
at 125 kHz — the old building-access frequency. **No iPhone can read these at
all**, and no app or setting changes that. iPhones only speak 13.56 MHz. If a
listing says 125 kHz, EM4100, EM4305 or T5577, it is the wrong radio.

**MIFARE Classic (1K / 4K).** These *are* 13.56 MHz, which is what makes them
such an effective trap — they look right. But iPhone does not support MIFARE
Classic; Apple's own developer forums confirm it, and Core NFC simply won't
return the tag. They're cheap and they're everywhere. Skip them.

### Reading the listing

| Look for | Avoid |
|---|---|
| NTAG213 / NTAG215 / NTAG216 | MIFARE Classic 1K / 4K |
| NXP NTAG21x | 125 kHz, EM4100, EM4305, T5577 |
| 13.56 MHz | UHF / 860–960 MHz |
| "NFC Forum Type 2", NDEF-formatted | "RFID key fob" with no chip named |
| "works with iPhone Shortcuts" | MIFARE Ultralight C (needs auth) |

A listing that names no chip at all is usually MIFARE Classic. If the seller
won't say, pick a different seller.

### Two physical gotchas

- **Metal kills NFC.** Don't stick a plain tag to a laptop, a fridge door, a
  radiator or a tin. Buy "on-metal" or "anti-metal" tags — they have a ferrite
  layer — or mount to wood, plastic, card or glass.
- **The UID is factory-burned and read-only.** Tim pairs against the UID rather
  than anything written to the tag, so a paired tag can't be spoofed by writing
  the same text onto a second sticker. It also means a pre-locked or
  "read-only" tag still works for pairing and for Shortcuts.

Good places to put one: the back of a coaster on the kitchen table, inside a
drawer in another room, the underside of a bedside table, the inside of the
front door. The whole mechanism is that walking to it costs you something.

Want something more like the real puck? Embed a tag in a 3D-printed disc with a
few grams of ballast and a magnet. Function is identical; it just feels nicer.

## The three tap paths

### 1. In-app scan — works immediately

Open Tim, press the button, tap the tag. Zero setup. Good for pairing and as a
fallback. Not how you'll actually use it, because opening your phone is the
thing you're trying to avoid.

### 2. Shortcuts automation — the one to use

Works with the app closed and with a completely blank tag. No website, no
associated domain, nothing written to the tag.

1. Shortcuts → **Automation** → **+** → **NFC**
2. **Scan** → hold your iPhone to the tag → name it "Tim tag"
3. **Next** → add action → search **Tim** → choose **Tim my phone**
4. Optionally set a Mode on the action
5. Turn **Ask Before Running** *off*
6. Done

Now a tap runs `ToggleTimIntent` in the background: apps vanish, or come back,
with no UI. Requires iPhone XS or later and iOS 13.1+ for the NFC trigger; iOS
15+ to skip the confirmation.

Add a second automation on a second tag with the **Start Timming** action if you
want a tag that only ever Tims — a bedside tag that can't accidentally release.

### 3. Background tag reading — what a shipping app does

iOS reads NDEF tags with no app open and shows a banner; tapping it opens your
app. To make that *your* app you need:

- a domain you control, e.g. `tim.example.com`
- an `apple-app-site-association` file served from
  `https://tim.example.com/.well-known/apple-app-site-association`:

  ```json
  {
    "applinks": {
      "details": [
        { "appIDs": ["TEAMID.app.tim.Tim"], "components": [{ "/": "/tap" }] }
      ]
    }
  }
  ```

- `applinks:tim.example.com` in `Tim/App/Tim.entitlements` (already there —
  change the domain)
- the URL `https://tim.example.com/tap` written to the tag, via **Settings →
  Pair a Tim tag** in the app or any NFC writer app

`TimModel.handleIncoming(url:)` handles the path: `/tap` toggles, `/tim` and
`/untim` are one-directional.

Custom URL schemes (`tim://tap`) do **not** work for background reading — iOS
only routes `https` universal links that way. The scheme in `Info.plist` is
there for Shortcuts' "Open URL" action, not for tags.

## Pairing

Until you pair a tag, any tag works — otherwise a fresh install would be
unusable. Once you pair one in Settings, only your paired tags toggle. You can
pair several.

Note that paths 2 and 3 don't carry a UID into the app: Shortcuts already
verified the tag before running, and a universal link only proves the tag holds
your URL. Pairing therefore guards path 1. That's the correct division — the OS
does the verifying on the paths where it can.
