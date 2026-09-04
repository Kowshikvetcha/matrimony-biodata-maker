-- Table to store submitted biodata
create table public.biodata_submissions (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  first_name text,
  last_name text,
  gender text,
  dob date,
  height text,
  complexion text,
  marital_status text,
  religion text,
  caste text,
  category text,
  diet text,
  living_country text,
  living_state text,
  living_city text,
  gothra text,
  mama_gotram text,
  mother_tongue text,
  manglik text,
  rashi text,
  nakshatra text,
  education text,
  college_name text,
  work_sector text,
  occupation text,
  company_name text,
  annual_income text,
  father_name text,
  father_occupation text,
  mother_name text,
  mother_occupation text,
  siblings text,
  siblings_occupation text,
  current_address text,
  phone text,
  father_phone text,
  mother_phone text,
  email text,
  about_me text,
  requirements text,
  photo_url text,
  card_image_url text
);

-- Lock the table down: anyone can submit (insert), nobody can read/edit/delete
-- via the public anon key. You view submissions from the Supabase dashboard
-- (Table Editor), which uses your own privileged login, not the anon key.
alter table public.biodata_submissions enable row level security;

drop policy if exists "Allow public inserts" on public.biodata_submissions;
create policy "Allow public inserts"
  on public.biodata_submissions
  for insert
  to anon
  with check (true);

-- Storage bucket for optional profile photos.
-- No SELECT policy: the bucket is public, so GET on a known file's
-- public URL (.../object/public/biodata-photos/<file>) already works
-- without RLS. Adding a broad SELECT policy would instead let anyone
-- LIST every file in the bucket via the Storage API, which is the
-- "Clients can list all files in this bucket" warning Supabase flags.
insert into storage.buckets (id, name, public)
values ('biodata-photos', 'biodata-photos', true)
on conflict (id) do nothing;

drop policy if exists "Public read of biodata photos" on storage.objects;

drop policy if exists "Anon upload of biodata photos" on storage.objects;
create policy "Anon upload of biodata photos"
  on storage.objects
  for insert
  to anon
  with check (bucket_id = 'biodata-photos');

-- Storage bucket for the generated biodata card image (the rendered
-- template, same image the user downloads as PDF/PNG). Same reasoning
-- as above: no SELECT policy needed or wanted.
insert into storage.buckets (id, name, public)
values ('biodata-cards', 'biodata-cards', true)
on conflict (id) do nothing;

drop policy if exists "Public read of biodata cards" on storage.objects;

drop policy if exists "Anon upload of biodata cards" on storage.objects;
create policy "Anon upload of biodata cards"
  on storage.objects
  for insert
  to anon
  with check (bucket_id = 'biodata-cards');

-- ============================================================
-- MIGRATION (run this once against the already-live project to
-- bring an existing biodata_submissions table up to date with the
-- shaadi.com-style form fields added later). Safe to skip if
-- you're running this whole file fresh on a brand new project.
-- Every add-column line below is non-destructive and safe to
-- re-run any number of times — existing rows just get NULL in a
-- newly added column, nothing is ever overwritten or removed.
-- ============================================================
alter table public.biodata_submissions
  add column if not exists first_name text,
  add column if not exists last_name text,
  add column if not exists diet text,
  add column if not exists living_country text,
  add column if not exists living_state text,
  add column if not exists living_city text,
  add column if not exists college_name text,
  add column if not exists work_sector text,
  add column if not exists father_phone text,
  add column if not exists mother_phone text,
  add column if not exists category text,
  add column if not exists siblings text,
  add column if not exists siblings_occupation text,
  add column if not exists mama_gotram text,
  add column if not exists requirements text;

-- ============================================================
-- CLEANUP — drops columns the form no longer writes to.
-- DROP COLUMN is NOT reversible from the SQL editor: back up first
-- if you haven't confirmed these are empty/unwanted, e.g.
--   create table public.biodata_submissions_backup as
--   select * from public.biodata_submissions;
-- ============================================================
alter table public.biodata_submissions
  drop column if exists full_name,
  drop column if exists family_type,
  drop column if exists time_of_birth,
  drop column if exists place_of_birth,
  drop column if exists weight,
  drop column if exists sub_caste;
