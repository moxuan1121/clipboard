#import "../URLRoute.h"
#include <assert.h>
int main(void) {
    @autoreleasepool {
        for (NSString *url in @[@"prefs://root=clipboard_history", @"prefs:root=clipboard_history", @"app-prefs://root=clipboard_history", @"prefs://root=clipboard%5Fhistory", @"prefs://root=clipboard_history#fragment"])
            assert(CBIsHistoryURL([NSURL URLWithString:url]));
        for (id url in @[@"prefs://root=OTHER", @"https://root=clipboard_history", @"prefs://root=clipboard_history&root=OTHER", @"prefs://root", @"prefs://root=clipboard_history_extra", @42, NSNull.null])
            assert(!CBIsHistoryURL(url));
        __block int completed = 0;
        CBCompleteURL(^(BOOL success) { assert(success); completed++; });
        CBCompleteURL(^(NSError *error) { assert(!error); completed++; });
        CBCompleteURL(^(BOOL success, NSError *error) { assert(success && !error); completed++; });
        CBCompleteURL(nil);
        assert(completed == 3);
    }
    return 0;
}
