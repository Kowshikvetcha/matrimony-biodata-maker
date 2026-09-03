# Matrimonial Biodata Maker

A single-page web app for building an Indian matrimonial biodata: fill in a form, preview a formatted biodata card live, and download it as a PDF, PNG image, or an Instagram-post-style image. Optionally saves each submission (and the generated photo/card images) to a Supabase project.

Live at [matrimony-biodata-maker.com](https://matrimony-biodata-maker.com) (see `CNAME`).

## Features

- Multi-section form (personal, astrological, education/career, family, and contact details) with a live-updating preview card
- Four visual templates (Classic, Modern, Elegant, Royal) switchable without losing form data
- Export as PDF (`jsPDF`) or PNG image (`html2canvas`), sized to fit a single A4 page
- A separate 1080×1350 Instagram-post export with its own layout, generated off-screen from the same data
- Bilingual UI (English / Telugu) with a language switcher — dropdown values are stored in canonical English internally regardless of the display language, so saved data stays consistent
- Per-field checkboxes to include/exclude phone numbers (own, father's, mother's) from the rendered biodata and Instagram image
- Client-side photo compression (resized and re-encoded to JPEG before upload) to keep Supabase storage usage low
- Optional persistence to Supabase: form data, uploaded photo, and the rendered card image

## Prerequisites

This is a static, dependency-free front end — there is no package manager, build step, or framework. All third-party libraries (`html2canvas`, `jsPDF`, `@supabase/supabase-js`) are loaded from CDN `<script>` tags directly in `index.html`. You only need:

- A modern web browser
- (Optional, for the "save to database" feature) A [Supabase](https://supabase.com) project

## Installation

```bash
git clone https://github.com/Kowshikvetcha/matrimony-biodata-maker.git
cd matrimony-biodata-maker
```

There is nothing to install — `index.html` is the whole app.

## Configuration

Saving submissions to a database is optional; the form, preview, and all three downloads (PDF/image/Instagram) work with no configuration at all. To enable persistence:

1. Create a Supabase project and run `supabase_setup.sql` against it (SQL Editor in the Supabase dashboard). This creates the `public.biodata_submissions` table, enables row-level security with an insert-only policy for the `anon` role, and creates two public storage buckets (`biodata-photos` for uploaded photos, `biodata-cards` for the rendered biodata card image) with insert-only policies — there is deliberately no `SELECT` policy, since the buckets are public and files are only ever fetched by their direct public URL, not listed. You view submitted data and photos from the Supabase dashboard (Table Editor / Storage), which uses your own login rather than the public key below.
2. In `index.html`, set the `SUPABASE_URL` and `SUPABASE_ANON_KEY` constants near the top of the `<script>` block to your project's API URL and anon/publishable key (Project Settings → API in the Supabase dashboard). If left unset, the app silently skips the save step and only performs the download.

The SQL file's final section is a migration block for bringing an already-live table up to date with fields added later (e.g. `first_name`/`last_name` split, `diet`, `living_country`); it's idempotent (`add column if not exists`) and safe to run on a fresh database too.

## Running the project

Since it's static HTML, either:

- Open `index.html` directly in a browser, or
- Serve it locally so relative paths behave exactly as in production:

  ```bash
  python -m http.server 8123
  ```

  (this is what `.claude/launch.json` uses to preview the app during development)

## Deployment

The site is deployed as a static GitHub Pages site. `CNAME` pins the custom domain (`matrimony-biodata-maker.com`); there is no CI/build workflow — the repo's files are served as-is.

## Project structure

```
index.html          the entire app: markup, styles, and JS (form, i18n, preview,
                     PDF/image/Instagram generation, Supabase persistence)
supabase_setup.sql   schema, RLS policies, and storage buckets for the optional
                     Supabase backend, plus an idempotent migration block
logo.svg             favicon / header logo
CNAME                GitHub Pages custom domain
.claude/             Claude Code project config (not part of the app itself)
docs/                architecture and code walkthrough — see docs/ARCHITECTURE.md
```

## Further documentation

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the single `index.html` file is organized internally and what each part does.
