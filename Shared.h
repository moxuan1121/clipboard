#import <UIKit/UIKit.h>
#define CBPrefs @"com.moxuan1121.clipboard"
#define CBShow "com.moxuan1121.clipboard.show"
#define CBReload "com.moxuan1121.clipboard.reload"
static inline NSUserDefaults *CBDefaults(void) {
    NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:CBPrefs];
    [d registerDefaults:@{@"enabled":@YES, @"height":@420, @"suppressTips":@YES}];
    return d;
}
