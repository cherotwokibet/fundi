# Design rules (owner app)

Full reasoning and before/after screens: https://claude.ai/artifact/SngcAzUst8vE8KrQKrBQrU

## Rules

- One lime button per screen: the main action. Everything else is quieter.
- The main button sits low on the screen, in one-handed thumb reach.
- Nothing is sent to a mechanic until the owner taps **Request this mechanic**.
- Calling is never blocked: every mechanic card has Call, whatever the status.
- Every wait has a way out: call the mechanic, call someone else, or cancel.
- Status is always in words, never colour alone.
- Red is only for emergency numbers and cancel. Amber is only for warnings and "Busy".
- Tap targets are at least 48 px tall. Text is at least 13 px.
- Layouts must hold at 320 px wide with text at 1.5 times size (there are tests for this).
- No ratings or stars until real reviews exist (Phase 2).
- The two home actions are tiles with an icon, a title, one line saying what happens, and an arrow.

## Screen sizes

- Under 900 px wide (phones, upright tablets): one column, capped at 560 px and centred.
- 900 px and wider (laptops, desktops): home is two columns (main action left; browse,
  how it works and safety right) and Browse shows two cards per row. Forms and the
  request screens stay 560 px wide and centred; they do not stretch.
- Bottom sheets are never wider than 560 px.
- The desktop home must fit a 1280 x 600 window without scrolling.

## Palette (`lib/ui/theme.dart`)

| Name | Colour | Used for | Contrast |
| --- | --- | --- | --- |
| forest | `#17392C` | Hero card, dark buttons, text on lime | White on it 12.7:1 |
| lime | `#D8F27E` | The one main button per screen | Forest on it 10.2:1 |
| page | `#F8F6F1` | Background | Ink on it 15.4:1 |
| ink | `#14211D` | Body text | 15.4:1 on page |
| muted | `#55625D` | Secondary lines | 5.9:1 on page |
| tint | `#E6ECE4` | Second button, quiet panels | Ink on it 13.8:1 |
| Available pill | `#135C37` on `#DCEFE2` | Status | 6.7:1 |
| Busy pill | `#7A4B00` on `#FCEBC7` | Status | 6.3:1 |
| Other pills | `#4A524F` on `#ECEDEA` | Not confirmed, offline | 6.8:1 |

The minimum for normal text is 4.5:1 (WCAG AA).

## Type

Headings: Inter Tight ExtraBold, bundled in `assets/fonts` (SIL Open Font License).
Body: the phone's own font (Roboto on Android).

## Emergency numbers

The safety sheet shows 999, 112 and Kenya Red Cross 1199. 911 is left out because
sources disagree on whether it works on every network. Check these once a year.
