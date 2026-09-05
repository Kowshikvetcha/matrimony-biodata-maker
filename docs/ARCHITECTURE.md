# Architecture

## Overview

This is a client-only static web app: a single `index.html` file containing all markup, CSS, and JavaScript, with no build step, bundler, or framework. It loads three third-party libraries from CDN — `html2canvas` and `jsPDF` for turning the on-page biodata card into a downloadable image/PDF, and `@supabase/supabase-js` for optional persistence — plus two Google Fonts (Playfair Display for headings, Inter for body text). The only server-side component is a Supabase project (Postgres + Storage), defined by `supabase_setup.sql`, which the page talks to directly from the browser using a public anon key restricted by row-level security to insert-only access.

## How it fits together

```mermaid
flowchart TD
  User -->|fills form| Form[bioForm inputs]
  Form -->|input event| RenderPreview[renderPreview] --> Card[#card preview div]
  User -->|checks a "Don't show" box| HideCheckbox[isFieldHidden lookup] --> RenderPreview
  User -->|click template swatch| SetTemplate[setTemplate] --> Card
  User -->|click language dropdown| ApplyLanguage[applyLanguage] --> Card

  User -->|click PDF/Image/Instagram button| HandleDownload[handleDownload / igBtn handler]
  HandleDownload --> Validate[validate: native form.checkValidity]
  Validate -->|invalid| Status[status banner: generic message]
  Validate -->|valid| RenderCanvas[renderCardCanvas via html2canvas]
  RenderCanvas --> SaveDb[saveToDbIfNeeded — best-effort, failures only logged]
  SaveDb -->|photo file present| UploadPhoto[uploadPhoto: compress + upload to biodata-photos bucket]
  SaveDb --> UploadCard[uploadCardImage: upload rendered canvas to biodata-cards bucket]
  SaveDb --> InsertRow[(Supabase: biodata_submissions insert)]
  RenderCanvas --> Generator[generatePdf / generateImage / generateInstagramImage]
  Generator --> TriggerDownload[triggerDownload]
  TriggerDownload -->|in-app browser + Web Share supported| ShareSheet[navigator.share: OS share sheet]
  TriggerDownload -->|otherwise, or share failed/unsupported| AnchorClick[Blob + object URL, clicked via an attached anchor]
  ShareSheet --> Status
  AnchorClick --> Status

  PageLoad[page load] --> InAppCheck[isInAppBrowser: UA sniff for Instagram/FB/TikTok/etc.]
  InAppCheck -->|true, Android| AndroidBanner[sticky banner: "Open in Chrome" via an intent: URL]
  InAppCheck -->|true, other OS| OtherBanner[sticky banner: text instructions to open in Safari]
```

A single concrete flow, PDF download, traced through the real code:

1. The user fills the form; every `input` event on `#bioForm` re-runs `renderPreview()`, which reads each field, looks up its translated label/value via `label()`/`displayValue()`, skips any field whose `hide_<fieldId>` checkbox is checked (`isFieldHidden()`), and rewrites `#previewBody`'s HTML grouped into sections. A `pairMode` per group ("dynamic", "fixed", or "single" — see `renderPreview()`) controls whether two fields share a row or each gets its own; a separate "Requirements" section is appended below the grouped fields if that field has content and isn't hidden.
2. Clicking **Download as PDF** calls the `pdfBtn` click handler, which calls `handleDownload(btn, "pdf", generatePdf)`.
3. `handleDownload` first calls `validate()` (native HTML5 `checkValidity()` on required fields); if invalid it shows a generic "fill in required fields" status and stops.
4. It renders the current `#card` DOM node to a canvas once via `renderCardCanvas()` (`html2canvas(card, {scale:2, ...})`), so the same canvas can be reused for both the database save and the actual download.
5. If a Supabase client was configured, `saveToDbIfNeeded(cardCanvas)` builds a plain object from `FIELDS`, optionally uploads the chosen photo (after client-side compression via `compressImage()`) and the rendered card canvas to Supabase Storage, and inserts one row into `public.biodata_submissions` — guarded by a `savedToDb` flag so a submission is only ever saved once per page load. **Any failure here (network, schema mismatch, etc.) is only `console.error`'d — it never reaches the status banner or blocks the download**, since a database-save outcome is an internal implementation detail, not something the user needs to know about.
6. `generatePdf(canvas)` runs regardless of whether the save succeeded: it computes a scale that fits the canvas onto a single A4 page in `jsPDF`, centers it, and hands `pdf.output("blob")` to `triggerDownload()`.
7. `triggerDownload(blob, filename)` is where the actual file save happens, and it branches on whether the page is running inside a known in-app browser. If so, and the platform supports the Web Share API for this file, it calls `navigator.share({files:[file]})` — this opens the OS's native share sheet ("Save Image"/"Save to Files"), which some in-app WebViews honor even though they have no download manager of their own. Otherwise (or if sharing fails for a reason other than the user dismissing the sheet), it falls back to the same `Blob`/`URL.createObjectURL()` + a briefly-attached `<a download>` that already works in normal browsers.
8. `showStatus()` shows one generic status at the end: `"<Label> downloaded!"` on success, or `"Could not download the <label>. Please try again."` if anything in the whole try block threw — the same two messages are reused for PDF, Image, and Instagram downloads (see `I18N.*.msg.downloaded`/`downloadFailed`).

The Image and Instagram-post downloads follow the same `handleDownload` path with a different generator function (`generateImage`, or the separate `igBtn` handler calling `generateInstagramImage`, which re-renders the off-screen `#igCard` element with `renderIgCard()` before capturing it); both also funnel their canvas through `triggerDownload()`.

Separately, at page load (and again on every language switch) `updateInAppEscapeBanner()` calls `isInAppBrowser()` to sniff `navigator.userAgent` for known in-app WebViews (Instagram, Facebook, TikTok, Line, WeChat). If matched, it shows a sticky banner at the very top of the page — before the user has even tried to download anything — with different content per platform: on Android, a real "Open in Chrome" button linking to an `intent:` URL (`buildChromeIntentUrl()`), which hands navigation straight to Android's intent resolver and escapes the in-app WebView entirely, with a `browser_fallback_url` so it never dead-ends if Chrome isn't installed; everywhere else (notably iOS), just text instructions to open the page in Safari, since Apple doesn't let a webpage force that redirect itself. This banner exists because, on a real device, downloads and Web Share both turned out to still fail inside Instagram's Android in-app browser — that WebView blocks file egress outright, and no client-side technique gets around it, so escaping to a real browser is the only fix that actually works.

## Directories / files

There are no real subdirectories beyond `.git`, `.claude`, and `docs`. Everything the app needs to run is at the repo root.

| Path | Purpose |
|---|---|
| `index.html` | The entire application — see file reference below for its internal structure |
| `supabase_setup.sql` | Defines the `biodata_submissions` table, RLS policies, and the two storage buckets used by `index.html`; also contains an idempotent migration block (add new columns) and a cleanup block (drop legacy columns) for evolving an already-deployed schema |
| `logo.svg` | Two-ring monogram used as the favicon and header logo |
| `CNAME` | GitHub Pages custom domain (`matrimony-biodata-maker.com`) |
| `.claude/launch.json` | Dev-server config used by Claude Code's preview tooling (`python -m http.server 8123`) — not read by the app itself |

## File reference — inside `index.html`

Since the whole app is one file, this table breaks it down by logical section (in source order) rather than by file.

### `<style>` (lines 15–582)

| Section | Lines (approx.) | Purpose |
|---|---|---|
| `:root` variables, base/body/header, template-picker swatches, in-app escape banner | 16–344 | Color palette (maroon/gold on cream), spacing/radius/shadow tokens, the two Google Fonts, the two-column `.layout` grid, header, form panel/fieldset/input/button styling, status banner, character-count and "don't show" checkbox styling, and `#inAppEscapeBanner`'s sticky-top styling |
| Preview card + `.kv`/`.kv-item` grid | 345–449 | `#card`'s layout, including `container-type: inline-size` so the field grid can respond to the card's own rendered width (not the viewport) via `@container`, and the `.kv-wide` class that forces a field onto its own row |
| The 4 templates | 450–518 | `tpl-classic`/`tpl-modern`/`tpl-elegant`/`tpl-royal` are CSS custom-property overrides on `#card`/`#igCard` (`--c-bg`, `--c-heading`, `--c-accent`, etc.), not separate markup |
| `#igCard` | 519–581 | Fixed 1080×1350px off-screen (`left:-9999px`) card used only as an `html2canvas` capture source for the Instagram export; reuses the same CSS variables as the main card so template/color choices stay in sync |

### `<body>` (lines 584–1043)

| Section | Lines (approx.) | Purpose |
|---|---|---|
| `#inAppEscapeBanner` markup | 586–589 | Empty by default (`updateInAppEscapeBanner()` fills it in and shows it via JS); holds a text span and an "Open in Chrome" link |
| Header | 591–600 | App title (i18n-driven) and the compact English/Telugu `<select>` |
| `#bioForm` — Personal Details | 609–758 | Required core fields (name, gender, DOB, height, marital status, religion, community, diet, location) plus optional ones (mother tongue, category, complexion) |
| `#bioForm` — Astro Details | 759–789 | Gothra, maternal uncle's gotram, manglik, rashi, nakshatra — all optional |
| `#bioForm` — Education & Career | 790–852 | Qualification, college, work sector, occupation, company, annual income (see the expanded income bracket list in the `<select>`) |
| `#bioForm` — Family Details | 853–882 | Parents' names/occupations, siblings |
| `#bioForm` — Contact Information | 883–963 | Phone numbers (own/father's/mother's, each a country-code `<select>` + number `<input>` combined into one hidden field), email, address |
| `#bioForm` — Photo Upload, About Me, Requirements | 964–1000 | Photo dropzone; About Me and Partner Requirements textareas, each with a live character counter (300-char limit) and a "don't show in biodata" checkbox for Requirements |
| Template picker + `#card` preview | 1001–1033 | The 4 template swatches and the live preview card (`#photoBox`, `#nameLine`, `#previewBody`) |
| `#igCard` markup | 1034–1043 | The off-screen Instagram card's DOM, populated by `renderIgCard()` on demand |

### `<script>` (lines 1044–1878)

| Function / section | Lines (approx.) | Purpose |
|---|---|---|
| `SUPABASE_URL`/`SUPABASE_ANON_KEY` + client init | 1049–1056 | Hardcoded project config; `supabaseClient` stays `null` if the URL/key look unset, which disables persistence but not the downloads |
| `FIELDS` | 1057–1071 | Canonical list of form field IDs that map 1:1 to `biodata_submissions` columns — used when building the record to insert |
| `isFieldHidden()`, `HIDEABLE_FIELDS` injection | 1072–1097 | The generic "don't show in biodata" mechanism: any field can be hidden via a checkbox named `hide_<fieldId>`. Phone numbers and Requirements have theirs hand-written in the HTML; `HIDEABLE_FIELDS` lists the rest (most Personal/Astro/Family fields) and injects an identical checkbox right after each one at page load, rather than repeating the markup by hand |
| `I18N` (`en`/`te`) | 1098–1290 | All UI strings, field labels, placeholders, dropdown option labels, and JS-generated status messages for both languages, keyed identically per language — including `btn.openInChrome` and `msg.inAppEscapeAndroid`/`inAppEscapeOther` |
| `t()`, `label()`, `displayValue()` | 1294–1311 | i18n lookup helpers. `displayValue()` is the important one: select fields store a canonical English value in the DOM, and this maps it to the current language's display text only for rendering — so a record saved while viewing Telugu still has English enum values |
| `applyOptionTranslations()`, `applyStaticTranslations()`, `applyLanguage()` | 1312–1362 | Re-render all translatable UI (labels, placeholders, `<option>` text, preview) when the language changes; persists the choice to `localStorage`; also re-runs `updateInAppEscapeBanner()` so its text follows the current language |
| `syncCardA4MinHeight()` | 1363–1371 | Sets `#card`'s `min-height` from its current rendered width (`width * 297/210`) so the preview always looks at least like an A4 page, via a `ResizeObserver` — a floor, not a fixed height, so longer content still grows the card instead of being clipped |
| `setTemplate()` | 1372–1391 | Swaps the `tpl-*` class on both `#card` and `#igCard`, updates the subtitle text, and persists the choice to `localStorage` |
| `fmtDate()` | 1392–1400 | Formats the `dob` input's ISO value for display (`14 Aug 1996`) |
| Photo upload handling | 1401–1423 | Validates file type (JPG/PNG only via `ALLOWED_PHOTO_TYPES`), reads it as a data URL for the live preview (`photoDataUrl`) |
| `wireCharCount()` | 1424–1440 | Wires a textarea + its counter `<span>` so About Me / Requirements show a live `x/300` count and flag when the limit is reached |
| `wirePhoneField()` | 1441–1454 | Combines a country-code `<select>` and a number `<input>` into one hidden field (`phone`/`father_phone`/`mother_phone`), used by the record and both card renderers |
| `renderPreview()` | 1455–1516 | Rebuilds `#previewBody`'s HTML from current form values: groups fields per section with a `pairMode` (dynamic/fixed/single) controlling row-sharing, skips anything `isFieldHidden()`, and appends the Requirements section |
| `escapeHtml()` | 1517–1525 | HTML-escapes a string for safe interpolation into `innerHTML` |
| `showStatus()` | 1526–1537 | Sets the `#status` banner's text and ok/err/warn styling |
| `isInAppBrowser()` | 1538–1549 | Sniffs `navigator.userAgent` for known in-app WebViews (Instagram, Facebook, TikTok, Line, WeChat) |
| `isAndroidInAppBrowser()`, `buildChromeIntentUrl()`, `updateInAppEscapeBanner()` + load-time call | 1550–1582 | Drives `#inAppEscapeBanner`: on a detected in-app browser, shows it immediately (before any download is attempted) with an Android-only `intent:` link that hands navigation straight to Chrome (`S.browser_fallback_url` covers Chrome-not-installed), or plain "open in Safari" instructions everywhere else — there's no equivalent redirect trick on iOS |
| `compressImage()` | 1583–1600 | Client-side resize (max 800px) + re-encode to JPEG (quality 0.8) before any photo is uploaded, to limit Supabase storage usage |
| `uploadPhoto()`, `uploadCardImage()` | 1601–1622 | Upload the compressed photo / rendered card canvas to the `biodata-photos` / `biodata-cards` Supabase Storage buckets and return their public URLs |
| `fileNameBase()` | 1623–1628 | Derives the downloaded file's name from the entered first/last name |
| `renderCardCanvas()` | 1629–1652 | `html2canvas`-based capture of `#card`, reused by every generator below |
| `triggerDownload()` | 1653–1677 | Shared save mechanism for all three exports. Inside a detected in-app browser, tries `navigator.share({files:[file]})` first (opens the OS share sheet — "Save Image"/"Save to Files" — which some in-app WebViews honor even with no download manager of their own); otherwise, or if sharing fails for any reason other than the user cancelling, falls back to a `Blob`/`URL.createObjectURL()` clicked via a temporarily-attached `<a download>` (replaced an earlier `data:` URI + detached-anchor approach that Instagram's in-app browser silently refused to save) |
| `generatePdf()`, `generateImage()` | 1678–1707 | Fit-to-A4-page PDF export (`jsPDF`, output as a blob) or direct PNG — both `await` `triggerDownload()` |
| `saveToDbIfNeeded()` | 1708–1733 | Builds the record from `FIELDS`, uploads photo/card image if applicable, inserts into `biodata_submissions`; no-ops if already saved this session or no Supabase client is configured. Called from `handleDownload` inside a try/catch that only logs failures |
| `validate()`, `handleDownload()` | 1734–1788 | Shared flow for the PDF/Image buttons: validate → render canvas once → save-if-needed (silently) → run the specific generator → show one generic downloaded/download-failed status |
| `calcAge()`, `val()`, `renderIgCard()`, `generateInstagramImage()` | 1789–1857 | Instagram-specific: computes age from DOB, builds the tagline/detail lines (education, occupation, income, location, religion/caste), and captures `#igCard` at a fixed 1080×1350 size, also `await`-ing `triggerDownload()` |
| `igBtn` click handler + initial `applyLanguage(currentLang)` | 1858–1878 | Same validate → canvas → generate → status flow as `handleDownload`, specialized for the Instagram image (no database save); the final line performs the initial render on page load |

## Key design decisions / gotchas

- **No build step by design.** Everything lives in one HTML file with inline `<style>`/`<script>`; there's no bundler to keep in sync. Any change to behavior means editing `index.html` directly.
- **Database save failures are deliberately invisible to the user.** `handleDownload()` treats `saveToDbIfNeeded()` as fire-and-forget: any error (schema mismatch, network, RLS, etc.) is `console.error`'d and otherwise ignored. Only the download itself (canvas render + `generator()`) can produce the "Could not download..." status. Don't reintroduce database-specific wording into any user-facing message — that was a deliberate fix for exactly this leak.
- **A single "don't show in biodata" mechanism drives every hide checkbox.** A checkbox named `hide_<fieldId>` next to a field means "checked = omit this field from the preview/PDF/image." Phone numbers and Requirements have their checkbox hand-written in the HTML; everything else in `HIDEABLE_FIELDS` gets an identical one injected by JS at load time. Adding a new hideable field means adding its ID to `HIDEABLE_FIELDS`, not writing new checkbox markup.
- **The preview card's height is a floor, not a fixed size.** `syncCardA4MinHeight()` only sets `min-height`; real content (a long About Me, many filled fields) is always allowed to grow the card taller. Earlier attempts using CSS `aspect-ratio` here actually clipped long content — that's why this is JS-driven instead.
- **Templates are CSS variables, not separate markup.** All four visual templates share the exact same `#card`/`#igCard` DOM; switching templates only toggles a `tpl-*` class that overrides custom properties. Adding a new template means adding a `#card.tpl-<name>` CSS block plus registering it in `I18N.*.subtitles` (see `setTemplate()`'s validity check) — not new HTML.
- **Language choice never changes stored data shape.** Dropdown fields keep a canonical English `value` in the DOM regardless of UI language; `displayValue()` maps to the current language purely for display. This is what keeps Supabase records (and the biodata card's data-driven rendering) consistent no matter which language a user filled the form in.
- **The Supabase anon key is meant to be public.** It's restricted entirely by the row-level security policies in `supabase_setup.sql` (insert-only, no `SELECT`/`UPDATE`/`DELETE` for the `anon` role) — this is the standard Supabase pattern for a public-facing form, not a leaked secret. Viewing submitted data requires logging into the Supabase dashboard directly.
- **Storage buckets intentionally have no `SELECT` policy.** The buckets are public, so a known file's direct public URL is already fetchable without RLS; adding a broad `SELECT` policy would instead let anyone *list* every file in the bucket via the Storage API (a warning Supabase's dashboard flags explicitly) — the SQL comments call this out.
- **`saveToDbIfNeeded` runs at most once per page load** (`savedToDb` flag), so downloading PDF, then Image, then Instagram for the same filled-in form doesn't create duplicate submissions.
- **Downloads go through `triggerDownload()`'s Web Share → Blob/attached-anchor fallback chain, not a bare `data:` URI.** The `data:` URI + detached-`<a>` approach this used to use is silently refused by Instagram/Facebook/TikTok's in-app WebViews; a `Blob` object URL clicked via an anchor briefly attached to the DOM, or (in a detected in-app browser) handing the file to `navigator.share()` for the OS's native share sheet, are both more compatible attempts. None of this is guaranteed, though — confirmed on a real device, Instagram's Android in-app browser blocks *both* of these too, because that WebView has no download manager and no share-sheet path out at all in that build. There is no client-side technique that reliably forces a file out of a WebView that's designed not to allow it.
- **The real fix for in-app browsers is escaping them, not out-downloading them.** `updateInAppEscapeBanner()` (driven by `isInAppBrowser()`/`isAndroidInAppBrowser()`) shows a sticky banner at the top of the page *before* the user even tries to download, not just after a failed attempt. On Android it's a real "Open in Chrome" button using an `intent:` URL (`buildChromeIntentUrl()`) — a native OS scheme that hands navigation to Android's intent resolver, bypassing the in-app WebView outright, with a `browser_fallback_url` so it never dead-ends without Chrome installed. This is confirmed working end-to-end (Instagram → banner → Chrome → download) on a real Android device. iOS has no equivalent: Apple doesn't let a webpage force-launch Safari from inside another app's in-app browser, so iOS (and any other non-Android in-app browser) only gets text instructions to open the page in Safari manually — unverified on a real device, since testing that requires an iPhone.
