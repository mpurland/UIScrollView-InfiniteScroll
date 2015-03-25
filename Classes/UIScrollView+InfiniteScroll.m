//
//  UIScrollView+InfiniteScroll.m
//
//  UIScrollView infinite scroll category
//
//  Created by Andrej Mihajlov on 9/4/13.
//  Copyright (c) 2013-2015 Andrej Mihajlov. All rights reserved.
//

#import "UIScrollView+InfiniteScroll.h"
#import <objc/runtime.h>

#define TRACE_ENABLED 0

#if TRACE_ENABLED
#   define TRACE(_format, ...) NSLog(_format, ##__VA_ARGS__)
#else
#   define TRACE(_format, ...)
#endif

static void PBSwizzleMethod(Class c, SEL original, SEL alternate) {
    Method origMethod = class_getInstanceMethod(c, original);
    Method newMethod = class_getInstanceMethod(c, alternate);
    
    if(class_addMethod(c, original, method_getImplementation(newMethod), method_getTypeEncoding(newMethod))) {
        class_replaceMethod(c, alternate, method_getImplementation(origMethod), method_getTypeEncoding(origMethod));
    } else {
        method_exchangeImplementations(origMethod, newMethod);
    }
}

// Animation duration used for setContentOffset:
static const NSTimeInterval kPBInfiniteScrollAnimationDuration = 0.35;

// Keys for values in associated dictionary
static const void* kPBInfiniteScrollHandlerTopKey = &kPBInfiniteScrollHandlerTopKey;
static const void* kPBInfiniteScrollHandlerBottomKey = &kPBInfiniteScrollHandlerBottomKey;
static const void* kPBInfiniteScrollIndicatorTopViewKey = &kPBInfiniteScrollIndicatorTopViewKey;
static const void* kPBInfiniteScrollIndicatorBottomViewKey = &kPBInfiniteScrollIndicatorBottomViewKey;
static const void* kPBInfiniteScrollIndicatorStyleTopKey = &kPBInfiniteScrollIndicatorStyleTopKey;
static const void* kPBInfiniteScrollIndicatorStyleBottomKey = &kPBInfiniteScrollIndicatorStyleBottomKey;
static const void* kPBInfiniteScrollStateKey = &kPBInfiniteScrollStateKey;
static const void* kPBInfiniteScrollInitTopKey = &kPBInfiniteScrollInitTopKey;
static const void* kPBInfiniteScrollInitBottomKey = &kPBInfiniteScrollInitBottomKey;
static const void* kPBInfiniteScrollExtraBottomInsetKey = &kPBInfiniteScrollExtraBottomInsetKey;
static const void* kPBInfiniteScrollIndicatorMarginKey = &kPBInfiniteScrollIndicatorMarginKey;
static const void* kPBInfiniteScrollAnimatedKey = &kPBInfiniteScrollAnimatedKey;

// Infinite scroll states
typedef NS_ENUM(NSInteger, PBInfiniteScrollState) {
    PBInfiniteScrollStateNone,
    PBInfiniteScrollStateLoading
};

// Private category on UIScrollView to define dynamic properties
@interface UIScrollView ()

// Infinite scroll handler block
@property (copy, nonatomic, setter=pb_setInfiniteScrollHandlerTop:, getter=pb_infiniteScrollHandlerTop)
void(^pb_infiniteScrollHandlerTop)(id scrollView);

@property (copy, nonatomic, setter=pb_setInfiniteScrollHandlerBottom:, getter=pb_infiniteScrollHandlerBottom)
void(^pb_infiniteScrollHandlerBottom)(id scrollView);

// Infinite scroll state
@property (nonatomic, setter=pb_setInfiniteScrollState:, getter=pb_infiniteScrollState)
PBInfiniteScrollState pb_infiniteScrollState;

// A flag that indicates whether scroll is initialized
@property (nonatomic, setter=pb_setInfiniteScrollTopInitialized:, getter=pb_infiniteScrollTopInitialized)
BOOL pb_infiniteScrollTopInitialized;
@property (nonatomic, setter=pb_setInfiniteScrollBottomInitialized:, getter=pb_infiniteScrollBottomInitialized)
BOOL pb_infiniteScrollBottomInitialized;

@property (nonatomic, setter=pb_setInfiniteScrollAnimated:, getter=pb_infiniteScrollAnimated)
BOOL pb_infiniteScrollAnimated;

// Extra padding to push indicator view below view bounds.
// Used in case when content size is smaller than view bounds
@property (nonatomic, setter=pb_setInfiniteScrollExtraBottomInset:, getter=pb_infiniteScrollExtraBottomInset)
CGFloat pb_infiniteScrollExtraBottomInset;

@end

@implementation UIScrollView (InfiniteScroll)

#pragma mark - Public methods

- (void)addInfiniteScrollTopWithHandler:(void(^)(id scrollView))handler {
    [self addInfiniteScrollTopWithHandler:handler animated:YES];
}

- (void)addInfiniteScrollTopWithHandler:(void(^)(id scrollView))handler animated:(BOOL)animated {
    // Save handler block
    self.pb_infiniteScrollHandlerTop = handler;
    
    // Double initialization only replaces handler block
    // Do not continue if already initialized
    if(self.pb_infiniteScrollTopInitialized) {
        return;
    }
    
    self.pb_infiniteScrollAnimated = animated;
    // Add pan guesture handler
    [self.panGestureRecognizer addTarget:self action:@selector(pb_handlePanGestureTop:)];
    
    // Mark infiniteScroll initialized
    self.pb_infiniteScrollTopInitialized = YES;
}

- (void)addInfiniteScrollBottomWithHandler:(void(^)(id scrollView))handler {
    [self addInfiniteScrollBottomWithHandler:handler animated:YES];
}

- (void)addInfiniteScrollBottomWithHandler:(void(^)(id scrollView))handler animated:(BOOL)animated {
    // Save handler block
    self.pb_infiniteScrollHandlerBottom = handler;
    
    // Double initialization only replaces handler block
    // Do not continue if already initialized
    if(self.pb_infiniteScrollBottomInitialized) {
        return;
    }
    
    self.pb_infiniteScrollAnimated = animated;
    
    // Add pan guesture handler
    [self.panGestureRecognizer addTarget:self action:@selector(pb_handlePanGestureBottom:)];
    
    // Mark infiniteScroll initialized
    self.pb_infiniteScrollBottomInitialized = YES;
}

- (void)removeInfiniteScrollTop {
    // Ignore multiple calls to remove infinite scroll
    if(!self.pb_infiniteScrollTopInitialized) {
        return;
    }
    
    // Remove pan gesture handler
    [self.panGestureRecognizer removeTarget:self action:@selector(pb_handlePanGestureTop:)];
    
    // Destroy infinite scroll indicator
    [self.infiniteScrollIndicatorTopView removeFromSuperview];
    self.infiniteScrollIndicatorTopView = nil;
    
    // Mark infinite scroll as uninitialized
    self.pb_infiniteScrollTopInitialized = NO;
}

- (void)removeInfiniteScrollBottom {
    // Ignore multiple calls to remove infinite scroll
    if(!self.pb_infiniteScrollBottomInitialized) {
        return;
    }
    
    // Remove pan gesture handler
    [self.panGestureRecognizer removeTarget:self action:@selector(pb_handlePanGestureBottom:)];
    
    // Destroy infinite scroll indicator
    [self.infiniteScrollIndicatorBottomView removeFromSuperview];
    self.infiniteScrollIndicatorBottomView = nil;
    
    // Mark infinite scroll as uninitialized
    self.pb_infiniteScrollBottomInitialized = NO;
}

- (void)finishInfiniteScrollTop {
    [self finishInfiniteScrollTopWithCompletion:nil];
}

- (void)finishInfiniteScrollBottom {
    [self finishInfiniteScrollBottomWithCompletion:nil];
}

- (void)finishInfiniteScrollTopWithCompletion:(void(^)(id scrollView))handler {
    if(self.pb_infiniteScrollState == PBInfiniteScrollStateLoading) {
        [self pb_stopAnimatingInfiniteScrollWithCompletion:handler top:YES];
    }
}

- (void)finishInfiniteScrollBottomWithCompletion:(void(^)(id scrollView))handler {
    if(self.pb_infiniteScrollState == PBInfiniteScrollStateLoading) {
        [self pb_stopAnimatingInfiniteScrollWithCompletion:handler top:NO];
    }
}

- (void)setInfiniteScrollIndicatorTopStyle:(UIActivityIndicatorViewStyle)infiniteScrollIndicatorStyle {
    objc_setAssociatedObject(self, kPBInfiniteScrollIndicatorStyleTopKey, @(infiniteScrollIndicatorStyle), OBJC_ASSOCIATION_ASSIGN);
    id activityIndicatorView = self.infiniteScrollIndicatorTopView;
    if([activityIndicatorView isKindOfClass:[UIActivityIndicatorView class]]) {
        [activityIndicatorView setActivityIndicatorViewStyle:infiniteScrollIndicatorStyle];
    }
}

- (UIActivityIndicatorViewStyle)infiniteScrollIndicatorTopStyle {
    NSNumber* indicatorStyle = objc_getAssociatedObject(self, kPBInfiniteScrollIndicatorStyleTopKey);
    if(indicatorStyle) {
        return indicatorStyle.integerValue;
    }
    return UIActivityIndicatorViewStyleGray;
}

- (void)setInfiniteScrollIndicatorBottomStyle:(UIActivityIndicatorViewStyle)infiniteScrollIndicatorStyle {
    objc_setAssociatedObject(self, kPBInfiniteScrollIndicatorStyleBottomKey, @(infiniteScrollIndicatorStyle), OBJC_ASSOCIATION_ASSIGN);
    id activityIndicatorView = self.infiniteScrollIndicatorBottomView;
    if([activityIndicatorView isKindOfClass:[UIActivityIndicatorView class]]) {
        [activityIndicatorView setActivityIndicatorViewStyle:infiniteScrollIndicatorStyle];
    }
}

- (UIActivityIndicatorViewStyle)infiniteScrollIndicatorBottomStyle {
    NSNumber* indicatorStyle = objc_getAssociatedObject(self, kPBInfiniteScrollIndicatorStyleBottomKey);
    if(indicatorStyle) {
        return indicatorStyle.integerValue;
    }
    return UIActivityIndicatorViewStyleGray;
}

- (void)setInfiniteScrollIndicatorTopView:(UIView*)indicatorView {
    // make sure indicator is initially hidden
    indicatorView.hidden = YES;
    
    objc_setAssociatedObject(self, kPBInfiniteScrollIndicatorTopViewKey, indicatorView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UIView*)infiniteScrollIndicatorTopView {
    return objc_getAssociatedObject(self, kPBInfiniteScrollIndicatorTopViewKey);
}

- (void)setInfiniteScrollIndicatorBottomView:(UIView*)indicatorView {
    // make sure indicator is initially hidden
    indicatorView.hidden = YES;
    
    objc_setAssociatedObject(self, kPBInfiniteScrollIndicatorBottomViewKey, indicatorView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UIView*)infiniteScrollIndicatorBottomView {
    return objc_getAssociatedObject(self, kPBInfiniteScrollIndicatorBottomViewKey);
}

- (void)setInfiniteScrollIndicatorMargin:(CGFloat)infiniteScrollIndicatorMargin {
    objc_setAssociatedObject(self, kPBInfiniteScrollIndicatorMarginKey, @(infiniteScrollIndicatorMargin), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (CGFloat)infiniteScrollIndicatorMargin {
    NSNumber* margin = objc_getAssociatedObject(self, kPBInfiniteScrollIndicatorMarginKey);
    if(margin) {
        return margin.floatValue;
    }
    // Default row height minus activity indicator height
    return UIScrollViewInfiniteScrollDefaultScrollIndicatorMargin;
}

#pragma mark - Private dynamic properties

- (PBInfiniteScrollState)pb_infiniteScrollState {
    NSNumber* state = objc_getAssociatedObject(self, kPBInfiniteScrollStateKey);
    return [state integerValue];
}

- (void)pb_setInfiniteScrollState:(PBInfiniteScrollState)state {
    objc_setAssociatedObject(self, kPBInfiniteScrollStateKey, @(state), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    TRACE(@"pb_setInfiniteScrollState = %ld", (long)state);
}

- (void)pb_setInfiniteScrollHandlerTop:(void(^)(id scrollView))handler {
    objc_setAssociatedObject(self, kPBInfiniteScrollHandlerTopKey, handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void(^)(id scrollView))pb_infiniteScrollHandlerTop {
    return objc_getAssociatedObject(self, kPBInfiniteScrollHandlerTopKey);
}

- (void)pb_setInfiniteScrollHandlerBottom:(void(^)(id scrollView))handler {
    objc_setAssociatedObject(self, kPBInfiniteScrollHandlerBottomKey, handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (void(^)(id scrollView))pb_infiniteScrollHandlerBottom {
    return objc_getAssociatedObject(self, kPBInfiniteScrollHandlerBottomKey);
}

- (void)pb_setInfiniteScrollExtraBottomInset:(CGFloat)height {
    objc_setAssociatedObject(self, kPBInfiniteScrollExtraBottomInsetKey, @(height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (CGFloat)pb_infiniteScrollExtraBottomInset {
    return [objc_getAssociatedObject(self, kPBInfiniteScrollExtraBottomInsetKey) doubleValue];
}

- (BOOL)pb_infiniteScrollTopInitialized {
    NSNumber* flag = objc_getAssociatedObject(self, kPBInfiniteScrollInitTopKey);
    
    return [flag boolValue];
}

- (void)pb_setInfiniteScrollTopInitialized:(BOOL)flag {
    objc_setAssociatedObject(self, kPBInfiniteScrollInitTopKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)pb_infiniteScrollBottomInitialized {
    NSNumber* flag = objc_getAssociatedObject(self, kPBInfiniteScrollInitBottomKey);
    
    return [flag boolValue];
}

- (void)pb_setInfiniteScrollBottomInitialized:(BOOL)flag {
    objc_setAssociatedObject(self, kPBInfiniteScrollInitBottomKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (BOOL)pb_infiniteScrollAnimated {
    NSNumber* flag = objc_getAssociatedObject(self, kPBInfiniteScrollAnimatedKey);
    
    return [flag boolValue];
}

- (void)pb_setInfiniteScrollAnimated:(BOOL)flag {
    objc_setAssociatedObject(self, kPBInfiniteScrollAnimatedKey, @(flag), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - Private methods

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        PBSwizzleMethod(self, @selector(setContentOffset:), @selector(pb_setContentOffset:));
        PBSwizzleMethod(self, @selector(setContentSize:), @selector(pb_setContentSize:));
    });
}

- (void)pb_handlePanGestureTop:(UITapGestureRecognizer*)gestureRecognizer {
    if(gestureRecognizer.state == UIGestureRecognizerStateEnded && self.pb_infiniteScrollTopInitialized) {
        [self pb_scrollToInfiniteIndicatorIfNeeded:YES];
    }
}

- (void)pb_handlePanGestureBottom:(UITapGestureRecognizer*)gestureRecognizer {
    if(gestureRecognizer.state == UIGestureRecognizerStateEnded && self.pb_infiniteScrollBottomInitialized) {
        [self pb_scrollToInfiniteIndicatorIfNeeded:NO];
    }
}

- (void)pb_setContentOffset:(CGPoint)contentOffset {
    [self pb_setContentOffset:contentOffset];
    
    if(self.pb_infiniteScrollTopInitialized || self.pb_infiniteScrollBottomInitialized) {
        [self pb_scrollViewDidScroll:contentOffset];
    }
}

- (void)pb_setContentSize:(CGSize)contentSize {
    
//    if (!CGSizeEqualToSize(self.contentSize, CGSizeZero)) {
//        if (contentSize.height > self.contentSize.height) {
//            CGPoint offset = self.contentOffset;
//            offset.y += (contentSize.height - self.contentSize.height);
//            self.contentOffset = offset;
//        }
//    }
    
    [self pb_setContentSize:contentSize];
    
    if(self.pb_infiniteScrollTopInitialized) {
        [self pb_positionInfiniteScrollIndicatorWithContentSize:contentSize top:YES];
    }
    if (self.pb_infiniteScrollBottomInitialized) {
        [self pb_positionInfiniteScrollIndicatorWithContentSize:contentSize top:NO];
    }
}

- (CGFloat)pb_adjustedHeightFromContentSize:(CGSize)contentSize {
    CGFloat remainingHeight = self.bounds.size.height - self.contentInset.top - self.contentInset.bottom;
    if(contentSize.height < remainingHeight) {
        return remainingHeight;
    }
    return contentSize.height;
}

- (void)pb_callInfiniteScrollHandlerTop {
    if(self.pb_infiniteScrollHandlerTop) {
        self.pb_infiniteScrollHandlerTop(self);
    }
    TRACE(@"Call handler top.");
}

- (void)pb_callInfiniteScrollHandlerBottom {
    if(self.pb_infiniteScrollHandlerBottom) {
        self.pb_infiniteScrollHandlerBottom(self);
    }
    TRACE(@"Call handler bottom.");
}

- (UIView*)pb_getOrCreateActivityIndicatorView:(BOOL)top {
    UIView* activityIndicator = top ? self.infiniteScrollIndicatorTopView : self.infiniteScrollIndicatorBottomView;
    
    if (!activityIndicator) {
        if (top) {
            activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:self.infiniteScrollIndicatorTopStyle];
            self.infiniteScrollIndicatorTopView = activityIndicator;
        }
        else {
            activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:self.infiniteScrollIndicatorBottomStyle];
            self.infiniteScrollIndicatorBottomView = activityIndicator;
        }
    }
    
    // Add activity indicator into scroll view if needed
    if(activityIndicator.superview != self) {
        [self addSubview:activityIndicator];
    }
    
    return activityIndicator;
}

- (CGFloat)infiniteScrollIndicatorRowHeight:(BOOL)top {
    return [self pb_infiniteIndicatorRowHeight:top];
}

- (CGFloat)pb_infiniteIndicatorRowHeight:(BOOL)top {
    UIView* activityIndicator = [self pb_getOrCreateActivityIndicatorView:top];
    CGFloat indicatorHeight = CGRectGetHeight(activityIndicator.bounds);
    
    return indicatorHeight + self.infiniteScrollIndicatorMargin * 2;
}

- (void)pb_positionInfiniteScrollIndicatorWithContentSize:(CGSize)size top:(BOOL)top {
    // adjust content height for case when contentSize smaller than view bounds
    CGFloat contentHeight = [self pb_adjustedHeightFromContentSize:size];
    
    UIView* activityIndicator = [self pb_getOrCreateActivityIndicatorView:top];
    CGFloat indicatorViewHeight = CGRectGetHeight(activityIndicator.bounds);
    CGFloat indicatorRowHeight = [self pb_infiniteIndicatorRowHeight:top];
    
    CGRect rect = activityIndicator.frame;
    rect.origin.x = size.width * 0.5 - CGRectGetWidth(rect) * 0.5;
    rect.origin.y = top ? -(indicatorViewHeight + indicatorRowHeight * 0.5 - indicatorViewHeight * 0.5) : (contentHeight + indicatorRowHeight * 0.5 - indicatorViewHeight * 0.5);
    
    if(!CGRectEqualToRect(rect, activityIndicator.frame)) {
        activityIndicator.frame = rect;
    }
}

- (void)pb_startAnimatingInfiniteScroll:(BOOL)top {
    UIView* activityIndicator = [self pb_getOrCreateActivityIndicatorView:top];
    
    [self pb_positionInfiniteScrollIndicatorWithContentSize:self.contentSize top:top];
    
    activityIndicator.hidden = NO;
    
    if([activityIndicator respondsToSelector:@selector(startAnimating)]) {
        [activityIndicator performSelector:@selector(startAnimating) withObject:nil];
    }
    
    UIEdgeInsets contentInset = self.contentInset;
    
    // Make a room to accommodate indicator view
    if (top) {
        contentInset.top += [self pb_infiniteIndicatorRowHeight:top];
    }
    else {
        contentInset.bottom += [self pb_infiniteIndicatorRowHeight:top];
    }
    // We have to pad scroll view when content height is smaller than view bounds.
    // This will guarantee that indicator view appears at the very bottom of scroll view.
    CGFloat adjustedContentHeight = [self pb_adjustedHeightFromContentSize:self.contentSize];
    CGFloat extraBottomInset = adjustedContentHeight - self.contentSize.height;
    
    // Add empty space padding
    if (top) {
        contentInset.top += extraBottomInset;
    }
    else {
        contentInset.bottom += extraBottomInset;
    }
    
    // Save extra inset
    self.pb_infiniteScrollExtraBottomInset = extraBottomInset;
    
    TRACE(@"extraBottomInset = %.2f", extraBottomInset);
    
    self.pb_infiniteScrollState = PBInfiniteScrollStateLoading;
    [self pb_setScrollViewContentInset:contentInset animated:self.pb_infiniteScrollAnimated completion:^(BOOL finished) {
        if(finished) {
            [self pb_scrollToInfiniteIndicatorIfNeeded:top];
        }
    }];
    TRACE(@"Start animating.");
}

- (void)pb_stopAnimatingInfiniteScrollWithCompletion:(void(^)(id scrollView))handler top:(BOOL)top {
    UIView* activityIndicator = top ? self.infiniteScrollIndicatorTopView : self.infiniteScrollIndicatorBottomView;
    UIEdgeInsets contentInset = self.contentInset;
    
    if (top) {
        contentInset.top -= [self pb_infiniteIndicatorRowHeight:top];
        
        // remove extra inset added to pad infinite scroll
        contentInset.top -= self.pb_infiniteScrollExtraBottomInset;
    }
    else {
        contentInset.bottom -= [self pb_infiniteIndicatorRowHeight:top];
        
        // remove extra inset added to pad infinite scroll
        contentInset.bottom -= self.pb_infiniteScrollExtraBottomInset;
    }
    
    [self pb_setScrollViewContentInset:contentInset animated:self.pb_infiniteScrollAnimated completion:^(BOOL finished) {
        if([activityIndicator respondsToSelector:@selector(stopAnimating)]) {
            [activityIndicator performSelector:@selector(stopAnimating) withObject:nil];
        }
        
        activityIndicator.hidden = YES;
        
        self.pb_infiniteScrollState = PBInfiniteScrollStateNone;
        
        // Initiate scroll to the bottom if due to user interaction contentOffset.y
        // stuck somewhere between last cell and activity indicator
        if(finished) {
            CGFloat newY = top ? (self.contentInset.top) : (self.contentSize.height - self.bounds.size.height + self.contentInset.bottom);
            
            if(self.contentOffset.y > newY && newY > 0) {
                [self setContentOffset:CGPointMake(0, newY) animated:self.pb_infiniteScrollAnimated];
                TRACE(@"Stop animating and scroll to bottom.");
            }
        }
        
        // Call completion handler
        if(handler) {
            handler(self);
        }
    }];
    
    TRACE(@"Stop animating.");
}

- (void)pb_scrollViewDidScroll:(CGPoint)contentOffset {
    CGFloat contentHeight = [self pb_adjustedHeightFromContentSize:self.contentSize];
    
    // The lower bound when infinite scroll should kick in
    CGFloat actionOffsetBottom = contentHeight - self.bounds.size.height + self.contentInset.bottom;
    CGFloat actionOffsetTop = -self.contentInset.top;
    
    // Disable infinite scroll when scroll view is empty
    // Default UITableView reports height = 1 on empty tables
    BOOL hasActualContent = (self.contentSize.height > 1);
    
    if([self isDragging] && hasActualContent) {
        if(self.pb_infiniteScrollState == PBInfiniteScrollStateNone) {
            if (self.pb_infiniteScrollBottomInitialized && contentOffset.y > actionOffsetBottom) {
                TRACE(@"Action bottom.");
                
                [self pb_startAnimatingInfiniteScroll:NO];
                
                // This will delay handler execution until scroll deceleration
                [self performSelector:@selector(pb_callInfiniteScrollHandlerBottom) withObject:self afterDelay:0.1 inModes:@[ NSDefaultRunLoopMode ]];
            }
            else if (self.pb_infiniteScrollTopInitialized && contentOffset.y < actionOffsetTop) {
                TRACE(@"Action Top.");
                
                [self pb_startAnimatingInfiniteScroll:YES];
                
                // This will delay handler execution until scroll deceleration
                [self performSelector:@selector(pb_callInfiniteScrollHandlerTop) withObject:self afterDelay:0.1 inModes:@[ NSDefaultRunLoopMode ]];
            }
        }
    }
}

//
// Scrolls down to activity indicator position if activity indicator is partially visible
//
- (void)pb_scrollToInfiniteIndicatorIfNeeded:(BOOL)top {
    if(![self isDragging] && self.pb_infiniteScrollState == PBInfiniteScrollStateLoading) {
        // adjust content height for case when contentSize smaller than view bounds
        CGFloat contentHeight = [self pb_adjustedHeightFromContentSize:self.contentSize];
        CGFloat indicatorRowHeight = top ? -([self pb_infiniteIndicatorRowHeight:top]) : [self pb_infiniteIndicatorRowHeight:top];
        
        CGFloat barHeight = top ? (self.contentInset.top + indicatorRowHeight) : (self.contentInset.bottom - indicatorRowHeight);
        CGFloat minY = top ? -(barHeight) : (contentHeight - self.bounds.size.height + barHeight);
        CGFloat maxY = minY + indicatorRowHeight;
        CGFloat y = self.contentOffset.y;
        TRACE(@"minY = %.2f; maxY = %.2f; offsetY = %.2f", minY, maxY, y);
        
        if ((!top && y > minY && y < maxY) || (top && y < minY && y > maxY)) {
            TRACE(@"Scroll to infinite indicator.");
            [self setContentOffset:CGPointMake(0, maxY) animated:self.pb_infiniteScrollAnimated];
        }
    }
}

- (void)pb_setScrollViewContentInset:(UIEdgeInsets)contentInset animated:(BOOL)animated completion:(void(^)(BOOL finished))completion {
    void(^animations)(void) = ^{
        self.contentInset = contentInset;
    };
    
    if(animated)
    {
        [UIView animateWithDuration:kPBInfiniteScrollAnimationDuration
                              delay:0.0
                            options:(UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState)
                         animations:animations
                         completion:completion];
    }
    else
    {
        [UIView performWithoutAnimation:animations];
        
        if(completion) {
            completion(YES);
        }
    }
}

@end
