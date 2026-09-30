#!/usr/bin/env python3
"""One-shot local migration: User.playerNo (short public id) + UgcComment table.
Mirrors exactly what sync-schema.mjs will do on the live Turso DB at deploy."""
import sqlite3, sys

DB = '/home/z/my-project/db/custom.db'
con = sqlite3.connect(DB)
cur = con.cursor()

# 1) add playerNo column if missing
cols = [r[1] for r in cur.execute('PRAGMA table_info(User)').fetchall()]
if 'playerNo' not in cols:
    cur.execute('ALTER TABLE User ADD COLUMN playerNo INTEGER NOT NULL DEFAULT 0')
    print('added User.playerNo')
else:
    print('User.playerNo already exists')

# 2) backfill: join order (createdAt ASC) -> 1, 2, 3 ...
rows = cur.execute('SELECT id FROM User WHERE playerNo = 0 ORDER BY createdAt ASC, id ASC').fetchall()
nxt = cur.execute('SELECT COALESCE(MAX(playerNo), 0) FROM User').fetchone()[0]
for (uid,) in rows:
    nxt += 1
    cur.execute('UPDATE User SET playerNo = ? WHERE id = ?', (nxt, uid))
print(f'backfilled {len(rows)} users; highest playerNo now {nxt}')

# 3) unique index (Prisma names it User_playerNo_key)
cur.execute('CREATE UNIQUE INDEX IF NOT EXISTS "User_playerNo_key" ON "User"("playerNo")')
print('unique index ready')

# 4) UgcComment table
cur.execute('''CREATE TABLE IF NOT EXISTS "UgcComment" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "itemId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "text" TEXT NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "UgcComment_itemId_fkey" FOREIGN KEY ("itemId") REFERENCES "AvatarItem" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "UgcComment_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User" ("id") ON DELETE CASCADE ON UPDATE CASCADE
)''')
cur.execute('CREATE INDEX IF NOT EXISTS "UgcComment_itemId_createdAt_idx" ON "UgcComment"("itemId", "createdAt")')
print('UgcComment table ready')

con.commit()
con.close()
print('DONE')
