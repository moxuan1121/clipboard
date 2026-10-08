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
assert 'Clipboard_INSTALL_PATH = /usr/lib/TweakInject' in (root / 'Makefile').read_text()
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
assert 'animateWithDuration:0.16 delay:0' in ui and 'animateWithDuration:0.12 delay:0' in ui
assert 'hideWithCompletion' not in ui
long_press = ui.split('- (void)longPress:')[1].split('- (void)closeTextEditor')[0]
assert long_press.index('[self hideAnimated:NO]') < long_press.index('if (imageItem) openImage')
assert 'else openText(item[@"text"])' in long_press
assert 'self.presentation != token' in long_press and 'imageItem && !image' in long_press
route = ui.split('static BOOL CBHandleURL(id url) {')[1].split('// RegionShot')[0]
assert 'if (NSThread.isMainThread) [controller show]' in route and 'notify_post' not in route
assert 'else dispatch_async(dispatch_get_main_queue()' in route
assert 'notify_register_dispatch(CBShow' in ui  # External Darwin entry stays available.
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
assert 'colorWithWhite:0.91 alpha:1' in ui and 'shadowOpacity = dark ? 0 : 0.025' in ui
assert 'colorWithWhite:0 alpha:0.06' in ui
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
assert 'BOOL blankIcon = !source.length || [source isEqualToString:@"com.apple.springboard"]' in ui
assert 'if (!blankIcon && !icon &&' in ui
assert 'cell.sourceIcon.backgroundColor = icon ? UIColor.clearColor : [UIColor colorWithWhite:0.97 alpha:1]' in ui
assert 'cell.sourceIcon.layer.borderWidth = icon ? 0 : 0.5' in ui
assert 'cell.sourceIcon.image = icon ?: CBPlaceholderIcon()' in ui
placeholder = ui.split('static UIImage *CBPlaceholderIcon(void) {')[1].split('typedef struct')[0]
assert 'dispatch_once(&once' in placeholder and 'UIGraphicsImageRenderer' in placeholder
assert 'grid.lineWidth = 0.25' in placeholder and 'bezierPathWithOvalInRect' in placeholder
assert 'for (int i = 1; i < 6; i++)' in placeholder and '@[@0.9, @0.55, @0.4]' in placeholder
assert 'cornerRadius:8.25] addClip' in placeholder
assert 'if (self.sourceIcon.image)' not in ui  # Placeholder keeps the same content alignment.
settings = (root / 'Preferences/Resources/Root.plist').read_text(encoding='utf-8')
assert '仅支持' not in settings and 'prefs://' not in settings and '呼出方式' not in settings
assert '_text.textColor = UIColor.labelColor;' in ui
assert 'CGRectOffset(self.deleteButton.frame, -42, 0)' in ui and 'cell.canEdit = !hasImage' in ui
assert 'UITextView *text' in ui and 'editor.view.safeAreaLayoutGuide.bottomAnchor' in ui
assert 'UIModalPresentationFullScreen' not in ui
assert '[self.panel addSubview:self.textEditor.view]' in ui
assert '[self.textEditor didMoveToParentViewController:self]' in ui
assert '[self.textEditor removeFromParentViewController]' in ui
assert 'self.textEditor.view.frame = self.panel.bounds' in ui
assert '- (void)hideEditorKeyboard { [self.textEditor.view endEditing:YES]; }' in ui and '收起键盘' in ui
# The same panel geometry is used while searching and while editing text.
for screen, keyboard_height, requested in [(844, 336, 420), (390, 210, 420), (844, 0, 420)]:
    bottom = screen-keyboard_height
    height = min(max(requested, 180), bottom)
    assert bottom-height >= 0 and bottom <= screen
    assert bottom+keyboard_height == screen
    if not keyboard_height:
        assert bottom == screen and height == requested
assert 'updateText:value forID:identifier' in ui
edit_sql = re.search(r'"(UPDATE history SET text=\? WHERE id=\? AND image IS NULL)"', source).group(1)
before_edit = db.execute('SELECT id,text,image,source FROM history ORDER BY id').fetchall()
text_id = next(row[0] for row in before_edit if row[2] is None)
image_id = next(row[0] for row in before_edit if row[2] is not None)
value = "第一行\n第二行 'quoted' 😀"
db.execute(edit_sql, (value, text_id))
assert db.execute('SELECT text FROM history WHERE id=?', (text_id,)).fetchone() == (value,)
assert db.execute('SELECT id,image,source FROM history WHERE id=?', (text_id,)).fetchone() == next((row[0],row[2],row[3]) for row in before_edit if row[0] == text_id)
image_before = db.execute('SELECT * FROM history WHERE id=?', (image_id,)).fetchone()
assert db.execute(edit_sql, ('not allowed', image_id)).rowcount == 0
assert db.execute('SELECT * FROM history WHERE id=?', (image_id,)).fetchone() == image_before
assert db.execute(edit_sql, ('missing', 99999)).rowcount == 0
delete = next(s for s in sql if s == 'DELETE FROM history WHERE id=?')
before = list(db.execute('SELECT id,text,image FROM history ORDER BY id'))
db.execute(delete, (500,))
assert list(db.execute('SELECT id,text,image FROM history ORDER BY id')) == [row for row in before if row[0] != 500]
db.execute(delete, (499,))
assert list(db.execute('SELECT id,text,image FROM history ORDER BY id')) == [row for row in before if row[0] not in (499,500)]
db.execute(delete, (99999,))
assert db.execute('SELECT count(*) FROM history').fetchone()[0] == 498
print('Plists, 500-item storage, SQLite backup, UI guards, RegionShot APIs and process filters checked.')
