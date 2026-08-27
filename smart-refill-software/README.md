# Smart Eco-Refill System — Software Setup

This gets your database and dashboard fully working **before your hardware parts arrive**.
The "Simulate Device" panel in the web app fakes an ESP32 tap so you can test the entire
pipeline right now.

---

## 1. Create your Supabase project

1. Go to https://supabase.com and sign up (free tier is enough for this project).
2. Click **New Project**. Pick any name (e.g. `eco-refill`), set a database password
   (save it somewhere), pick the region closest to you, and create it. Takes ~2 minutes.

## 2. Run the database schema

1. In your new project, open the **SQL Editor** (left sidebar).
2. Click **New query**.
3. Open `database/schema.sql` from this folder, copy the whole thing, paste it in, and
   click **Run**.
4. You should see `Success. No rows returned` and three demo users will already exist
   (`TAG-DEMO-001`, `TAG-DEMO-002`, `TAG-DEMO-003`) so the leaderboard isn't empty.

## 3. Get your API keys

1. In Supabase, go to **Project Settings → API**.
2. Copy the **Project URL** and the **anon public** key (NOT the `service_role` key —
   that one is secret and should never go in the web app or firmware).

## 4. Connect the web app

1. Open `webapp/index.html` in a text editor.
2. Find this block near the bottom:
   ```js
   const SUPABASE_URL = "https://YOUR-PROJECT-ID.supabase.co";
   const SUPABASE_ANON_KEY = "YOUR-ANON-PUBLIC-KEY";
   ```
3. Replace both values with what you copied in step 3.
4. Save, then just double-click `index.html` to open it in a browser. No build step,
   no npm install — it runs straight from the file.

You should see "connected to supabase" in the top-right pill. If it says "not connected,"
double-check you pasted the URL/key correctly.

## 5. Try it out

- Use the **Simulate Device** panel to log a fake refill. Points and the leaderboard
  update instantly (this uses Supabase Realtime — the same tech your final dashboard
  will use for actual hardware taps).
- Try tapping the same tag twice within 5 seconds — it should get blocked. That's the
  anti-spam trigger in the schema working as intended.
- Look up a user by tag in the "Find your stats" card.

## 6. Hosting it so others can see it (optional, for demos/panel)

Drag the `webapp` folder into https://app.netlify.com/drop — it'll give you a live public
URL in seconds. No account needed for a quick drop. (For anything longer-term, a free
Netlify or GitHub Pages account is fine too.)

---

## For later: what the real ESP32 needs to send

When your hardware is ready, the ESP32 firmware just needs to send an HTTP POST to
Supabase's auto-generated REST API — no custom backend server needed. This is the exact
request the "Simulate Device" button is faking:

```
POST https://YOUR-PROJECT-ID.supabase.co/rest/v1/refills
Headers:
  apikey: YOUR-ANON-PUBLIC-KEY
  Authorization: Bearer YOUR-ANON-PUBLIC-KEY
  Content-Type: application/json
  Prefer: return=minimal

Body:
{
  "rfid_tag": "TAG-DEMO-001",
  "volume_ml": 500
}
```

You can test this from a computer right now (before writing any Arduino code) using curl:

```bash
curl -X POST "https://YOUR-PROJECT-ID.supabase.co/rest/v1/refills" \
  -H "apikey: YOUR-ANON-PUBLIC-KEY" \
  -H "Authorization: Bearer YOUR-ANON-PUBLIC-KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=minimal" \
  -d '{"rfid_tag": "TAG-DEMO-001", "volume_ml": 350}'
```

On the ESP32 side, this is a plain `HTTPClient` POST with a JSON body — the same shape
as any other HTTP request the Arduino framework supports. Nothing about the database
needs to change once you get to that stage; the firmware team just needs to reproduce
the request above using the actual sensor readings (bottle-verified + flow-sensor volume)
instead of hardcoded test values.

## Notes on the points logic

Currently set in `schema.sql`:
- **Points:** 1 point per 10 mL dispensed
- **Bottles saved:** 1 per 500 mL cumulative

If your group's research methodology defines different numbers, they're both in one
place — the `handle_new_refill()` function in `schema.sql` — easy to change without
touching the web app or firmware at all.
