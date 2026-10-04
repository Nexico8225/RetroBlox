#!/usr/bin/env python3
"""E2E check for the NEW permanent UGC delete (remove = delete = true).
Uses a throwaway LOCAL account on the LOCAL dev server only — production is
never touched. Publishes a 2D UGC item, hard-deletes it, and verifies the row
is GONE from the database (not soft-deleted)."""
import io, json, struct, urllib.request, uuid

BASE = 'http://127.0.0.1:3000'


def req(path, method='GET', data=None, headers=None, raw=False):
    r = urllib.request.Request(BASE + path, data=data, method=method)
    for k, v in (headers or {}).items():
        r.add_header(k, v)
    with urllib.request.urlopen(r) as res:
        body = res.read()
        return res.status, (body if raw else json.loads(body or b'{}'))


def png_byte():
    # 1x1 red PNG
    return bytes.fromhex(
        '89504e470d0a1a0a0000000d49484452000000010000000108020000009077'
        '53de0000000c4944415408d763f8cfc00000030101'
        '00cbfe062b0000000049454e44ae426082'
    )


def main():
    user = 'deletecheck1'
    b = uuid.uuid4().hex[:8].encode()
    form = (
        f'--{b.decode()}\r\nContent-Disposition: form-data; name="username"\r\n\r\n{user}\r\n'
        f'--{b.decode()}\r\nContent-Disposition: form-data; name="password"\r\n\r\nretro123\r\n'
        f'--{b.decode()}--\r\n'.encode()
    )
    st, res = req('/api/auth/signup', 'POST', form, {'Content-Type': f'multipart/form-data; boundary={b.decode()}'})
    if st == 400:
        # account exists from a previous run — log in instead
        st, res = req('/api/auth/login', 'POST', form, {'Content-Type': f'multipart/form-data; boundary={b.decode()}'})
    tok = res['token']
    auth = {'Authorization': f'Bearer {tok}'}
    print('1. signup/login OK')

    # publish a 2D UGC item (face) — multipart with a tiny png
    b = uuid.uuid4().hex[:8].encode()
    parts = []
    for k, v in [('name', 'Delete Check Item'), ('type', 'face'), ('description', 'e2e')]:
        parts.append(f'--{b.decode()}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
    parts.append(
        f'--{b.decode()}\r\nContent-Disposition: form-data; name="image"; filename="t.png"\r\n'
        f'Content-Type: image/png\r\n\r\n'.encode() + png_byte() + b'\r\n'
    )
    parts.append(f'--{b.decode()}--\r\n'.encode())
    st, res = req('/api/catalog', 'POST', b''.join(parts), {**auth, 'Content-Type': f'multipart/form-data; boundary={b.decode()}'})
    item_id = res['item']['id']
    print('2. published item', res['item']['assetId'], item_id)

    # hard delete it
    st, res = req(f'/api/catalog/{item_id}', 'DELETE', None, auth)
    print('3. DELETE ->', st, res)

    # must be GONE, not soft-deleted
    try:
        st, _ = req(f'/api/catalog/{item_id}', 'GET', None, auth)
        print('4. GET after delete ->', st, 'FAIL: still reachable' if st == 200 else '')
    except urllib.error.HTTPError as e:
        print('4. GET after delete ->', e.code, '(gone for good) OK' if e.code == 404 else 'FAIL')

    # catalog list must not contain it
    st, res = req('/api/catalog', 'GET', None, auth)
    ids = [i['id'] for i in res['items']]
    print('5. catalog list contains it:', item_id in ids, '(should be False)')

    # and the DATABASE row must not exist at all
    import sqlite3
    con = sqlite3.connect('/home/z/my-project/db/custom.db')
    n = con.execute('SELECT COUNT(*) FROM AvatarItem WHERE id = ?', (item_id,)).fetchone()[0]
    deleted_n = con.execute('SELECT COUNT(*) FROM AvatarItem WHERE id = ? AND deletedAt IS NOT NULL', (item_id,)).fetchone()[0]
    print('6. DB rows with that id:', n, '(should be 0) | soft-deleted rows:', deleted_n, '(should be 0)')
    con.close()
    print('PASS' if n == 0 else 'FAIL')


if __name__ == '__main__':
    main()
