//
//  UIScrollView+InfiniteScroll.h
//
//  UIScrollView infinite scroll category
//
//  Created by Andrej Mihajlov on 9/4/13.
//  Copyright (c) 2013-2015 Andrej Mihajlov. All rights reserved.
//

#import <UIKit/UIKit.h>

static CGFloat const UIScrollViewInfiniteScrollDefaultScrollIndicatorMargin = 11.0f;

@interface UIScrollView (InfiniteScroll)

/**
 *  Infinite scroll activity indicator style (default: UIActivityIndicatorViewStyleGray)
 */
@property (nonatomic) UIActivityIndicatorViewStyle infiniteScrollIndicatorTopStyle;
@property (nonatomic) UIActivityIndicatorViewStyle infiniteScrollIndicatorBottomStyle;

/**
 *  Infinite indicator view
 *
 *  You can set your own custom view instead of default activity indicator, 
 *  make sure it implements methods below:
 *
 *  * `- (void)startAnimating`
 *  * `- (void)stopAnimating`
 *
 *  Infinite scroll will call implemented methods during user interaction.
 */
@property (nonatomic) UIView* infiniteScrollIndicatorTopView;
@property (nonatomic) UIView* infiniteScrollIndicatorBottomView;

/**
 *  Vertical margin around indicator view (Default: 11)
 */
@property (nonatomic) CGFloat infiniteScrollIndicatorMargin;

/**
 *  Setup infinite scroll handler
 *
 *  @param handler a handler block
 */
- (void)addInfiniteScrollTopWithHandler:(void(^)(id scrollView))handler animated:(BOOL)animated;
- (void)addInfiniteScrollBottomWithHandler:(void(^)(id scrollView))handler animated:(BOOL)animated;
- (void)addInfiniteScrollTopWithHandler:(void(^)(id scrollView))handler;
- (void)addInfiniteScrollBottomWithHandler:(void(^)(id scrollView))handler;

/**
 *  Unregister infinite scroll
 */
- (void)removeInfiniteScrollTop;
- (void)removeInfiniteScrollBottom;

/**
 *  Finish infinite scroll animations
 *
 *  You must call this method from your infinite scroll handler to finish all
 *  animations properly and reset infinite scroll state
 *
 *  @param handler a completion block handler called when animation finished
 */
- (void)finishInfiniteScrollTopWithCompletion:(void(^)(id scrollView))handler;
- (void)finishInfiniteScrollBottomWithCompletion:(void(^)(id scrollView))handler;

/**
 *  Finish infinite scroll animations
 *
 *  You must call this method from your infinite scroll handler to finish all
 *  animations properly and reset infinite scroll state
 */
- (void)finishInfiniteScrollTop;
- (void)finishInfiniteScrollBottom;

/**
 * Infinite scroll indicator height with margin included. 
 *
 * You may call this method to return to the height of the top or bottom indicator view.
 */
- (CGFloat)infiniteScrollIndicatorRowHeight:(BOOL)top;

@end
