#import <Foundation/Foundation.h>
static inline NSArray *CBFilterHistory(NSArray *items, NSString *text) {
    NSString *query = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!query.length) return items;
    NSMutableArray *matches = [NSMutableArray array];
    for (NSDictionary *item in items) {
        NSString *value = item[@"text"];
        if ([value isKindOfClass:NSString.class] && [value rangeOfString:query options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) [matches addObject:item];
    }
    return matches;
}
