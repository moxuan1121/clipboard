#import <Foundation/Foundation.h>
static inline NSArray *CBHistoryWithoutID(NSArray *items, NSNumber *identifier) {
    return [items filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
        return ![item[@"id"] isEqual:identifier];
    }]];
}
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
