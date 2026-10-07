#import <Foundation/Foundation.h>
#include <stdint.h>
#include <string.h>

// Apple Blocks ABI: read the signature instead of guessing the private URL callback type.
static inline void CBCompleteURL(id callback) {
    if (!callback) return;
    struct CBBlock { void *isa; int flags, reserved; void *invoke; const uintptr_t *descriptor; };
    const struct CBBlock *block = (__bridge const struct CBBlock *)callback;
    if (!(block->flags & (1 << 30)) || !block->descriptor) return;
    const uintptr_t *descriptor = block->descriptor + 2;
    if (block->flags & (1 << 25)) descriptor += 2;
    const char *encoding = *(const char * const *)descriptor;
    if (!encoding) return;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:encoding];
    if (strcmp(signature.methodReturnType, "v") || signature.numberOfArguments < 2) return;
    const char *argument = [signature getArgumentTypeAtIndex:1];
    if (signature.numberOfArguments == 2 && (*argument == 'B' || *argument == 'c')) ((void (^)(BOOL))callback)(YES);
    else if (signature.numberOfArguments == 2 && *argument == '@') ((void (^)(NSError *))callback)(nil);
    else if (signature.numberOfArguments == 3 && (*argument == 'B' || *argument == 'c') && *[signature getArgumentTypeAtIndex:2] == '@')
        ((void (^)(BOOL, NSError *))callback)(YES, nil);
}

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
