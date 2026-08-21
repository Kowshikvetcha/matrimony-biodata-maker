-- Table to store submitted biodata
create table public.biodata_submissions (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  full_name text,
  gender text,
  dob date,
  time_of_birth text,
  place_of_birth text,
  height text,
  weight text,
  complexion text,
  marital_status text,
  religion text,
  caste text,
  sub_caste text,
  gothra text,
  mother_tongue text,
  manglik text,
  rashi text,
  nakshatra text,
  education text,
  occupation text,
  company_name text,
  annual_income text,
  father_name text,
  father_occupation text,
  mother_name text,
  mother_occupation text,
  siblings text,
  family_type text,
  current_address text,
  phone text,
  email text,
  about_me text,
  photo_url text,
  card_image_url text
);

-- Lock the table down: anyone can submit (insert), nobody can read/edit/delete
-- via the public anon key. You view submissions from the Supabase dashboard
-- (Table Editor), which uses your own privileged login, not the anon key.
alter table public.biodata_submissions enable row level security;

create policy "Allow public inserts"
  on public.biodata_submissions
  for insert
  to anon
  with check (true);

-- Storage bucket for optional profile photos
insert into storage.buckets (id, name, public)
values ('biodata-photos', 'biodata-photos', true)
on conflict (id) do nothing;

create policy "Public read of biodata photos"
  on storage.objects
  for select
  to public
  using (bucket_id = 'biodata-photos');

create policy "Anon upload of biodata photos"
  on storage.objects
  for insert
  to anon
  with check (bucket_id = 'biodata-photos');

-- Storage bucket for the generated biodata card image (the rendered
-- template, same image the user downloads as PDF/PNG)
insert into storage.buckets (id, name, public)
values ('biodata-cards', 'biodata-cards', true)
on conflict (id) do nothing;

create policy "Public read of biodata cards"
  on storage.objects
  for select
  to public
  using (bucket_id = 'biodata-cards');

create policy "Anon upload of biodata cards"
  on storage.objects
  for insert
  to anon
  with check (bucket_id = 'biodata-cards');
