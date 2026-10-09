#import "../URLRoute.h"
#import "../ScreenOrientation.h"
#import "../HistorySearch.h"
#include <assert.h>
int main(void) {
    @autoreleasepool {
        NSArray *records = @[@{@"id":@3, @"text":@"image", @"image":@YES}, @{@"id":@2, @"text":@"text"}, @{@"id":@1, @"text":@"image", @"image":@YES}];
        NSArray *remaining = CBHistoryWithoutID(records, @2);
        assert(remaining.count == 2 && remaining[0] == records[0] && remaining[1] == records[2]);
        assert(records.count == 3); // Existing image metadata objects stay unchanged.
        assert(CBHistoryWithoutID(records, @999).count == 3);
        assert(CBHistoryWithoutID(@[], @2).count == 0);
        NSArray *filtered = CBFilterHistory(records, @"text");
        assert(CBHistoryWithoutID(filtered, @2).count == 0);
        assert(CBHistoryWithoutID(CBHistoryWithoutID(records, @3), @1).count == 1);
        assert(CBHistoryWithoutID(CBHistoryWithoutID(CBHistoryWithoutID(records, @3), @2), @1).count == 0);
        NSArray *history = @[@{@"text":@"Café hello"}, @{@"text":@"剪切板测试"}, @{@"text":@"", @"image":@YES}];
        assert(CBFilterHistory(history, @"  \n").count == 3);
        assert(CBFilterHistory(history, @"CAFE").count == 1);
        assert(CBFilterHistory(history, @"  切板  ").count == 1);
        assert(CBFilterHistory(history, @"absent").count == 0);
        // Deleting a query down to one character, then clearing it, keeps filtering valid.
        assert(CBFilterHistory(history, @"剪切").count == 1);
        assert(CBFilterHistory(history, @"剪").count == 1);
        assert(CBFilterHistory(history, @"").count == 3);
        assert(history.count == 3);
        assert(CBScreenOrientation(1) == 1);
        assert(CBScreenOrientation(3) == 3 && CBScreenOrientation(4) == 4);
        assert(CBScreenOrientation(0) == 1 && CBScreenOrientation(2) == 1);
        assert(CBScreenOrientation(-1) == 1 && CBScreenOrientation(5) == 1);
        for (NSString *url in @[@"prefs://root=clipboard_history", @"prefs:root=clipboard_history", @"app-prefs://root=clipboard_history", @"prefs://root=clipboard%5Fhistory", @"prefs://root=clipboard_history#fragment"])
            assert(CBIsHistoryURL([NSURL URLWithString:url]));
        for (id url in @[@"prefs://root=OTHER", @"https://root=clipboard_history", @"prefs://root=clipboard_history&root=OTHER", @"prefs://root", @"prefs://root=clipboard_history_extra", @42, NSNull.null])
            assert(!CBIsHistoryURL(url));
    }
    return 0;
}
