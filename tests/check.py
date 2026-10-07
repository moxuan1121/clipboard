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
assert 'jbroot(@"/var/mobile/Library/Clipboard")' in source
assert 'sqlite3_backup_init' in source and 'SQLITE_OPEN_READONLY' in source
db.commit()
destination = sqlite3.connect(':memory:')
db.backup(destination)
assert list(destination.execute('SELECT * FROM history')) == list(db.execute('SELECT * FROM history'))
assert len(list(db.execute('SELECT * FROM history'))) == 500  # migration leaves source intact
ui = (root / 'Clipboard.xm').read_text(encoding='utf-8')
assert 'UITableView' not in ui and 'self.trigger' not in ui
assert '点击复制或粘贴' not in ui and 'title.text = @"剪切板"' in ui
assert 'RSKAOpenTokens' in ui and 'RSShowFloatingImage' in ui
assert 'IOHIDEventSystemClientDispatchEvent' in ui and 'sendAction:' not in ui
assert 'self.presentation != token' in ui and 'self.presentation != hiddenToken' in ui
assert 'size.width-34)/2), 56)' in ui
assert 'UIBlurEffectStyleSystemThinMaterialDark' in ui and '0.06 : 0.34' in ui
assert '%init(URLApplication)' in ui and 'UIApplicationDidFinishLaunchingNotification' not in ui
assert 'CBCompleteURL' not in ui and 'CGRectInset(body, 3, 3)' in ui
delete = next(s for s in sql if s == 'DELETE FROM history WHERE id=?')
before = list(db.execute('SELECT id,text,image FROM history ORDER BY id'))
db.execute(delete, (500,))
assert list(db.execute('SELECT id,text,image FROM history ORDER BY id')) == [row for row in before if row[0] != 500]
db.execute(delete, (499,))
assert list(db.execute('SELECT id,text,image FROM history ORDER BY id')) == [row for row in before if row[0] not in (499,500)]
db.execute(delete, (99999,))
assert db.execute('SELECT count(*) FROM history').fetchone()[0] == 498
print('Plists, 500-item storage, SQLite backup, UI guards, RegionShot APIs and process filters checked.')
