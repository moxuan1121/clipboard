#import "Store.h"
#import <sqlite3.h>
@implementation CBStore {
    sqlite3 *_db;
}
- (instancetype)init {
    if ((self = [super init])) {
        NSString *directory = @"/var/mobile/Library/Clipboard";
        NSError *error;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:&error]) return nil;
        if (sqlite3_open([[directory stringByAppendingPathComponent:@"history.sqlite"] fileSystemRepresentation], &_db) != SQLITE_OK) return nil;
        sqlite3_busy_timeout(_db, 1000);
        if (sqlite3_exec(_db, "CREATE TABLE IF NOT EXISTS history(id INTEGER PRIMARY KEY, text TEXT, image BLOB);", NULL, NULL, NULL) != SQLITE_OK) return nil;
    }
    return self;
}
- (void)dealloc { if (_db) sqlite3_close(_db); }
- (BOOL)saveText:(NSString *)text image:(NSData *)image {
    if (!_db || (!text.length && !image.length)) return NO;
    if (sqlite3_exec(_db, "BEGIN IMMEDIATE", NULL, NULL, NULL) != SQLITE_OK) return NO;
    sqlite3_stmt *statement = NULL;
    BOOL ok = sqlite3_prepare_v2(_db, "INSERT INTO history(text,image) VALUES(?,?)", -1, &statement, NULL) == SQLITE_OK;
    if (ok) {
        if (text.length) sqlite3_bind_text(statement, 1, text.UTF8String, -1, SQLITE_TRANSIENT);
        if (image.length) sqlite3_bind_blob64(statement, 2, image.bytes, image.length, SQLITE_TRANSIENT);
        ok = sqlite3_step(statement) == SQLITE_DONE;
    }
    sqlite3_finalize(statement);
    if (ok) ok = sqlite3_exec(_db, "DELETE FROM history WHERE id NOT IN (SELECT id FROM history ORDER BY id DESC LIMIT 500)", NULL, NULL, NULL) == SQLITE_OK;
    if (!ok) { sqlite3_exec(_db, "ROLLBACK", NULL, NULL, NULL); return NO; }
    if (sqlite3_exec(_db, "COMMIT", NULL, NULL, NULL) != SQLITE_OK) { sqlite3_exec(_db, "ROLLBACK", NULL, NULL, NULL); return NO; }
    return YES;
}
- (NSArray *)history {
    NSMutableArray *items = [NSMutableArray array];
    sqlite3_stmt *s = NULL;
    if (_db && sqlite3_prepare_v2(_db, "SELECT id,text,image IS NOT NULL FROM history ORDER BY id DESC LIMIT 500", -1, &s, NULL) == SQLITE_OK) {
        while (sqlite3_step(s) == SQLITE_ROW) {
            const char *text = (const char *)sqlite3_column_text(s, 1);
            [items addObject:@{@"id":@(sqlite3_column_int64(s, 0)), @"text":text ? [NSString stringWithUTF8String:text] : @"", @"image":@(sqlite3_column_int(s, 2))}];
        }
    }
    sqlite3_finalize(s);
    return items;
}
- (NSData *)imageForID:(NSNumber *)identifier {
    sqlite3_stmt *s = NULL;
    NSData *data = nil;
    if (_db && sqlite3_prepare_v2(_db, "SELECT image FROM history WHERE id=?", -1, &s, NULL) == SQLITE_OK) {
        sqlite3_bind_int64(s, 1, identifier.longLongValue);
        if (sqlite3_step(s) == SQLITE_ROW) data = [NSData dataWithBytes:sqlite3_column_blob(s, 0) length:sqlite3_column_bytes(s, 0)];
    }
    sqlite3_finalize(s);
    return data;
}
@end
