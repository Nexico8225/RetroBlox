import sqlite3

db_path = r"D:\Folders\RetroBlox\RetroBlox\db\custom.db"
conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("SELECT id, username, role FROM User WHERE username LIKE 'mxl%' LIMIT 10")
bots = c.fetchall()
print(f"Sample mxl bots ({len(bots)}):")
for b in bots:
    print(b)

c.execute("SELECT COUNT(*) FROM User WHERE username LIKE 'mxl%'")
count = c.fetchone()[0]
print(f"Total mxl bots: {count}")

conn.close()
