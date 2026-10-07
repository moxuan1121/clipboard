#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../Shared.h"
#import <notify.h>
@interface CBRootController : PSListController
@end
@implementation CBRootController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return [CBDefaults() objectForKey:[specifier propertyForKey:@"key"]] ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    if ([[specifier propertyForKey:@"key"] isEqual:@"height"]) {
        double height = [value doubleValue];
        value = @(MIN(MAX(isfinite(height) ? height : 420, 180), 900));
    }
    NSUserDefaults *defaults = CBDefaults();
    [defaults setObject:value forKey:[specifier propertyForKey:@"key"]];
    [defaults synchronize];
    notify_post(CBReload);
}
- (void)openHistory { notify_post(CBShow); }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"clipboard";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
}
@end
