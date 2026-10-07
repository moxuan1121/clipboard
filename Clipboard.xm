#import "Shared.h"
#import "Store.h"
#import <ImageIO/ImageIO.h>
#import <notify.h>
#import <AudioToolbox/AudioToolbox.h>

@interface CBWindow : UIWindow
@end
@interface UIKeyboardImpl : UIView
+ (instancetype)activeInstance;
- (id)inputDelegate;
@end

@interface CBController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic,strong) CBWindow *overlay;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UITableView *table;
@property(nonatomic,strong) UIButton *trigger;
@property(nonatomic,strong) CBStore *store;
@property(nonatomic,strong) NSArray *items;
@property(nonatomic,strong) dispatch_queue_t queue;
@property(nonatomic) NSInteger lastChange;
@property(nonatomic) BOOL visible;
@property(nonatomic) BOOL locked;
@property(nonatomic,weak) UIResponder *pasteTarget;
- (void)reloadPreferences;
- (void)capture;
- (void)show;
- (void)hide;
@end
static CBController *controller;

@implementation CBController
- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.moxuan1121.clipboard.storage", DISPATCH_QUEUE_SERIAL);
        dispatch_sync(_queue, ^{ self.store = [CBStore new]; });
        _lastChange = [UIPasteboard generalPasteboard].changeCount;
        _items = @[];
    }
    return self;
}
- (void)loadView {
    UIControl *root = [[UIControl alloc] initWithFrame:UIScreen.mainScreen.bounds];
    [root addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
    self.view = root;
    self.panel = [UIView new];
    self.panel.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.panel.layer.cornerRadius = 28;
    self.panel.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    self.panel.clipsToBounds = YES;
    [root addSubview:self.panel];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 8, 220, 42)];
    title.text = @"剪贴板 · 历史记录";
    title.font = [UIFont boldSystemFontOfSize:18];
    [self.panel addSubview:title];
    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.rowHeight = 72;
    self.table.backgroundColor = UIColor.clearColor;
    [self.panel addSubview:self.table];
    self.trigger = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.trigger setTitle:@"剪贴板" forState:UIControlStateNormal];
    self.trigger.backgroundColor = UIColor.systemBlueColor;
    [self.trigger setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.trigger.layer.cornerRadius = 20;
    self.trigger.accessibilityLabel = @"打开剪贴板历史";
    [self.trigger addTarget:self action:@selector(show) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:self.trigger];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat value = [CBDefaults() doubleForKey:@"height"];
    CGFloat height = MIN(MAX(isfinite(value) ? value : 420, 180), b.size.height);
    CGFloat width = b.size.width > b.size.height ? MIN(520, b.size.width) : b.size.width;
    self.panel.frame = CGRectMake((b.size.width-width)/2, b.size.height-height, width, height);
    self.table.frame = CGRectMake(0, 50, width, MAX(height-50, 0));
    self.table.contentInset = UIEdgeInsetsMake(0, 0, self.view.safeAreaInsets.bottom, 0);
    self.trigger.frame = CGRectMake(b.size.width-92-self.view.safeAreaInsets.right, MAX(20, b.size.height*0.6), 80, 40);
}
- (void)reloadPreferences {
    NSUserDefaults *d = CBDefaults();
    if (![d boolForKey:@"enabled"] || self.locked) [self hide];
    self.trigger.hidden = self.visible || self.locked || ![d boolForKey:@"enabled"] || ![d boolForKey:@"trigger"];
    self.panel.hidden = !self.visible;
    [self.view setNeedsLayout];
}
- (void)hide {
    self.visible = NO;
    self.panel.hidden = YES;
    self.view.backgroundColor = UIColor.clearColor;
    self.items = @[];
    [self.table reloadData];
    self.trigger.hidden = self.locked || ![CBDefaults() boolForKey:@"enabled"] || ![CBDefaults() boolForKey:@"trigger"];
}
- (void)show {
    if (self.locked || ![CBDefaults() boolForKey:@"enabled"]) return;
    self.visible = YES;
    Class keyboardClass = NSClassFromString(@"UIKeyboardImpl");
    id keyboard = [keyboardClass respondsToSelector:@selector(activeInstance)] ? [keyboardClass activeInstance] : nil;
    self.pasteTarget = [keyboard respondsToSelector:@selector(inputDelegate)] ? [keyboard inputDelegate] : nil;
    self.panel.hidden = NO;
    self.trigger.hidden = YES;
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.12];
    [self refresh];
}
- (void)refresh {
    dispatch_async(self.queue, ^{
        NSArray *items = [self.store history];
        dispatch_async(dispatch_get_main_queue(), ^{ if (self.visible) { self.items = items; [self.table reloadData]; } });
    });
}
- (void)capture {
    if (![CBDefaults() boolForKey:@"enabled"]) return;
    UIPasteboard *pb = UIPasteboard.generalPasteboard;
    if (pb.changeCount == self.lastChange) return;
    self.lastChange = pb.changeCount;
    NSString *text = pb.string;
    NSData *image = [pb dataForPasteboardType:@"public.png"] ?: [pb dataForPasteboardType:@"public.jpeg"];
    if (!image && pb.hasImages) image = UIImagePNGRepresentation(pb.image);
    if (!text.length && !image.length) return;
    dispatch_async(self.queue, ^{
        if ([self.store saveText:text image:image]) dispatch_async(dispatch_get_main_queue(), ^{ if (self.visible) [self refresh]; });
    });
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return self.items.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"history"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"history"];
    NSDictionary *item = self.items[path.row];
    cell.tag = [item[@"id"] integerValue];
    cell.textLabel.text = [item[@"image"] boolValue] ? @"图片" : item[@"text"];
    cell.textLabel.numberOfLines = 1;
    cell.detailTextLabel.text = [item[@"image"] boolValue] ? @"点击复制或粘贴图片" : @"点击复制或粘贴文字";
    cell.imageView.image = [UIImage systemImageNamed:[item[@"image"] boolValue] ? @"photo" : @"doc.text"];
    cell.backgroundColor = UIColor.clearColor;
    if ([item[@"image"] boolValue]) {
        NSNumber *identifier = item[@"id"];
        __weak UITableViewCell *weakCell = cell;
        dispatch_async(self.queue, ^{
            NSData *data = [self.store imageForID:identifier];
            CGImageSourceRef source = data ? CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL) : NULL;
            CGImageRef image = source ? CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)@{(id)kCGImageSourceCreateThumbnailFromImageAlways:@YES, (id)kCGImageSourceCreateThumbnailWithTransform:@YES, (id)kCGImageSourceThumbnailMaxPixelSize:@120}) : NULL;
            UIImage *thumbnail = image ? [UIImage imageWithCGImage:image] : nil;
            if (image) CGImageRelease(image);
            if (source) CFRelease(source);
            dispatch_async(dispatch_get_main_queue(), ^{ if (thumbnail && weakCell.tag == identifier.integerValue) { weakCell.imageView.image = thumbnail; [weakCell setNeedsLayout]; } });
        });
    }
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *item = self.items[path.row];
    [table deselectRowAtIndexPath:path animated:YES];
    dispatch_async(self.queue, ^{
        NSData *image = [item[@"image"] boolValue] ? [self.store imageForID:item[@"id"]] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.visible || self.locked) return;
            if ([item[@"image"] boolValue] && !image.length) return;
            if (image) {
                CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)image, NULL);
                NSString *type = source ? (__bridge NSString *)CGImageSourceGetType(source) : @"public.png";
                [[UIPasteboard generalPasteboard] setData:image forPasteboardType:type ?: @"public.png"];
                if (source) CFRelease(source);
            } else [UIPasteboard generalPasteboard].string = item[@"text"];
            self.lastChange = UIPasteboard.generalPasteboard.changeCount;
            [self hide];
            AudioServicesPlaySystemSound(1519);
            UIResponder *target = self.pasteTarget;
            Class keyboardClass = NSClassFromString(@"UIKeyboardImpl");
            id keyboard = [keyboardClass respondsToSelector:@selector(activeInstance)] ? [keyboardClass activeInstance] : nil;
            id currentTarget = [keyboard respondsToSelector:@selector(inputDelegate)] ? [keyboard inputDelegate] : nil;
            if (target && target == currentTarget && [target respondsToSelector:@selector(paste:)] &&
                [target respondsToSelector:@selector(canPerformAction:withSender:)] && [target canPerformAction:@selector(paste:) withSender:nil]) {
                [UIApplication.sharedApplication sendAction:@selector(paste:) to:target from:nil forEvent:nil];
            }
        });
    });
}
@end

// The root control only intercepts outside taps while the history is visible.
@implementation CBWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!controller.visible && hit != controller.trigger && ![hit isDescendantOfView:controller.trigger]) return nil;
    return hit;
}
@end

%group PasteTips
%hook DRPasteAnnouncer
- (void)announcePaste:(id)paste { if (![CBDefaults() boolForKey:@"enabled"] || ![CBDefaults() boolForKey:@"suppressTips"]) %orig; }
- (void)announceDeniedPaste { if (![CBDefaults() boolForKey:@"enabled"] || ![CBDefaults() boolForKey:@"suppressTips"]) %orig; }
%end
%end

%ctor {
    @autoreleasepool {
        NSString *process = NSProcessInfo.processInfo.processName;
        if (NSClassFromString(@"DRPasteAnnouncer")) { %init(PasteTips); }
        if ([process isEqualToString:@"druid"]) return;
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
                controller = [CBController new];
                UIWindowScene *scene = nil;
                for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) if ([candidate isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)candidate; break; }
                controller.overlay = scene ? [[CBWindow alloc] initWithWindowScene:scene] : [[CBWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
                controller.overlay.frame = UIScreen.mainScreen.bounds;
                controller.overlay.windowLevel = 10000000;
                controller.overlay.rootViewController = controller;
                controller.overlay.hidden = NO;
                [controller reloadPreferences];
                int token;
                notify_register_dispatch("com.apple.pasteboard.notify.changed", &token, dispatch_get_main_queue(), ^(int t) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC/10), dispatch_get_main_queue(), ^{ [controller capture]; });
                });
                notify_register_dispatch(CBShow, &token, dispatch_get_main_queue(), ^(int t) { [controller show]; });
                notify_register_dispatch(CBReload, &token, dispatch_get_main_queue(), ^(int t) { [controller reloadPreferences]; });
                notify_register_dispatch("com.apple.springboard.lockstate", &token, dispatch_get_main_queue(), ^(int t) { uint64_t state = 0; notify_get_state(t, &state); controller.locked = state != 0; [controller reloadPreferences]; });
                uint64_t state = 0; notify_get_state(token, &state); controller.locked = state != 0; [controller reloadPreferences];
            }];
        }
    }
}
