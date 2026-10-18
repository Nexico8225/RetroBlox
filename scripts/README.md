# scripts/ — RetroBlox Maintenance & Developer Tools

Active tools live here. One-off historical scripts (old E2E runs, patches, migration checks) are moved to `archive/` — do not run them blind, they document past migrations.

## Active Database & Platform Tools
| Script | Command | Purpose |
|---|---|---|
| `backup_db.ts` | `npm run backup` | Timestamped backup of `db/custom.db` into `db/backups/` |
| `restore_db.ts` | `npm run restore` | Restores database from latest or chosen backup |
| `protect_data.ts` | `npm run protect` | Safety check against accidental data loss and ensures admin user exists |
| `sync-schema.mjs` | `npm run build` | Syncs schema columns and unique indices on SQLite / Turso cloud |
| `create_admin.ts` | `npx tsx scripts/create_admin.ts` | Upserts/promotes owner admin account (`Nexico8225`) |
| `dev_game_seed.ts` | `npx tsx scripts/dev_game_seed.ts` | Seeds demo games for development |
| `db_inspect.mjs` | `node scripts/db_inspect.mjs` | Quick inspector for tables, row counts, and schema health |
| `turso_migrate.sh` | `bash scripts/turso_migrate.sh` | Migrates local SQLite database to Turso cloud LibSQL |

## Asset & Game Tools
| Script | Command | Purpose |
|---|---|---|
| `make_godot_kit_zip.py` | `python scripts/make_godot_kit_zip.py` | Bundles `public/godot/RetroBloxPlayer` into downloadable kit zip |
| `make_wordmark.py` | `python scripts/make_wordmark.py` | Generates 2006 retro wordmark assets |
| `parse_baseplate.py` | `python scripts/parse_baseplate.py` | Parses classic baseplate model parts and coordinates |

## `archive/`
Contains one-off E2E tests, audit scripts, and historical migrations:
- `cleanup_market_e2e.ts`
- `debug_counter.cjs`
- `e2e_market2.cjs`
- `e2e_market3.cjs`
- `e2e_update5.cjs`
- `migrate_player_no.py`
- `test_hard_delete.py`
- `test_sync_drift.cjs`
