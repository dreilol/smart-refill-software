-- ============================================================================
-- SMART ECO-REFILL SYSTEM — DATABASE SCHEMA
-- Run this entire file in: Supabase Dashboard -> SQL Editor -> New Query -> Run
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. USERS TABLE
-- One row per person with an RFID tag (student ID sticker or card).
-- ----------------------------------------------------------------------------
create table if not exists users (
  id            uuid primary key default gen_random_uuid(),
  rfid_tag      text unique not null,          -- the ID read off the RFID chip
  full_name     text not null,
  student_id    text,                          -- optional school ID number
  points        integer not null default 0,
  total_ml      numeric not null default 0,    -- lifetime volume dispensed
  bottles_saved integer not null default 0,    -- total_ml / 500, floored
  created_at    timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 2. REFILLS TABLE
-- One row per completed refill event. This is the table your ESP32
-- (or, for now, your test/simulator) sends an HTTP POST to insert into.
-- ----------------------------------------------------------------------------
create table if not exists refills (
  id            uuid primary key default gen_random_uuid(),
  rfid_tag      text not null references users(rfid_tag),
  volume_ml     numeric not null check (volume_ml > 0 and volume_ml <= 4000),
  points_earned integer not null default 0,    -- filled in automatically, see trigger below
  device_id     text default 'esp32-prototype-01',
  created_at    timestamptz not null default now()
);

-- Speeds up "show me this user's refill history" and leaderboard-by-recency queries
create index if not exists idx_refills_rfid_tag on refills(rfid_tag);
create index if not exists idx_refills_created_at on refills(created_at desc);


-- ----------------------------------------------------------------------------
-- 3. POINTS CONVERSION LOGIC
-- Rule used here (change the numbers to match your paper's methodology):
--   - 1 point per 10 mL dispensed
--   - 1 "bottle saved" credited per 500 mL cumulative (i.e. one refill of a
--     standard 500 mL bottle = 1 bottle saved)
-- This runs automatically in the database the instant a refill is inserted,
-- so your ESP32 firmware and your frontend never have to calculate this
-- themselves — they just read the result.
-- ----------------------------------------------------------------------------
create or replace function handle_new_refill()
returns trigger
language plpgsql
security definer  -- allows this function to update `users` even though the
                   -- caller (anon/ESP32) does not have direct UPDATE rights
as $$
declare
  calculated_points integer;
begin
  calculated_points := round(new.volume_ml / 10);
  new.points_earned := calculated_points;

  update users
  set
    points        = points + calculated_points,
    total_ml      = total_ml + new.volume_ml,
    bottles_saved = floor((total_ml + new.volume_ml) / 500)
  where rfid_tag = new.rfid_tag;

  return new;
end;
$$;

drop trigger if exists on_refill_insert on refills;
create trigger on_refill_insert
  before insert on refills
  for each row
  execute function handle_new_refill();


-- ----------------------------------------------------------------------------
-- 4. ANTI-SPAM GUARD (basic protection against a spammed/looping device)
-- Rejects a second refill for the same tag within 5 seconds. This is a
-- cheap software-side backstop — your real anti-spoofing defense is still
-- the HC-SR04 ultrasonic bottle check on the hardware side, as argued in
-- your research gap.
-- ----------------------------------------------------------------------------
create or replace function prevent_rapid_duplicate_refill()
returns trigger
language plpgsql
as $$
begin
  if exists (
    select 1 from refills
    where rfid_tag = new.rfid_tag
      and created_at > now() - interval '5 seconds'
  ) then
    raise exception 'Duplicate refill blocked: same tag used again within 5 seconds';
  end if;
  return new;
end;
$$;

drop trigger if exists on_refill_spam_check on refills;
create trigger on_refill_spam_check
  before insert on refills
  for each row
  execute function prevent_rapid_duplicate_refill();


-- ----------------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY (RLS)
-- This controls what the public "anon" key (used by your ESP32 AND your
-- web app) is allowed to do. Without this, anyone with your anon key could
-- read/write anything.
-- ----------------------------------------------------------------------------
alter table users enable row level security;
alter table refills enable row level security;

-- Anyone (students viewing the dashboard, the ESP32) can read user stats
-- for the leaderboard. No sensitive data lives here, so this is safe.
drop policy if exists "public can read users" on users;
create policy "public can read users"
  on users for select
  using (true);

-- Direct writes to `users` are NOT allowed from the app/device — points are
-- only ever changed via the trigger above (which runs as security definer).
-- (No insert/update/delete policy is created for `users`, so anon has none.)

-- The ESP32 (and your simulator) can insert new refill rows.
drop policy if exists "anon can insert refills" on refills;
create policy "anon can insert refills"
  on refills for insert
  with check (true);

-- Anyone can read refill history (for the "recent activity" feed).
drop policy if exists "public can read refills" on refills;
create policy "public can read refills"
  on refills for select
  using (true);


-- ----------------------------------------------------------------------------
-- 6. SEED DATA (a few test users so the leaderboard isn't empty on day 1)
-- Delete or edit these once you have real users.
-- ----------------------------------------------------------------------------
insert into users (rfid_tag, full_name, student_id)
values
  ('TAG-DEMO-001', 'Juan Dela Cruz', '2026-00123'),
  ('TAG-DEMO-002', 'Maria Santos', '2026-00456'),
  ('TAG-DEMO-003', 'Jose Rizal', '2026-00789')
on conflict (rfid_tag) do nothing;

-- ============================================================================
-- DONE. Next steps:
--   1. Go to Project Settings -> API in Supabase, copy your Project URL
--      and "anon public" key.
--   2. Paste those into webapp/index.html (see the CONFIG section at the top
--      of that file).
--   3. Open index.html in a browser and try the "Simulate Device" panel.
-- ============================================================================
