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
  Generator -->|triggers file save| Download[Browser download: PDF / PNG]
  Download --> Status
```

A single concrete flow, PDF download, traced through the real code:

1. The user fills the form; every `input` event on `#bioForm` re-runs `renderPreview()`, which reads each field, looks up its translated label/value via `label()`/`displayValue()`, skips any field whose `hide_<fieldId>` checkbox is checked (`isFieldHidden()`), and rewrites `#previewBody`'s HTML grouped into sections. A `pairMode` per group ("dynamic", "fixed", or "single" — see `renderPreview()`) controls whether two fields share a row or each gets its own; a separate "Requirements" section is appended below the grouped fields if that field has content and isn't hidden.
2. Clicking **Download as PDF** calls the `pdfBtn` click handler, which calls `handleDownload(btn, "pdf", generatePdf)`.
3. `handleDownload` first calls `validate()` (native HTML5 `checkValidity()` on required fields); if invalid it shows a generic "fill in required fields" status and stops.
4. It renders the current `#card` DOM node to a canvas once via `renderCardCanvas()` (`html2canvas(card, {scale:2, ...})`), so the same canvas can be reused for both the database save and the actual download.
5. If a Supabase client was configured, `saveToDbIfNeeded(cardCanvas)` builds a plain object from `FIELDS`, optionally uploads the chosen photo (after client-side compression via `compressImage()`) and the rendered card canvas to Supabase Storage, and inserts one row into `public.biodata_submissions` — guarded by a `savedToDb` flag so a submission is only ever saved once per page load. **Any failure here (network, schema mismatch, etc.) is only `console.error`'d — it never reaches the status banner or blocks the download**, since a database-save outcome is an internal implementation detail, not something the user needs to know about.
6. `generatePdf(canvas)` runs regardless of whether the save succeeded: it computes a scale that fits the canvas onto a single A4 page in `jsPDF`, centers it, and calls `pdf.save(...)`, which triggers the browser's file download.
7. `showStatus()` shows one generic status at the end: `"<Label> downloaded!"` on success, or `"Could not download the <label>. Please try again."` if anything in the whole try block threw — the same two messages are reused for PDF, Image, and Instagram downloads (see `I18N.*.msg.downloaded`/`downloadFailed`).

The Image and Instagram-post downloads follow the same `handleDownload` path with a different generator function (`generateImage`, or the separate `igBtn` handler calling `generateInstagramImage`, which re-renders the off-screen `#igCard` element with `renderIgCard()` before capturing it).

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

### `<style>` (lines 15–558)

| Section | Lines (approx.) | Purpose |
|---|---|---|
| `:root` variables, base/body/header | 16–320 | Color palette (maroon/gold on cream), spacing/radius/shadow tokens, the two Google Fonts, the two-column `.layout` grid, header, form panel/fieldset/input/button styling, status banner, character-count and "don't show" checkbox styling |
| Preview card + `.kv`/`.kv-item` grid | 321–425 | `#card`'s layout, including `container-type: inline-size` so the field grid can respond to the card's own rendered width (not the viewport) via `@container`, and the `.kv-wide` class that forces a field onto its own row |
| The 4 templates | 426–494 | `tpl-classic`/`tpl-modern`/`tpl-elegant`/`tpl-royal` are CSS custom-property overrides on `#card`/`#igCard` (`--c-bg`, `--c-heading`, `--c-accent`, etc.), not separate markup |
| `#igCard` | 495–557 | Fixed 1080×1350px off-screen (`left:-9999px`) card used only as an `html2canvas` capture source for the Instagram export; reuses the same CSS variables as the main card so template/color choices stay in sync |

### `<body>` (lines 560–1014)

| Section | Lines (approx.) | Purpose |
|---|---|---|
| Header | 562–571 | App title (i18n-driven) and the compact English/Telugu `<select>` |
| `#bioForm` — Personal Details | 580–729 | Required core fields (name, gender, DOB, height, marital status, religion, community, diet, location) plus optional ones (mother tongue, category, complexion) |
| `#bioForm` — Astro Details | 730–760 | Gothra, maternal uncle's gotram, manglik, rashi, nakshatra — all optional |
| `#bioForm` — Education & Career | 761–823 | Qualification, college, work sector, occupation, company, annual income (see the expanded income bracket list in the `<select>`) |
| `#bioForm` — Family Details | 824–853 | Parents' names/occupations, siblings |
| `#bioForm` — Contact Information | 854–934 | Phone numbers (own/father's/mother's, each a country-code `<select>` + number `<input>` combined into one hidden field), email, address |
| `#bioForm` — Photo Upload, About Me, Requirements | 935–971 | Photo dropzone; About Me and Partner Requirements textareas, each with a live character counter (300-char limit) and a "don't show in biodata" checkbox for Requirements |
| Template picker + `#card` preview | 972–1004 | The 4 template swatches and the live preview card (`#photoBox`, `#nameLine`, `#previewBody`) |
| `#igCard` markup | 1005–1014 | The off-screen Instagram card's DOM, populated by `renderIgCard()` on demand |

### `<script>` (lines 1015–1755)

| Function / section | Lines (approx.) | Purpose |
|---|---|---|
| `SUPABASE_URL`/`SUPABASE_ANON_KEY` + client init | 1020–1027 | Hardcoded project config; `supabaseClient` stays `null` if the URL/key look unset, which disables persistence but not the downloads |
| `FIELDS` | 1028–1042 | Canonical list of form field IDs that map 1:1 to `biodata_submissions` columns — used when building the record to insert |
| `isFieldHidden()`, `HIDEABLE_FIELDS` injection | 1043–1059 | The generic "don't show in biodata" mechanism: any field can be hidden via a checkbox named `hide_<fieldId>`. Phone numbers and Requirements have theirs hand-written in the HTML; `HIDEABLE_FIELDS` lists the rest (most Personal/Astro/Family fields) and injects an identical checkbox right after each one at page load, rather than repeating the markup by hand |
| `I18N` (`en`/`te`) | 1069–1257 | All UI strings, field labels, placeholders, dropdown option labels, and JS-generated status messages for both languages, keyed identically per language |
| `t()`, `label()`, `displayValue()` | 1261–1278 | i18n lookup helpers. `displayValue()` is the important one: select fields store a canonical English value in the DOM, and this maps it to the current language's display text only for rendering — so a record saved while viewing Telugu still has English enum values |
| `applyOptionTranslations()`, `applyStaticTranslations()`, `applyLanguage()` | 1279–1328 | Re-render all translatable UI (labels, placeholders, `<option>` text, preview) when the language changes; persists the choice to `localStorage` |
| `syncCardA4MinHeight()` | 1329–1335 | Sets `#card`'s `min-height` from its current rendered width (`width * 297/210`) so the preview always looks at least like an A4 page, via a `ResizeObserver` — a floor, not a fixed height, so longer content still grows the card instead of being clipped |
| `setTemplate()` | 1336–1357 | Swaps the `tpl-*` class on both `#card` and `#igCard`, updates the subtitle text, and persists the choice to `localStorage` |
| `fmtDate()` | 1358–1364 | Formats the `dob` input's ISO value for display (`14 Aug 1996`) |
| Photo upload handling | 1365–1387 | Validates file type (JPG/PNG only via `ALLOWED_PHOTO_TYPES`), reads it as a data URL for the live preview (`photoDataUrl`) |
| `wireCharCount()` | 1390–1406 | Wires a textarea + its counter `<span>` so About Me / Requirements show a live `x/300` count and flag when the limit is reached |
| `wirePhoneField()` | 1407–1420 | Combines a country-code `<select>` and a number `<input>` into one hidden field (`phone`/`father_phone`/`mother_phone`), used by the record and both card renderers |
| `renderPreview()` | 1421–1481 | Rebuilds `#previewBody`'s HTML from current form values: groups fields per section with a `pairMode` (dynamic/fixed/single) controlling row-sharing, skips anything `isFieldHidden()`, and appends the Requirements section |
| `escapeHtml()` | 1483–1488 | HTML-escapes a string for safe interpolation into `innerHTML` |
| `showStatus()` | 1492–1499 | Sets the `#status` banner's text and ok/err styling |
| `compressImage()` | 1500–1517 | Client-side resize (max 800px) + re-encode to JPEG (quality 0.8) before any photo is uploaded, to limit Supabase storage usage |
| `uploadPhoto()`, `uploadCardImage()` | 1518–1538 | Upload the compressed photo / rendered card canvas to the `biodata-photos` / `biodata-cards` Supabase Storage buckets and return their public URLs |
| `fileNameBase()` | 1540–1544 | Derives the downloaded file's name from the entered first/last name |
| `renderCardCanvas()`, `generatePdf()`, `generateImage()` | 1546–1582 | `html2canvas`-based capture of `#card`, then either fit-to-A4-page PDF export (`jsPDF`) or direct PNG download |
| `saveToDbIfNeeded()` | 1583–1607 | Builds the record from `FIELDS`, uploads photo/card image if applicable, inserts into `biodata_submissions`; no-ops if already saved this session or no Supabase client is configured. Called from `handleDownload` inside a try/catch that only logs failures |
| `validate()`, `handleDownload()` | 1609–1662 | Shared flow for the PDF/Image buttons: validate → render canvas once → save-if-needed (silently) → run the specific generator → show one generic downloaded/download-failed status |
| `calcAge()`, `val()`, `renderIgCard()`, `generateInstagramImage()` | 1664–1734 | Instagram-specific: computes age from DOB, builds the tagline/detail lines (education, occupation, income, location, religion/caste), and captures `#igCard` at a fixed 1080×1350 size |
| `igBtn` click handler + initial `applyLanguage(currentLang)` | 1735–1754 | Same validate → canvas → generate → status flow as `handleDownload`, specialized for the Instagram image (no database save); the final line performs the initial render on page load |

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
