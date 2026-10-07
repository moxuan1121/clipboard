import pathlib, plistlib, re, sqlite3

root = pathlib.Path(__file__).resolve().parents[1]
for file in root.rglob('*.plist'):
    if file.name != 'Clipboard.plist' or 'Preferences' in file.parts:
        plistlib.loads(file.read_bytes())
source = (root / 'Store.m').read_text(encoding='utf-8')
sql = re.findall(r'"((?:CREATE TABLE|DELETE FROM|INSERT INTO|SELECT id,text)[^"]+)"', source)
db = sqlite3.connect(':memory:')
db.execute(next(s for s in sql if s.startswith('CREATE')))
db.execute("INSERT INTO history(text,image) VALUES('old entry',X'0102')")
old = db.execute('SELECT id,text,image FROM history').fetchall()
alter = re.search(r'"(ALTER TABLE history ADD COLUMN source TEXT)"', source).group(1)
db.execute(alter)
assert db.execute('SELECT id,text,image FROM history').fetchall() == old
assert db.execute('SELECT source FROM history').fetchone() == (None,)
insert = next(s for s in sql if s.startswith('INSERT'))
trim = next(s for s in sql if s.startswith('DELETE'))
for i in range(501):
    db.execute(insert, (f'text {i}', b'image' if i % 2 else None, 'com.apple.Preferences'))
db.execute(trim)
items = list(db.execute(next(s for s in sql if s.startswith('SELECT'))))
assert len(items) == 500 and items[0][1] == 'text 500' and items[-1][1] == 'text 1'
assert db.execute('SELECT image,source FROM history WHERE id=501').fetchone() == (b'image', 'com.apple.Preferences')
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
assert 'size.width-34)/2), 44.8)' in ui
assert 'UIBlurEffectStyleSystemThinMaterialDark' in ui and '0.06 : 0.34' in ui
assert '%init(URLApplication)' in ui and 'UIApplicationDidFinishLaunchingNotification' not in ui
assert 'CBCompleteURL' not in ui and 'CGRectInset(body, 3, 3)' in ui
assert 'previous.deleteRevealed = NO;' in ui and 'self.revealedCell = visible ? cell : nil;' in ui
assert '- (BOOL)shouldAutorotate { return NO; }' in ui and '- (BOOL)autorotate { return NO; }' in ui
assert 'UIDevice.currentDevice' not in ui and 'UIDeviceOrientation' not in ui and 'CMMotionManager' not in ui
assert 'noteInterfaceOrientationChanged:' in ui and 'activeInterfaceOrientation' in ui
assert 'updateStatusBar:NO duration:0 force:YES' in ui
assert 'colorWithWhite:0.24 alpha:1' in ui and 'borderWidth = 0.5' in ui
assert 'colorWithRed:0.88 green:0.905 blue:0.94 alpha:1' in ui and 'shadowOpacity = dark ? 0 : 0.045' in ui
assert 'self.layer.shadowPath =' in ui
assert 'self.grid.alwaysBounceVertical = YES' in ui and 'CBFilterHistory(self.allItems, self.searchBar.text)' in ui
assert 'self.sourceIcon.frame = CGRectMake(gap, gap, side, side)' in ui and 'MIN(37.5,' in ui
assert 'CGRectInset(body, 12, 4)' in ui and '(body.size.height-side)/2' in ui
assert '_text.font = [UIFont systemFontOfSize:13]' in ui and '_text.numberOfLines = 2' in ui
assert '_text.lineBreakMode = NSLineBreakByTruncatingTail' in ui
assert 'self.contentView.layer.cornerRadius = self.sourceIcon.layer.cornerRadius+gap' in ui
assert 'cornerRadius:self.contentView.layer.cornerRadius' in ui
assert abs(8.25+(44.8-37.5)/2-11.9) < 1e-9
assert abs(56*0.8-44.8) < 1e-9 and 50*0.75 == 37.5
assert (44.8-37.5)/2 > 3  # Equal top, bottom and left margins.
assert '[self.listContainer addSubview:self.searchBar]' in ui and '[self.grid addSubview:self.searchBar]' not in ui
assert 'searchBarShouldEndEditing:(UISearchBar *)bar { return !self.searching; }' in ui
assert 'self.searchBar.enablesReturnKeyAutomatically = NO' in ui
text_change = ui.split('- (void)searchBar:(UISearchBar *)bar textDidChange:')[1].split('\n- (')[0]
assert 'endSearchEditing' not in text_change and 'resignFirstResponder' not in text_change
end_edit = ui.split('- (void)endSearchEditing {')[1].split('\n}')[0]
assert end_edit.index('self.searching = NO') < end_edit.index('resignFirstResponder')
assert 'searchBarCancelButtonClicked' not in ui
assert 'saveText:text image:image source:source' in ui and '_iconCache.countLimit = 32' in ui
settings = (root / 'Preferences/Resources/Root.plist').read_text(encoding='utf-8')
assert '仅支持' not in settings and 'prefs://' not in settings and '呼出方式' not in settings
assert '_text.textColor = UIColor.labelColor;' in ui
delete = next(s for s in sql if s == 'DELETE FROM history WHERE id=?')
before = list(db.execute('SELECT id,text,image FROM history ORDER BY id'))
db.execute(delete, (500,))
assert list(db.execute('SELECT id,text,image FROM history ORDER BY id')) == [row for row in before if row[0] != 500]
db.execute(delete, (499,))
assert list(db.execute('SELECT id,text,image FROM history ORDER BY id')) == [row for row in before if row[0] not in (499,500)]
db.execute(delete, (99999,))
assert db.execute('SELECT count(*) FROM history').fetchone()[0] == 498
print('Plists, 500-item storage, SQLite backup, UI guards, RegionShot APIs and process filters checked.')
