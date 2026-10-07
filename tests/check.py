import pathlib, plistlib, re, sqlite3

root = pathlib.Path(__file__).resolve().parents[1]
for file in root.rglob('*.plist'):
    if file.name != 'Clipboard.plist' or 'Preferences' in file.parts:
        plistlib.loads(file.read_bytes())
source = (root / 'Store.m').read_text(encoding='utf-8')
sql = re.findall(r'"((?:CREATE TABLE|DELETE FROM|INSERT INTO|SELECT id,text)[^"]+)"', source)
db = sqlite3.connect(':memory:')
db.execute(next(s for s in sql if s.startswith('CREATE')))
insert = next(s for s in sql if s.startswith('INSERT'))
trim = next(s for s in sql if s.startswith('DELETE'))
for i in range(501):
    db.execute(insert, (f'text {i}', b'image' if i % 2 else None))
db.execute(trim)
items = list(db.execute(next(s for s in sql if s.startswith('SELECT'))))
assert len(items) == 500 and items[0][1] == 'text 500' and items[-1][1] == 'text 1'
assert db.execute('SELECT image FROM history WHERE id=500').fetchone()[0] == b'image'
filter_text = (root / 'Clipboard.plist').read_text()
assert 'com.apple.UIKit' not in filter_text and 'com.apple.springboard' in filter_text
assert '/var/jb' not in (root / 'Makefile').read_text()
print('Plists, 500-item storage, image persistence and process filters checked.')
