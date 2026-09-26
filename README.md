# RetroBlox

A retro 2016-Roblox-style sandbox platform: accounts, avatars, games,
catalog, community — with a Godot multiplayer player that logs into
the site and wears your account avatar in-game.

## Stack
- Next.js 16 (App Router) + React 19 + TypeScript
- Prisma 6 + SQLite — the whole database is `db/custom.db`
- File storage = BLOBs inside that DB (`UploadedFile.data`), served by
  `/api/files/[id]` with Range support — survives any host
- Godot 4.5 player project in `public/godot/RetroBloxPlayer/`
  (owned by the game AI — do not edit from the website side)

## Run it
```bash
npm install
npx prisma generate
npm run dev        # http://localhost:3000
```
No DATABASE_URL needed — `src/lib/db.ts` resolves the DB path
automatically (set one only to override).

## Deploy (Vercel / Netlify)
`next.config.ts` + `netlify.toml` already ship `db/custom.db` and the
Prisma schema inside every serverless function. Logins work out of the
box. LIMIT without a managed DB: lambdas are read-only — signups,
uploads and purchases are REJECTED (e.g. "The Test Bank could not
credit your wallet") because SQLite cannot be written on a read-only
disk.

### Real persistence: move the DB to Turso (free)
1. Install the Turso CLI and log in:
   - macOS/Linux: `curl -sSfL https://get.tur.so/install.sh | bash && turso auth login`
   - Windows: grab `turso_cli-x86_64-pc-windows-msvc.zip` from
     <https://github.com/tursodatabase/turso/releases/latest>, extract it,
     open CMD in that folder and run `turso.exe auth login`
2. `turso db create retroblox`
3. `bash scripts/turso_migrate.sh retroblox`  (copies schema + ALL data)
4. Set env vars on the host and redeploy:
   - `DATABASE_URL` = `turso db show retroblox --url` (libsql://…)
   - `LIBSQL_AUTH_TOKEN` = `turso db tokens create retroblox`
`src/lib/db.ts` auto-switches to libSQL adapter mode for `libsql://`
URLs — same Prisma client, writes work on every host.

## Layout
```
src/app/            pages + API routes (see src/app/api/)
src/components/retro/  one component per page view + Shell (header/sidebar)
src/lib/            db, auth (v2 tokens), uploads, platform API, text FX,
                    avatar assets, sprite font meta, easter eggs
prisma/schema.prisma  the data model
db/custom.db          THE database (git-tracked — commit it when data matters)
public/retro/         cursors, logo, auth key art, sprite font A..Z
public/godot/         the multiplayer player + game (game AI's domain)
brand-assets/         the owner's original art (logo, font sheet, mockups)
scripts/              maintenance tools (scripts/README.md), history in archive/
download/             owner deliverables (game master prompt, handoff prompt)
worklog.md            the project's memory — every task logs here
```

## Ground rules (short version)
- Replies to the owner: English. Icons: SVG, no emoji.
- No AI-slop copy: no "Est. 2016", no "Powering Imagination", no
  invented marketing. Plain, honest, 2016-flavored text only.
- The Godot folder is another AI's domain. `.git` is never deleted.
- The platform API contract (`/api/platform/*`, `/api/gamedata/*`,
  `/api/playtime`, ...) is consumed by the game player — extend, never break.
