#import <Foundation/Foundation.h>
@interface CBStore : NSObject
- (BOOL)saveText:(NSString *)text image:(NSData *)image;
- (NSArray<NSDictionary *> *)history;
- (NSData *)imageForID:(NSNumber *)identifier;
- (BOOL)deleteItem:(NSNumber *)identifier;
@end
