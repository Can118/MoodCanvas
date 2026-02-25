# MoodCanvas – Setup Guide

## Security model summary

| What | Where stored | Who can see it |
|---|---|---|
| User phone number | Never stored — only HMAC-SHA256 hash | Nobody (not even Supabase admins in plaintext) |
| HMAC secret | Supabase Edge Function secrets vault | Server-side only |
| Firebase UID | Supabase `users.id` (plaintext) | Group members only (RLS-enforced) |
| Supabase JWT | iOS Keychain (`WhenUnlockedThisDeviceOnly`) | This device only |
| Supabase anon key | App binary + Secrets.xcconfig | Public by design — RLS makes it safe |
| Service role key | Supabase Edge Function secrets vault | Server-side only, never in app |

---

## Step 1 — Supabase project

1. Create a project at [supabase.com](https://supabase.com)
2. Run `Supabase/schema.sql` in **SQL Editor → New Query**
3. Copy from **Project Settings → API**:
   - Project URL → `SUPABASE_URL`
   - `anon` / `public` key → `SUPABASE_ANON_KEY`

---

## Step 2 — Firebase project

1. Create a project at [console.firebase.google.com](https://console.firebase.google.com)
2. Add an iOS app — bundle ID: `com.moodcanvas.app`
3. Download `GoogleService-Info.plist`
4. **Authentication → Sign-in method → Phone → Enable**
5. Add test numbers for development (avoids using real SMS):
   - Authentication → Sign-in method → Phone → **Phone numbers for testing**
   - e.g. `+15555550100` / code `123456`
6. Copy the **Web API Key** from Project Settings → General

---

## Step 3 — Deploy Edge Functions

Install the Supabase CLI:
```bash
brew install supabase/tap/supabase
supabase login
supabase link --project-ref YOUR_PROJECT_ID
```

Set secrets (server-side only — never in the app):
```bash
# Firebase Web API Key (from Firebase Console → Project Settings → General)
supabase secrets set FIREBASE_WEB_API_KEY=your_firebase_web_api_key

# Generate a strong random secret for phone hashing:
# openssl rand -hex 32
supabase secrets set PHONE_HASH_SECRET=your_64_char_hex_secret
```

Deploy both functions:
```bash
supabase functions deploy authenticate
supabase functions deploy match-contacts
```

---

## Step 4 — iOS credentials (gitignored)

Copy the example and fill in your values:
```bash
cp MoodCanvas/Config/Secrets.xcconfig.example MoodCanvas/Config/Secrets.xcconfig
```

Edit `Secrets.xcconfig`:
```
SUPABASE_URL = https://YOUR_PROJECT_ID.supabase.co
SUPABASE_ANON_KEY = YOUR_SUPABASE_ANON_KEY
```

Drag `GoogleService-Info.plist` into Xcode → `MoodCanvas` folder.
Target membership: **MoodCanvas only** (not extensions).

---

## Step 5 — Xcode signing

For each of the 3 targets (MoodCanvas, MoodCanvasWidget, MoodCanvasiMessage):
- Signing & Capabilities → Team → your Apple Developer account

For App Group (shared widget/iMessage storage):
- Main app → **+ Capability → App Groups → `group.com.moodcanvas.app`**
- Repeat for both extensions

For Firebase push notifications (required for phone auth on real devices):
- MoodCanvas → + Capability → **Push Notifications**
- Upload APNs key in Firebase Console → Project Settings → Cloud Messaging

---

## Step 6 — Re-generate project after any project.yml change

```bash
cd ~/Desktop/MoodCanvas
xcodegen generate
```

**Never edit `.xcodeproj` directly.**

---

## What NOT to do

- ❌ Never commit `Secrets.xcconfig` or `GoogleService-Info.plist`
- ❌ Never use the Supabase **service role key** in the iOS app
- ❌ Never store phone numbers in Supabase (schema enforces this — only `phone_hash`)
- ❌ Never disable RLS in production
