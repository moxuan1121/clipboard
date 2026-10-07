#import <Foundation/Foundation.h>

static inline BOOL CBIsHistoryURL(id value) {
    NSString *text = [value isKindOfClass:NSURL.class] ? [value absoluteString] : ([value isKindOfClass:NSString.class] ? value : nil);
    if (!text.length) return NO;
    NSRange colon = [text rangeOfString:@":"];
    if (colon.location == NSNotFound) return NO;
    NSString *scheme = [[text substringToIndex:colon.location] lowercaseString];
    if (![@[@"prefs", @"app-prefs"] containsObject:scheme]) return NO;
    NSString *parameters = [text substringFromIndex:colon.location+1];
    while ([parameters hasPrefix:@"/"] || [parameters hasPrefix:@"?"]) parameters = [parameters substringFromIndex:1];
    NSURLComponents *parts = [NSURLComponents componentsWithString:[@"clipboard://route?" stringByAppendingString:parameters]];
    NSString *root = nil;
    for (NSURLQueryItem *item in parts.queryItems) {
        if ([item.name.lowercaseString isEqualToString:@"root"]) {
            if (root || !item.value) return NO;
            root = item.value;
        }
    }
    return [root isEqualToString:@"clipboard_history"];
}
