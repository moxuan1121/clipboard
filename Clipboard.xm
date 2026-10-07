#import "Shared.h"
#import "Store.h"
#import <ImageIO/ImageIO.h>
#import <notify.h>
#import <AudioToolbox/AudioToolbox.h>
#import <mach/mach_time.h>
#import <unistd.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#include <string.h>
#import "URLRoute.h"

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
extern "C" {
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef);
extern IOHIDEventRef IOHIDEventCreateKeyboardEvent(CFAllocatorRef, uint64_t, uint32_t, uint32_t, boolean_t, uint32_t);
extern void IOHIDEventSetSenderID(IOHIDEventRef, uint64_t);
extern void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef, IOHIDEventRef);
}
@interface UIApplication (ClipboardHost)
- (id)_accessibilityFrontMostApplication;
@end
static id CBFrontApplication(void) {
    UIApplication *app = UIApplication.sharedApplication;
    return [app respondsToSelector:@selector(_accessibilityFrontMostApplication)] ? [app _accessibilityFrontMostApplication] : nil;
}
// The OS routes Cmd+V to the focused app, as in Kayoko's simulated paste.
// Build all four events before pressing a key so allocation failure cannot leave it held.
static void CBPaste(dispatch_queue_t queue) {
    dispatch_async(queue, ^{
        IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (!client) return;
        uint32_t usages[] = {0xE3, 0x19, 0x19, 0xE3};
        IOHIDEventRef events[4] = {NULL};
        BOOL complete = YES;
        for (int i = 0; i < 4; i++) {
            events[i] = IOHIDEventCreateKeyboardEvent(kCFAllocatorDefault, mach_absolute_time(), 7, usages[i], i < 2, 0);
            if (!events[i]) complete = NO;
        }
        if (complete) for (int i = 0; i < 4; i++) {
            if (i == 2) usleep(50000);
            IOHIDEventSetSenderID(events[i], 0x8000000817319371ULL);
            IOHIDEventSystemClientDispatchEvent(client, events[i]);
        }
        for (int i = 0; i < 4; i++) if (events[i]) CFRelease(events[i]);
        CFRelease(client);
    });
}

@interface CBWindow : UIWindow
@end
@interface CBCell : UICollectionViewCell
@property(nonatomic,strong) UILabel *text;
@property(nonatomic,strong) UIImageView *picture;
@end
@implementation CBCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.backgroundColor = UIColor.tertiarySystemBackgroundColor;
        self.contentView.layer.cornerRadius = 16;
        self.contentView.clipsToBounds = YES;
        _text = [UILabel new];
        _text.font = [UIFont systemFontOfSize:15];
        _text.numberOfLines = 0;
        [self.contentView addSubview:_text];
        _picture = [UIImageView new];
        _picture.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:_picture];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.text.frame = CGRectInset(self.contentView.bounds, 12, 10);
    self.picture.frame = self.contentView.bounds;
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.contentView.alpha = highlighted ? 0.65 : 1;
}
@end

@interface CBController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@property(nonatomic,strong) CBWindow *overlay;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UICollectionView *grid;
@property(nonatomic,strong) CBStore *store;
@property(nonatomic,strong) NSArray *items;
@property(nonatomic,strong) dispatch_queue_t queue;
@property(nonatomic) NSInteger lastChange;
@property(nonatomic) BOOL visible;
@property(nonatomic) BOOL locked;
@property(nonatomic,strong) id pasteApplication;
@property(nonatomic) NSUInteger presentation;
@property(nonatomic) BOOL selecting;
- (void)reloadPreferences;
- (void)capture;
- (void)show;
- (void)hide;
- (void)hideWithCompletion:(dispatch_block_t)completion;
@end
static CBController *controller;

@implementation CBController
- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.moxuan1121.clipboard.storage", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
        dispatch_async(_queue, ^{ self.store = [CBStore new]; });
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
    title.text = @"剪切板";
    title.font = [UIFont boldSystemFontOfSize:18];
    [self.panel addSubview:title];
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.sectionInset = UIEdgeInsetsMake(0, 12, 12, 12);
    layout.minimumInteritemSpacing = 10;
    layout.minimumLineSpacing = 10;
    self.grid = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.grid.dataSource = self;
    self.grid.delegate = self;
    self.grid.backgroundColor = UIColor.clearColor;
    [self.grid registerClass:CBCell.class forCellWithReuseIdentifier:@"history"];
    [self.grid addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)]];
    [self.panel addSubview:self.grid];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat value = [CBDefaults() doubleForKey:@"height"];
    CGFloat height = MIN(MAX(isfinite(value) ? value : 420, 180), b.size.height);
    CGFloat width = b.size.width > b.size.height ? MIN(520, b.size.width) : b.size.width;
    self.panel.bounds = CGRectMake(0, 0, width, height);
    self.panel.center = CGPointMake(CGRectGetMidX(b), b.size.height-height/2);
    self.grid.frame = CGRectMake(0, 50, width, MAX(height-50, 0));
    self.grid.contentInset = UIEdgeInsetsMake(0, 0, self.view.safeAreaInsets.bottom, 0);
    [self.grid.collectionViewLayout invalidateLayout];
}
- (CGSize)collectionView:(UICollectionView *)grid layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)path {
    return CGSizeMake(floor((grid.bounds.size.width-34)/2), 112);
}
- (void)reloadPreferences {
    NSUserDefaults *d = CBDefaults();
    if (![d boolForKey:@"enabled"] || self.locked) [self hide];
    [self.view setNeedsLayout];
}
- (void)hide {
    [self hideWithCompletion:nil];
}
- (void)hideWithCompletion:(dispatch_block_t)completion {
    self.visible = NO;
    self.selecting = NO;
    self.pasteApplication = nil;
    NSUInteger token = ++self.presentation;
    void (^finish)(void) = ^{
        if (self.presentation != token) return;
        self.overlay.hidden = YES;
        self.items = @[];
        [self.grid reloadData];
        if (completion && !self.locked && [CBDefaults() boolForKey:@"enabled"]) completion();
    };
    if (self.locked || ![CBDefaults() boolForKey:@"enabled"]) { finish(); return; }
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        self.panel.transform = CGAffineTransformMakeTranslation(0, self.panel.bounds.size.height);
        self.view.backgroundColor = UIColor.clearColor;
    } completion:^(BOOL finished) { finish(); }];
}
- (void)show {
    if (self.visible || self.locked || ![CBDefaults() boolForKey:@"enabled"]) return;
    ++self.presentation;
    self.visible = YES;
    self.pasteApplication = CBFrontApplication();
    self.overlay.hidden = NO;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    self.panel.transform = CGAffineTransformMakeTranslation(0, self.panel.bounds.size.height);
    self.view.backgroundColor = UIColor.clearColor;
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut animations:^{
        self.panel.transform = CGAffineTransformIdentity;
        self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.12];
    } completion:nil];
    [self refresh];
}
- (void)refresh {
    NSUInteger token = self.presentation;
    dispatch_async(self.queue, ^{
        if (!self.store) self.store = [CBStore new];
        NSArray *items = [self.store history];
        dispatch_async(dispatch_get_main_queue(), ^{ if (self.visible && self.presentation == token) { self.items = items ?: @[]; [self.grid reloadData]; } });
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
        if (!self.store) self.store = [CBStore new];
        if ([self.store saveText:text image:image]) dispatch_async(dispatch_get_main_queue(), ^{ if (self.visible) [self refresh]; });
    });
}
- (NSInteger)collectionView:(UICollectionView *)grid numberOfItemsInSection:(NSInteger)section { return self.items.count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)grid cellForItemAtIndexPath:(NSIndexPath *)path {
    CBCell *cell = [grid dequeueReusableCellWithReuseIdentifier:@"history" forIndexPath:path];
    NSDictionary *item = self.items[path.item];
    BOOL hasImage = [item[@"image"] boolValue];
    cell.tag = [item[@"id"] integerValue];
    cell.text.text = hasImage ? nil : item[@"text"];
    cell.text.hidden = hasImage;
    cell.picture.hidden = !hasImage;
    cell.picture.image = nil;
    cell.accessibilityLabel = hasImage ? @"图片" : item[@"text"];
    cell.isAccessibilityElement = YES;
    cell.accessibilityTraits = UIAccessibilityTraitButton;
    if (hasImage) {
        NSNumber *identifier = item[@"id"];
        NSUInteger token = self.presentation;
        __weak CBCell *weakCell = cell;
        dispatch_async(self.queue, ^{
            NSData *data = [self.store imageForID:identifier];
            CGImageSourceRef source = data ? CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL) : NULL;
            CGImageRef image = source ? CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)@{(id)kCGImageSourceCreateThumbnailFromImageAlways:@YES, (id)kCGImageSourceCreateThumbnailWithTransform:@YES, (id)kCGImageSourceThumbnailMaxPixelSize:@480}) : NULL;
            UIImage *thumbnail = image ? [UIImage imageWithCGImage:image] : nil;
            if (image) CGImageRelease(image);
            if (source) CFRelease(source);
            dispatch_async(dispatch_get_main_queue(), ^{ if (self.visible && self.presentation == token && weakCell.tag == identifier.integerValue) weakCell.picture.image = thumbnail; });
        });
    }
    return cell;
}
- (void)collectionView:(UICollectionView *)grid didSelectItemAtIndexPath:(NSIndexPath *)path {
    [grid deselectItemAtIndexPath:path animated:NO];
    if (self.selecting || path.item >= self.items.count) return;
    self.selecting = YES;
    NSUInteger token = self.presentation;
    NSDictionary *item = self.items[path.item];
    dispatch_async(self.queue, ^{
        NSData *image = [item[@"image"] boolValue] ? [self.store imageForID:item[@"id"]] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.visible || self.locked || self.presentation != token) return;
            self.selecting = NO;
            if ([item[@"image"] boolValue] && !image.length) return;
            if (image) {
                CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)image, NULL);
                NSString *type = source ? (__bridge NSString *)CGImageSourceGetType(source) : @"public.png";
                [[UIPasteboard generalPasteboard] setData:image forPasteboardType:type ?: @"public.png"];
                if (source) CFRelease(source);
            } else [UIPasteboard generalPasteboard].string = item[@"text"];
            self.lastChange = UIPasteboard.generalPasteboard.changeCount;
            NSInteger change = self.lastChange;
            id application = self.pasteApplication;
            [self hide];
            NSUInteger hiddenToken = self.presentation;
            AudioServicesPlaySystemSound(1519);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC/5), dispatch_get_main_queue(), ^{
                if (self.locked || self.visible || self.presentation != hiddenToken ||
                    ![CBDefaults() boolForKey:@"enabled"] || UIPasteboard.generalPasteboard.changeCount != change) return;
                if (application && ![application isEqual:CBFrontApplication()]) return;
                CBPaste(self.queue);
            });
        });
    });
}
- (void)longPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || !self.visible || self.selecting) return;
    NSIndexPath *path = [self.grid indexPathForItemAtPoint:[gesture locationInView:self.grid]];
    if (!path || path.item >= self.items.count) return;
    NSDictionary *item = self.items[path.item];
    BOOL imageItem = [item[@"image"] boolValue];
    void (*openText)(NSString *) = (void (*)(NSString *))dlsym(RTLD_DEFAULT, "RSKAOpenTokens");
    void (*openImage)(UIImage *, UIWindowScene *) = (void (*)(UIImage *, UIWindowScene *))dlsym(RTLD_DEFAULT, "RSShowFloatingImage");
    if ((imageItem && !openImage) || (!imageItem && !openText)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"需要 RegionShot" message:@"请先安装或更新支持分词和图片浮窗接口的 RegionShot。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    self.selecting = YES;
    NSUInteger token = self.presentation;
    dispatch_async(self.queue, ^{
        UIImage *image = imageItem ? [UIImage imageWithData:[self.store imageForID:item[@"id"]]] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.visible || self.locked || self.presentation != token) return;
            self.selecting = NO;
            if (imageItem && !image) return;
            AudioServicesPlaySystemSound(1519);
            [self hideWithCompletion:^{
                if (imageItem) openImage(image, self.overlay.windowScene);
                else openText(item[@"text"]);
            }];
        });
    });
}
@end

// The root control only intercepts outside taps while the history is visible.
@implementation CBWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return controller.visible ? [super hitTest:point withEvent:event] : nil;
}
@end

static BOOL CBHandleURL(id url) {
    if (!controller || ![CBDefaults() boolForKey:@"enabled"] || !CBIsHistoryURL(url)) return NO;
    notify_post(CBShow);
    return YES;
}
// Same system URL entry points used by RegionShot; no UIApplication/app injection.
%group URLShort
%hook SpringBoard
- (void)applicationOpenURL:(id)url {
    if (!CBHandleURL(url)) {
        %orig;
    }
}
%end
%end
%group URLExternal
%hook SpringBoard
- (void)applicationOpenURL:(id)url withApplication:(id)application sender:(id)sender publicURLsOnly:(BOOL)publicOnly animating:(BOOL)animating needsConfirm:(BOOL)confirm options:(id)options windowContext:(id)context {
    if (!CBHandleURL(url)) {
        %orig;
    }
}
%end
%end
%group URLPort
%hook FBSSystemService
- (void)openURL:(id)url application:(id)application options:(id)options clientPort:(unsigned int)port withResult:(void (^)(NSError *))result {
    if (!CBHandleURL(url)) {
        %orig;
        return;
    }
    if (result) result(nil);
}
%end
%end
%group URLProcess
%hook FBSSystemService
- (void)openURL:(id)url application:(id)application options:(id)options clientProcess:(id)process withResult:(void (^)(NSError *))result {
    if (!CBHandleURL(url)) {
        %orig;
        return;
    }
    if (result) result(nil);
}
%end
%end
static BOOL CBURLMethod(Class cls, NSString *name, NSArray<NSString *> *types) {
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(name));
    if (!method || method_getNumberOfArguments(method) != types.count+2) return NO;
    char type[128] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (type[0] != 'v') return NO;
    for (NSUInteger i = 0; i < types.count; i++) {
        method_getArgumentType(method, (unsigned int)i+2, type, sizeof(type));
        if (!type[0] || !strchr(types[i].UTF8String, type[0])) return NO;
    }
    return YES;
}

%group PasteTips
%hook DRPasteAnnouncer
- (void)announcePaste:(id)paste {
    if (![CBDefaults() boolForKey:@"enabled"] || ![CBDefaults() boolForKey:@"suppressTips"]) {
        %orig;
    }
}
- (void)announceDeniedPaste {
    if (![CBDefaults() boolForKey:@"enabled"] || ![CBDefaults() boolForKey:@"suppressTips"]) {
        %orig;
    }
}
%end
%end

%ctor {
    @autoreleasepool {
        NSString *process = NSProcessInfo.processInfo.processName;
        if (NSClassFromString(@"DRPasteAnnouncer")) {
            %init(PasteTips);
        }
        if ([process isEqualToString:@"druid"]) return;
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            Class springBoard = NSClassFromString(@"SpringBoard"), service = NSClassFromString(@"FBSSystemService");
            if (CBURLMethod(springBoard, @"applicationOpenURL:", @[@"@"])) {
                %init(URLShort);
            }
            if (CBURLMethod(springBoard, @"applicationOpenURL:withApplication:sender:publicURLsOnly:animating:needsConfirm:options:windowContext:", @[@"@", @"@", @"@", @"Bc", @"Bc", @"Bc", @"@", @"@"])) {
                %init(URLExternal);
            }
            if (CBURLMethod(service, @"openURL:application:options:clientPort:withResult:", @[@"@", @"@", @"@", @"I", @"@"])) {
                %init(URLPort);
            }
            if (CBURLMethod(service, @"openURL:application:options:clientProcess:withResult:", @[@"@", @"@", @"@", @"@", @"@"])) {
                %init(URLProcess);
            }
            [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
                controller = [CBController new];
                UIWindowScene *scene = nil;
                for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) if ([candidate isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)candidate; break; }
                controller.overlay = scene ? [[CBWindow alloc] initWithWindowScene:scene] : [[CBWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
                controller.overlay.frame = UIScreen.mainScreen.bounds;
                controller.overlay.windowLevel = 10000000;
                controller.overlay.rootViewController = controller;
                controller.overlay.hidden = YES;
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
