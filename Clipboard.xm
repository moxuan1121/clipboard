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
#import "ScreenOrientation.h"
#import "HistorySearch.h"

@interface NSObject (ClipboardSource)
- (NSString *)bundleIdentifier;
@end
@interface UIImage (ClipboardAppIcon)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(int)format scale:(CGFloat)scale;
@end

static UIImage *CBPlaceholderIcon(void) {
    static UIImage *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGFloat side = 37.5;
        CGRect bounds = CGRectMake(0, 0, side, side);
        image = [[[UIGraphicsImageRenderer alloc] initWithSize:bounds.size] imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [[UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:8.25] addClip];
            [UIColor.whiteColor setFill];
            UIRectFill(bounds);
            [[UIColor colorWithWhite:0.55 alpha:0.8] setStroke];
            UIBezierPath *grid = [UIBezierPath bezierPath];
            grid.lineWidth = 0.25;
            for (int i = 1; i < 6; i++) {
                CGFloat position = side*i/6;
                [grid moveToPoint:CGPointMake(position, 0)]; [grid addLineToPoint:CGPointMake(position, side)];
                [grid moveToPoint:CGPointMake(0, position)]; [grid addLineToPoint:CGPointMake(side, position)];
            }
            [grid moveToPoint:CGPointZero]; [grid addLineToPoint:CGPointMake(side, side)];
            [grid moveToPoint:CGPointMake(side, 0)]; [grid addLineToPoint:CGPointMake(0, side)];
            for (NSNumber *fraction in @[@0.9, @0.55, @0.4]) {
                CGFloat inset = side*(1-fraction.doubleValue)/2;
                [grid appendPath:[UIBezierPath bezierPathWithOvalInRect:CGRectInset(bounds, inset, inset)]];
            }
            [grid stroke];
        }];
    });
    return image;
}

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
- (UIInterfaceOrientation)activeInterfaceOrientation;
@end
@interface UIWindow (ClipboardOrientation)
- (void)_setWindowControlsStatusBarOrientation:(BOOL)controls;
- (void)_setRotatableViewOrientation:(UIInterfaceOrientation)orientation updateStatusBar:(BOOL)update duration:(NSTimeInterval)duration force:(BOOL)force;
@end
static UIInterfaceOrientation CBActiveOrientation(UIWindowScene *scene) {
    UIApplication *app = UIApplication.sharedApplication;
    UIInterfaceOrientation value = [app respondsToSelector:@selector(activeInterfaceOrientation)] ? [app activeInterfaceOrientation] : UIInterfaceOrientationUnknown;
    if (value < 1 || value > 4) value = scene.interfaceOrientation;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (value < 1 || value > 4) value = app.statusBarOrientation;
#pragma clang diagnostic pop
    return (UIInterfaceOrientation)CBScreenOrientation((int)value);
}
static id CBFrontApplication(void) {
    UIApplication *app = UIApplication.sharedApplication;
    return [app respondsToSelector:@selector(_accessibilityFrontMostApplication)] ? [app _accessibilityFrontMostApplication] : nil;
}
// The OS routes Cmd+V to the focused app, as in Kayoko's simulated paste.
// Build all four events before pressing a key so allocation failure cannot leave it held.
static void CBPaste(BOOL (^allowed)(void)) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.moxuan1121.clipboard.paste", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL); });
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
        __block BOOL permitted = NO;
        if (complete) dispatch_sync(dispatch_get_main_queue(), ^{ permitted = allowed(); });
        if (permitted) for (int i = 0; i < 4; i++) {
            if (i == 2) usleep(50000);
            IOHIDEventSetSenderID(events[i], 0x8000000817319371ULL);
            IOHIDEventSystemClientDispatchEvent(client, events[i]);
        }
        for (int i = 0; i < 4; i++) if (events[i]) CFRelease(events[i]);
        CFRelease(client);
    });
}

@interface CBWindow : UIWindow
- (void)updateOrientation:(UIInterfaceOrientation)orientation;
@end
@interface CBCell : UICollectionViewCell
@property(nonatomic,strong) UILabel *text;
@property(nonatomic,strong) UIImageView *picture;
@property(nonatomic,strong) UIImageView *sourceIcon;
@property(nonatomic,strong) UIButton *deleteButton;
@property(nonatomic,strong) UIButton *editButton;
@property(nonatomic,copy) void (^editAction)(NSNumber *);
@property(nonatomic) BOOL canEdit;
@property(nonatomic,copy) void (^deleteAction)(NSNumber *);
@property(nonatomic,copy) void (^revealAction)(CBCell *, BOOL);
@property(nonatomic) BOOL deleteRevealed;
@end
@implementation CBCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.clipsToBounds = YES;
        _text = [UILabel new];
        _text.font = [UIFont systemFontOfSize:13];
        _text.textColor = UIColor.labelColor;
        _text.numberOfLines = 2;
        _text.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:_text];
        _picture = [UIImageView new];
        _picture.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:_picture];
        _sourceIcon = [UIImageView new];
        _sourceIcon.contentMode = UIViewContentModeScaleAspectFit;
        _sourceIcon.layer.cornerRadius = 8.25;
        _sourceIcon.clipsToBounds = YES;
        [self.contentView addSubview:_sourceIcon];
        _deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _deleteButton.backgroundColor = UIColor.systemRedColor;
        _deleteButton.tintColor = UIColor.whiteColor;
        _deleteButton.layer.cornerRadius = 18;
        [_deleteButton setImage:[UIImage systemImageNamed:@"trash"] forState:UIControlStateNormal];
        _deleteButton.accessibilityLabel = @"删除此条记录";
        [_deleteButton addTarget:self action:@selector(deletePressed) forControlEvents:UIControlEventTouchUpInside];
        _deleteButton.hidden = YES;
        [self.contentView addSubview:_deleteButton];
        _editButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _editButton.backgroundColor = UIColor.systemBlueColor;
        _editButton.tintColor = UIColor.whiteColor;
        _editButton.layer.cornerRadius = 18;
        [_editButton setImage:[UIImage systemImageNamed:@"pencil"] forState:UIControlStateNormal];
        _editButton.accessibilityLabel = @"编辑文字";
        [_editButton addTarget:self action:@selector(editPressed) forControlEvents:UIControlEventTouchUpInside];
        _editButton.hidden = YES;
        [self.contentView addSubview:_editButton];
        for (NSNumber *direction in @[@(UISwipeGestureRecognizerDirectionLeft), @(UISwipeGestureRecognizerDirectionRight)]) {
            UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swiped:)];
            swipe.direction = direction.unsignedIntegerValue;
            [self addGestureRecognizer:swipe];
        }
        [self updateAppearance];
    }
    return self;
}
- (void)updateAppearance {
    BOOL dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    self.contentView.backgroundColor = dark ? [UIColor colorWithWhite:0.24 alpha:1] : [UIColor colorWithWhite:0.91 alpha:1];
    self.contentView.layer.borderWidth = 0.5;
    self.contentView.layer.borderColor = (dark ? [UIColor colorWithWhite:1 alpha:0.18] : [UIColor colorWithWhite:0 alpha:0.06]).CGColor;
    self.clipsToBounds = NO;
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = dark ? 0 : 0.025;
    self.layer.shadowRadius = 3;
    self.layer.shadowOffset = CGSizeMake(0, 2);
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (!previous || [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous]) [self updateAppearance];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect body = self.contentView.bounds;
    if (self.deleteRevealed) body.size.width = MAX(0, body.size.width-(self.canEdit ? 90 : 48));
    CGFloat side = MIN(37.5, MAX(0, MIN(body.size.height, body.size.width)));
    CGFloat gap = MAX(0, (body.size.height-side)/2);
    self.contentView.layer.cornerRadius = self.sourceIcon.layer.cornerRadius+gap;
    self.sourceIcon.frame = CGRectMake(gap, gap, side, side);
    body.origin.x += side+gap*2;
    body.size.width = MAX(0, body.size.width-side-gap*2);
    self.text.frame = CGRectInset(body, 12, 4);
    self.picture.frame = CGRectInset(body, 3, 3);
    self.deleteButton.frame = CGRectMake(self.contentView.bounds.size.width-42, (self.contentView.bounds.size.height-36)/2, 36, 36);
    self.editButton.frame = CGRectOffset(self.deleteButton.frame, -42, 0);
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.contentView.layer.cornerRadius].CGPath;
}
- (void)setDeleteRevealed:(BOOL)revealed {
    _deleteRevealed = revealed;
    self.deleteButton.hidden = !revealed;
    self.editButton.hidden = !revealed || !self.canEdit;
    self.isAccessibilityElement = !revealed;
    [self setNeedsLayout];
}
- (void)swiped:(UISwipeGestureRecognizer *)gesture {
    if (self.revealAction) self.revealAction(self, gesture.direction == UISwipeGestureRecognizerDirectionLeft);
}
- (void)deletePressed { if (self.deleteRevealed && self.deleteAction) self.deleteAction(@(self.tag)); }
- (void)editPressed { if (self.deleteRevealed && self.canEdit && self.editAction) self.editAction(@(self.tag)); }
- (void)prepareForReuse {
    [super prepareForReuse];
    self.deleteRevealed = NO;
    self.deleteAction = nil;
    self.editAction = nil;
    self.canEdit = NO;
    self.revealAction = nil;
    self.picture.image = nil;
    self.sourceIcon.image = nil;
    [self updateAppearance];
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.contentView.alpha = highlighted ? 0.65 : 1;
}
@end

@interface CBController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UISearchBarDelegate>
@property(nonatomic,strong) CBWindow *overlay;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) UIVisualEffectView *material;
@property(nonatomic,strong) UIView *materialTint;
@property(nonatomic,strong) UICollectionView *grid;
@property(nonatomic,strong) UIView *listContainer;
@property(nonatomic,weak) CBCell *revealedCell;
@property(nonatomic,strong) CBStore *store;
@property(nonatomic,strong) NSArray *items;
@property(nonatomic,strong) NSArray *allItems;
@property(nonatomic,strong) UISearchBar *searchBar;
@property(nonatomic,strong) NSCache *iconCache;
@property(nonatomic,weak) UIWindow *previousKeyWindow;
@property(nonatomic) BOOL searching;
@property(nonatomic) BOOL resetSearchOffset;
@property(nonatomic) CGRect keyboardFrame;
@property(nonatomic,strong) dispatch_queue_t queue;
@property(nonatomic) NSInteger lastChange;
@property(nonatomic) BOOL visible;
@property(nonatomic) BOOL locked;
@property(nonatomic,strong) id pasteApplication;
@property(nonatomic) NSUInteger presentation;
@property(nonatomic) BOOL selecting;
@property(nonatomic,strong) UINavigationController *textEditor;
- (void)reloadPreferences;
- (void)capture;
- (void)show;
- (void)hide;
- (void)hideAnimated:(BOOL)animated;
- (void)deleteItem:(NSNumber *)identifier;
- (void)editItem:(NSNumber *)identifier;
- (void)closeTextEditor;
- (void)revealDeleteForCell:(CBCell *)cell visible:(BOOL)visible;
@end
static CBController *controller;

@implementation CBController
- (BOOL)shouldAutorotate { return NO; }
- (BOOL)autorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return CBActiveOrientation(self.overlay.windowScene); }
- (void)revealDeleteForCell:(CBCell *)cell visible:(BOOL)visible {
    CBCell *previous = self.revealedCell;
    previous.deleteRevealed = NO;
    self.revealedCell = visible ? cell : nil;
    cell.deleteRevealed = visible;
    [UIView animateWithDuration:0.18 animations:^{ [previous layoutIfNeeded]; [cell layoutIfNeeded]; }];
}
- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.moxuan1121.clipboard.storage", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
        dispatch_async(_queue, ^{ self.store = [CBStore new]; });
        _lastChange = [UIPasteboard generalPasteboard].changeCount;
        _items = @[];
        _allItems = @[];
        _iconCache = [NSCache new];
        _iconCache.countLimit = 32;
    }
    return self;
}
- (void)loadView {
    UIControl *root = [[UIControl alloc] initWithFrame:UIScreen.mainScreen.bounds];
    [root addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
    self.view = root;
    self.panel = [UIView new];
    self.panel.backgroundColor = UIColor.clearColor;
    self.panel.layer.cornerRadius = 28;
    self.panel.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    self.panel.clipsToBounds = YES;
    [root addSubview:self.panel];
    self.material = [[UIVisualEffectView alloc] initWithEffect:nil];
    self.material.userInteractionEnabled = NO;
    self.material.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.panel addSubview:self.material];
    self.materialTint = [UIView new];
    self.materialTint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.material.contentView addSubview:self.materialTint];
    [self applyMaterial];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 8, 220, 42)];
    title.text = @"剪切板";
    title.font = [UIFont boldSystemFontOfSize:18];
    [self.panel addSubview:title];
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.sectionInset = UIEdgeInsetsMake(0, 12, 12, 12);
    layout.minimumInteritemSpacing = 10;
    layout.minimumLineSpacing = 10;
    layout.headerReferenceSize = CGSizeMake(1, 56);
    self.grid = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.grid.dataSource = self;
    self.grid.delegate = self;
    self.grid.backgroundColor = UIColor.clearColor;
    self.grid.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.grid registerClass:CBCell.class forCellWithReuseIdentifier:@"history"];
    [self.grid registerClass:UICollectionReusableView.class forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:@"search"];
    self.grid.alwaysBounceVertical = YES;
    self.searchBar = [UISearchBar new];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"搜索剪切板";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.returnKeyType = UIReturnKeyDone;
    self.searchBar.enablesReturnKeyAutomatically = NO;
    // Keep the editor outside collection-view reload/reuse so filtering cannot drop focus.
    self.listContainer = [UIView new];
    self.listContainer.clipsToBounds = YES;
    [self.listContainer addSubview:self.grid];
    [self.listContainer addSubview:self.searchBar];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [self.grid addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)]];
    [self.panel addSubview:self.listContainer];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat value = [CBDefaults() doubleForKey:@"height"];
    CGRect keyboard = [self.overlay convertRect:self.keyboardFrame fromCoordinateSpace:UIScreen.mainScreen.coordinateSpace];
    CGFloat bottom = self.searching && CGRectIntersectsRect(b, keyboard) ? MAX(0, CGRectGetMinY(keyboard)) : b.size.height;
    CGFloat height = MIN(MAX(isfinite(value) ? value : 420, 180), bottom);
    CGFloat width = b.size.width > b.size.height ? MIN(520, b.size.width) : b.size.width;
    self.panel.bounds = CGRectMake(0, 0, width, height);
    self.panel.center = CGPointMake(CGRectGetMidX(b), bottom-height/2);
    self.material.frame = self.panel.bounds;
    self.materialTint.frame = self.material.bounds;
    self.textEditor.view.frame = self.panel.bounds;
    self.listContainer.frame = CGRectMake(0, 50, width, MAX(height-50, 0));
    self.grid.frame = self.listContainer.bounds;
    [self scrollViewDidScroll:self.grid];
    self.grid.contentInset = UIEdgeInsetsMake(0, 0, self.searching ? 0 : self.view.safeAreaInsets.bottom, 0);
    [self.grid.collectionViewLayout invalidateLayout];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    self.searchBar.frame = CGRectMake(8, 4-scrollView.contentOffset.y, MAX(0, scrollView.bounds.size.width-16), 48);
}
- (UICollectionReusableView *)collectionView:(UICollectionView *)grid viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)path {
    UICollectionReusableView *header = [grid dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:@"search" forIndexPath:path];
    return header;
}
- (void)applySearch {
    [self revealDeleteForCell:nil visible:NO];
    self.items = CBFilterHistory(self.allItems, self.searchBar.text);
    [self.grid reloadData];
    if (self.resetSearchOffset) {
        self.resetSearchOffset = NO;
        [self.grid layoutIfNeeded];
        [self.grid setContentOffset:CGPointMake(0, 56) animated:NO];
    }
}
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text { [self applySearch]; }
- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)bar {
    if (!self.visible || self.locked) return NO;
    if (self.searching) return YES;
    self.searching = YES;
    for (UIWindow *window in self.overlay.windowScene.windows) if (window.isKeyWindow && window != self.overlay) { self.previousKeyWindow = window; break; }
    [self.overlay makeKeyWindow];
    return YES;
}
- (BOOL)searchBarShouldEndEditing:(UISearchBar *)bar { return !self.searching; }
- (void)endSearchEditing {
    self.searching = NO;
    [self.searchBar resignFirstResponder];
    self.keyboardFrame = CGRectZero;
    [self.previousKeyWindow makeKeyWindow];
    self.previousKeyWindow = nil;
    [self.view setNeedsLayout];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar { [self endSearchEditing]; }
- (void)keyboardChanged:(NSNotification *)notification {
    if (!self.visible || !self.searching) return;
    self.keyboardFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration animations:^{ [self.view setNeedsLayout]; [self.view layoutIfNeeded]; }];
}
- (CGSize)collectionView:(UICollectionView *)grid layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)path {
    return CGSizeMake(floor((grid.bounds.size.width-34)/2), 44.8);
}
- (void)applyMaterial {
    BOOL dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    self.material.effect = [UIBlurEffect effectWithStyle:dark ? UIBlurEffectStyleSystemThinMaterialDark : UIBlurEffectStyleSystemThinMaterialLight];
    self.materialTint.backgroundColor = [UIColor colorWithWhite:1 alpha:dark ? 0.06 : 0.34];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (!previous || [self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previous]) [self applyMaterial];
}
- (void)reloadPreferences {
    NSUserDefaults *d = CBDefaults();
    if (![d boolForKey:@"enabled"] || self.locked) [self hide];
    [self.view setNeedsLayout];
}
- (void)hide {
    [self hideAnimated:YES];
}
- (void)hideAnimated:(BOOL)animated {
    [self closeTextEditor];
    [self endSearchEditing];
    [self revealDeleteForCell:nil visible:NO];
    self.visible = NO;
    self.selecting = NO;
    self.pasteApplication = nil;
    NSUInteger token = ++self.presentation;
    void (^finish)(void) = ^{
        if (self.presentation != token) return;
        self.overlay.hidden = YES;
        self.items = @[];
        self.allItems = @[];
        [self.grid reloadData];
    };
    if (!animated || self.locked || ![CBDefaults() boolForKey:@"enabled"]) {
        [self.panel.layer removeAllAnimations];
        [self.view.layer removeAllAnimations];
        finish();
        return;
    }
    [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn animations:^{
        self.panel.transform = CGAffineTransformMakeTranslation(0, self.panel.bounds.size.height);
        self.view.backgroundColor = UIColor.clearColor;
    } completion:^(BOOL finished) { finish(); }];
}
- (void)show {
    if (self.visible || self.locked || ![CBDefaults() boolForKey:@"enabled"]) return;
    ++self.presentation;
    self.visible = YES;
    self.searchBar.text = @"";
    self.resetSearchOffset = YES;
    self.pasteApplication = CBFrontApplication();
    [self.overlay updateOrientation:CBActiveOrientation(self.overlay.windowScene)];
    self.overlay.hidden = NO;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [self.grid setContentOffset:CGPointMake(0, 56) animated:NO];
    self.panel.transform = CGAffineTransformMakeTranslation(0, self.panel.bounds.size.height);
    self.view.backgroundColor = UIColor.clearColor;
    [UIView animateWithDuration:0.16 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut animations:^{
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
        dispatch_async(dispatch_get_main_queue(), ^{ if (self.visible && self.presentation == token) { self.allItems = items ?: @[]; [self applySearch]; } });
    });
}
- (void)capture {
    if (![CBDefaults() boolForKey:@"enabled"]) return;
    UIPasteboard *pb = UIPasteboard.generalPasteboard;
    if (pb.changeCount == self.lastChange) return;
    self.lastChange = pb.changeCount;
    id application = CBFrontApplication();
    NSString *source = [application respondsToSelector:@selector(bundleIdentifier)] ? [[application bundleIdentifier] copy] : nil;
    if (![source isKindOfClass:NSString.class]) source = nil;
    NSString *text = pb.string;
    NSData *image = [pb dataForPasteboardType:@"public.png"] ?: [pb dataForPasteboardType:@"public.jpeg"];
    if (!image && pb.hasImages) image = UIImagePNGRepresentation(pb.image);
    if (!text.length && !image.length) return;
    NSInteger change = pb.changeCount;
    dispatch_async(self.queue, ^{
        if (!self.store) self.store = [CBStore new];
        if ([self.store saveText:text image:image source:source]) dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.locked && [CBDefaults() boolForKey:@"enabled"] && UIPasteboard.generalPasteboard.changeCount == change)
                AudioServicesPlaySystemSound(1519);
            if (self.visible) [self refresh];
        });
    });
}
- (NSInteger)collectionView:(UICollectionView *)grid numberOfItemsInSection:(NSInteger)section { return self.items.count; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)grid cellForItemAtIndexPath:(NSIndexPath *)path {
    CBCell *cell = [grid dequeueReusableCellWithReuseIdentifier:@"history" forIndexPath:path];
    NSDictionary *item = self.items[path.item];
    BOOL hasImage = [item[@"image"] boolValue];
    cell.tag = [item[@"id"] integerValue];
    if (self.revealedCell == cell) self.revealedCell = nil;
    cell.canEdit = !hasImage;
    cell.deleteRevealed = NO;
    __weak CBController *weakSelf = self;
    cell.deleteAction = ^(NSNumber *identifier) { [weakSelf deleteItem:identifier]; };
    cell.editAction = ^(NSNumber *identifier) { [weakSelf editItem:identifier]; };
    cell.revealAction = ^(CBCell *sender, BOOL visible) { [weakSelf revealDeleteForCell:sender visible:visible]; };
    cell.text.text = hasImage ? nil : item[@"text"];
    cell.text.hidden = hasImage;
    cell.picture.hidden = !hasImage;
    cell.picture.image = nil;
    NSString *source = item[@"source"];
    BOOL blankIcon = !source.length || [source isEqualToString:@"com.apple.springboard"];
    UIImage *icon = blankIcon ? nil : [self.iconCache objectForKey:source];
    if (!blankIcon && !icon && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        icon = [UIImage _applicationIconImageForBundleIdentifier:source format:1 scale:UIScreen.mainScreen.scale];
        if (icon) [self.iconCache setObject:icon forKey:source];
    }
    cell.sourceIcon.image = icon ?: CBPlaceholderIcon();
    cell.sourceIcon.backgroundColor = icon ? UIColor.clearColor : [UIColor colorWithWhite:0.97 alpha:1];
    cell.sourceIcon.layer.borderWidth = icon ? 0 : 0.5;
    cell.sourceIcon.layer.borderColor = [UIColor colorWithWhite:0.65 alpha:0.35].CGColor;
    [cell setNeedsLayout];
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
    CBCell *cell = (CBCell *)[grid cellForItemAtIndexPath:path];
    if (cell.deleteRevealed) { [self revealDeleteForCell:cell visible:NO]; return; }
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
                CBPaste(^BOOL {
                    if (self.locked || self.visible || self.presentation != hiddenToken ||
                        ![CBDefaults() boolForKey:@"enabled"] || UIPasteboard.generalPasteboard.changeCount != change) return NO;
                    return !application || [application isEqual:CBFrontApplication()];
                });
            });
        });
    });
}
- (void)longPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || !self.visible || self.selecting) return;
    NSIndexPath *path = [self.grid indexPathForItemAtPoint:[gesture locationInView:self.grid]];
    if (!path || path.item >= self.items.count) return;
    if (((CBCell *)[self.grid cellForItemAtIndexPath:path]).deleteRevealed) return;
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
        NSData *data = imageItem ? [self.store imageForID:item[@"id"]] : nil;
        UIImage *image = data.length ? [UIImage imageWithData:data] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.visible || self.locked || self.presentation != token) return;
            self.selecting = NO;
            if (imageItem && !image) return;
            AudioServicesPlaySystemSound(1519);
            [self hideAnimated:NO];
            if (imageItem) openImage(image, self.overlay.windowScene);
            else openText(item[@"text"]);
        });
    });
}
- (void)closeTextEditor {
    if (!self.textEditor) return;
    [self.textEditor.view endEditing:YES];
    [self.textEditor willMoveToParentViewController:nil];
    [self.textEditor.view removeFromSuperview];
    [self.textEditor removeFromParentViewController];
    self.textEditor = nil;
}
- (void)hideEditorKeyboard { [self.textEditor.view endEditing:YES]; }
- (void)editItem:(NSNumber *)identifier {
    if (!self.visible || self.locked || self.selecting || self.presentedViewController) return;
    NSDictionary *item = nil;
    for (NSDictionary *candidate in self.items) if ([candidate[@"id"] isEqual:identifier]) { item = candidate; break; }
    if (!item || [item[@"image"] boolValue]) return;
    [self endSearchEditing];
    [self searchBarShouldBeginEditing:self.searchBar];
    [self revealDeleteForCell:nil visible:NO];
    self.selecting = YES;
    NSUInteger token = self.presentation;
    UIViewController *editor = [UIViewController new];
    editor.title = @"编辑文字";
    editor.view.backgroundColor = UIColor.systemBackgroundColor;
    UITextView *text = [UITextView new];
    text.font = [UIFont systemFontOfSize:17];
    text.text = item[@"text"];
    text.translatesAutoresizingMaskIntoConstraints = NO;
    [editor.view addSubview:text];
    [NSLayoutConstraint activateConstraints:@[
        [text.topAnchor constraintEqualToAnchor:editor.view.safeAreaLayoutGuide.topAnchor constant:8],
        [text.leadingAnchor constraintEqualToAnchor:editor.view.safeAreaLayoutGuide.leadingAnchor constant:12],
        [text.trailingAnchor constraintEqualToAnchor:editor.view.safeAreaLayoutGuide.trailingAnchor constant:-12],
        [text.bottomAnchor constraintEqualToAnchor:editor.view.safeAreaLayoutGuide.bottomAnchor constant:-8]]];
    self.textEditor = [[UINavigationController alloc] initWithRootViewController:editor];
    __weak CBController *weakSelf = self;
    dispatch_block_t close = ^{
        CBController *host = weakSelf;
        if (!host || host.presentation != token) return;
        [host closeTextEditor];
        host.selecting = NO;
        [host endSearchEditing];
    };
    __weak UIViewController *weakEditor = editor;
    editor.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel primaryAction:[UIAction actionWithHandler:^(UIAction *action) { close(); }]];
    editor.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave primaryAction:[UIAction actionWithHandler:^(UIAction *action) {
        CBController *host = weakSelf;
        if (!host || !host.visible || host.locked || host.presentation != token) return;
        NSString *value = [text.text copy];
        if (!value.length) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"文字不能为空" message:@"如需移除此条记录，请使用删除按钮。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
            [weakEditor presentViewController:alert animated:YES completion:nil];
            return;
        }
        weakEditor.navigationItem.rightBarButtonItem.enabled = NO;
        weakEditor.navigationItem.leftBarButtonItem.enabled = NO;
        text.editable = NO;
        dispatch_async(host.queue, ^{
            BOOL saved = [host.store updateText:value forID:identifier];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!host.visible || host.presentation != token) return;
                if (saved) { AudioServicesPlaySystemSound(1519); [host refresh]; close(); }
                else {
                    text.editable = YES;
                    weakEditor.navigationItem.rightBarButtonItem.enabled = YES;
                    weakEditor.navigationItem.leftBarButtonItem.enabled = YES;
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存失败" message:@"记录未被修改，请稍后重试。" preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
                    [weakEditor presentViewController:alert animated:YES completion:nil];
                }
            });
        });
    }]];
    UIBarButtonItem *hideKeyboard = [[UIBarButtonItem alloc] initWithTitle:@"收起键盘" style:UIBarButtonItemStylePlain target:self action:@selector(hideEditorKeyboard)];
    editor.navigationItem.rightBarButtonItems = @[editor.navigationItem.rightBarButtonItem, hideKeyboard];
    [self addChildViewController:self.textEditor];
    self.textEditor.view.frame = self.panel.bounds;
    self.textEditor.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.panel addSubview:self.textEditor.view];
    [self.textEditor didMoveToParentViewController:self];
    [text becomeFirstResponder];
}
- (void)deleteItem:(NSNumber *)identifier {
    if (!self.visible || self.locked || self.selecting) return;
    self.selecting = YES;
    NSUInteger token = self.presentation;
    dispatch_async(self.queue, ^{
        BOOL deleted = [self.store deleteItem:identifier];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.visible || self.presentation != token) return;
            self.selecting = NO;
            if (deleted) { AudioServicesPlaySystemSound(1519); [self refresh]; }
            else {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除失败" message:@"记录未被删除，请稍后重试。" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    });
}
@end

// The root control only intercepts outside taps while the history is visible.
@implementation CBWindow
- (void)updateOrientation:(UIInterfaceOrientation)orientation {
    orientation = (UIInterfaceOrientation)CBScreenOrientation((int)orientation);
    [controller revealDeleteForCell:nil visible:NO];
    // RegionShot's window-only rotation: do not rotate the app or its status bar.
    if ([self respondsToSelector:@selector(_setWindowControlsStatusBarOrientation:)]) [self _setWindowControlsStatusBarOrientation:NO];
    if ([self respondsToSelector:@selector(_setRotatableViewOrientation:updateStatusBar:duration:force:)])
        [self _setRotatableViewOrientation:orientation updateStatusBar:NO duration:0 force:YES];
    [self.rootViewController.view setNeedsLayout];
    [self.rootViewController.view layoutIfNeeded];
}
- (BOOL)canBecomeKeyWindow { return controller.searching; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    CGRect keyboard = [self convertRect:controller.keyboardFrame fromCoordinateSpace:UIScreen.mainScreen.coordinateSpace];
    if (controller.searching && CGRectContainsPoint(keyboard, point)) return nil;
    return controller.visible ? [super hitTest:point withEvent:event] : nil;
}
@end

static BOOL CBHandleURL(id url) {
    if (!controller || ![CBDefaults() boolForKey:@"enabled"] || !CBIsHistoryURL(url)) return NO;
    if (NSThread.isMainThread) [controller show];
    else dispatch_async(dispatch_get_main_queue(), ^{ [controller show]; });
    return YES;
}
// RegionShot's URL entry points; this group is installed only in SpringBoard.
%group URLApplication
%hook UIApplication
- (BOOL)openURL:(NSURL *)url {
    if (CBHandleURL(url)) return YES;
    return %orig;
}
- (void)openURL:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL))completion {
    if (!CBHandleURL(url)) {
        %orig;
        return;
    }
    if (completion) completion(YES);
}
%end
%end
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

%group ScreenTarget
%hook SpringBoard
- (void)noteInterfaceOrientationChanged:(long long)orientation duration:(double)duration updateMirroredDisplays:(BOOL)update force:(BOOL)force logMessage:(id)message {
    %orig;
    if (orientation < 1 || orientation > 4) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (controller.visible) [controller.overlay updateOrientation:(UIInterfaceOrientation)orientation];
    });
}
%end
%end
%group ScreenFallback
%hook SpringBoard
- (void)_postActiveInterfaceOrientationChangedNotificationAnimated:(BOOL)animated {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (controller.visible) [controller.overlay updateOrientation:CBActiveOrientation(controller.overlay.windowScene)];
    });
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
            dispatch_async(dispatch_get_main_queue(), ^{
            // Match RegionShot: install after class loading, only inside SpringBoard.
            %init(URLApplication);
            Class springBoard = NSClassFromString(@"SpringBoard"), service = NSClassFromString(@"FBSSystemService");
            if (CBURLMethod(springBoard, @"noteInterfaceOrientationChanged:duration:updateMirroredDisplays:force:logMessage:", @[@"ql", @"d", @"Bc", @"Bc", @"@"])) {
                %init(ScreenTarget);
            } else if (CBURLMethod(springBoard, @"_postActiveInterfaceOrientationChangedNotificationAnimated:", @[@"Bc"])) {
                %init(ScreenFallback);
            }
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
            // Register the Darwin entry directly, not behind a one-shot launch notification.
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
            });
        }
    }
}
