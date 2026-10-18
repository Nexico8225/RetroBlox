# scripts/ — RetroBlox maintenance tools

Active tools live here. One-off historical scripts (old E2E runs,
patches, checks) are in `archive/` — do not run them blind, they
document past migrations.

## Database
| Script | What it does |
|---|---|
| `seed.ts` | Seed demo users/games into db/custom.db |
| `attach_builds.ts` | Attach real demo .zip builds to seeded games |
| `create_admin.ts` | Create/promote the admin account |
| `backup_db.ts` | Timestamped backup of db/custom.db -> db/backups/ |
| `restore_db.ts` | Restore a backup |
| `protect_data.ts` | Guard against accidental data wipes |
| `db_inspect.mjs` | Quick look inside the SQLite file |
| `backfill-file-blobs.js` | Copy disk uploads INTO the DB (BLOB storage) |

## Assets / branding
| Script | What it does |
|---|---|
| `process_assets.py` | Cursors/logo/image processing into public/retro/ |
| `crop_retrofont.py` | Crop the owner's font sheet -> public/retro/font/A..Z.png |
| `gen_retrofont_meta.py` | Regenerate src/lib/retrofont-meta.ts glyph widths |
| `fix_x_glyph.py` | One-glyph repair helper |
| `make_grid.py` | Letter-grid detection for the font sheet |
| `crop_auth_bg.py` / `make_auth_bg.py` | Auth key-art -> public/retro/auth-bg.jpg |
| `make_default_face.py` | Classic default face texture |
| `make_rig_template.py` | R6 rig template model (backlog) |
| `make_ugc_templates.py` | UGC item template models |
| `make_painted_shirt.py` / `make_test_models.py` | Shirt/model generators |

## Project hygiene
| Script | What it does |
|---|---|
| `cleanup_project.sh` | Remove transient trash (screenshots, pastes, caches) |
| `organize_scripts.sh` | This organization (idempotent) |

`blockyard-src/` and `_DANGER_do_not_run/` belong to the Godot game
AI's world — hands off.
