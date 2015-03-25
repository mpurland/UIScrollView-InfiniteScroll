//
//  TableViewController.m
//  InfiniteScrollViewDemo
//
//  Created by pronebird on 09/05/14.
//  Copyright (c) 2014 codeispoetry.ru. All rights reserved.
//

#import "TableViewController.h"
#import "UIApplication+NetworkIndicator.h"
#import "BrowserViewController.h"
#import "StoryModel.h"

#import "CustomInfiniteIndicator.h"
#import "UIScrollView+InfiniteScroll.h"

static NSString* const kAPIEndpointURL = @"https://hn.algolia.com/api/v1/search_by_date?tags=story&hitsPerPage=%ld&page=%ld";
static NSString* const kShowBrowserSegueIdentifier = @"ShowBrowser";
static NSString* const kCellIdentifier = @"Cell";

static NSString* const kJSONResultsKey = @"hits";
static NSString* const kJSONNumPagesKey = @"nbPages";

@interface TableViewController()

@property (strong) NSMutableArray* stories;
@property (assign) NSInteger retryPage;
@property (assign) NSInteger firstPage;
@property (assign) NSInteger lastPage;
@property (assign) NSInteger numPages;

@end

@implementation TableViewController

#pragma mark - View lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // enable auto-sizing cells on iOS 8
    if([self.tableView respondsToSelector:@selector(layoutMargins)]) {
        self.tableView.estimatedRowHeight = 88.0;
        self.tableView.rowHeight = UITableViewAutomaticDimension;
    }
    
    self.firstPage = 5;
    self.lastPage = 5;
    self.numPages = 0;
    self.stories = [NSMutableArray new];
    
    __weak typeof(self) weakSelf = self;
    
    // Set custom indicator
    self.tableView.infiniteScrollIndicatorTopView = [[CustomInfiniteIndicator alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
    self.tableView.infiniteScrollIndicatorBottomView = [[CustomInfiniteIndicator alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
    
    // Add bottom infinite scroll handler
    [self.tableView addInfiniteScrollBottomWithHandler:^(UITableView* tableView) {
        [weakSelf loadRemoteDataWithDelay:YES completion:^(NSArray *newStories) {

            // Finish infinite scroll animations
            [tableView finishInfiniteScrollBottomWithCompletion:^(id scrollView) {
                if (self.stories.count == 0) {
                    self.stories = newStories;
                    [self.tableView reloadData];
                }
                else {
                    [self updateTableWithNewRowCount:NO newStories:newStories];
                }
            }];
        } top:NO page:self.lastPage + 1];
    }];

    [self.tableView addInfiniteScrollTopWithHandler:^(UITableView* tableView) {
        [weakSelf loadRemoteDataWithDelay:YES completion:^(NSArray *newStories) {
            // Finish infinite scroll animations
            [tableView finishInfiniteScrollTopWithCompletion:^(UIScrollView *scrollView) {
                if (self.stories.count == 0) {
                    self.stories = newStories;
                    [self.tableView reloadData];
                }
                else {
                    [self updateTableWithNewRowCount:YES newStories:newStories];
                }
            }];
        } top:YES page:self.firstPage - 1];
    }];
    
    // Load initial data
    [self loadRemoteDataWithDelay:NO completion:^(NSArray *newStories) {
        self.stories = newStories;
        [self.tableView reloadData];
    } top:NO page:self.firstPage];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if([segue.identifier isEqualToString:kShowBrowserSegueIdentifier]) {
        NSIndexPath* selectedRow = [self.tableView indexPathForSelectedRow];
        BrowserViewController* browserController = (BrowserViewController*)segue.destinationViewController;
        browserController.story = self.stories[selectedRow.row];
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.stories count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellIdentifier forIndexPath:indexPath];
    StoryModel* itemModel = self.stories[indexPath.row];
    
    cell.textLabel.text = itemModel.title;
    cell.detailTextLabel.text = itemModel.author;
    
    // enable auto-sizing cells on iOS 8
    if([tableView respondsToSelector:@selector(layoutMargins)]) {
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.numberOfLines = 0;
    }
    
    return cell;
}

#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if(buttonIndex == alertView.firstOtherButtonIndex) {
        [self loadRemoteDataWithDelay:NO completion:nil top:NO page:self.retryPage];
    }
}

#pragma mark - Private methods

- (void)showRetryAlertWithError:(NSError*)error {
    UIAlertView* alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error fetching data", @"")
                                                        message:[error localizedDescription]
                                                       delegate:self
                                              cancelButtonTitle:NSLocalizedString(@"Dismiss", @"")
                                              otherButtonTitles:NSLocalizedString(@"Retry", @""), nil];
    [alertView show];
}

-(void) updateTableWithNewRowCount:(BOOL)top newStories:(NSArray *)newStories {
    // Save the tableview content offset
    CGPoint tableViewOffset = [self.tableView contentOffset];
    
    // Turn off animations for the update block
    // to get the effect of adding rows on top of TableView
    [UIView setAnimationsEnabled:NO];
    
    if (top) {
        self.stories = [[newStories arrayByAddingObjectsFromArray:self.stories] mutableCopy];
    }
    else {
        [self.stories addObjectsFromArray:newStories];
    }
    
    if (top) {
//        [self.tableView beginUpdates];
        
        int heightForNewRows = 0;
        
        NSMutableArray *indexPaths = [NSMutableArray array];
        
        for (id newStory in newStories) {
            NSUInteger index = [self.stories indexOfObject:newStory];
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
            [indexPaths addObject:indexPath];
        }
        
        // Reload data instead of insert because animation causes view to jitter
        [self.tableView reloadData];
        
//        [self.tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationNone];
//        [self.tableView endUpdates];
        
        heightForNewRows = 0;
        for (NSIndexPath *indexPath in indexPaths) {
            CGFloat height = [self heightForCellAtIndexPath:indexPath];
            heightForNewRows += height;
        }
        
        tableViewOffset.y += heightForNewRows;
        [self.tableView setContentOffset:tableViewOffset animated:NO];
    }
    else {
        [self.tableView reloadData];
    }

    [UIView setAnimationsEnabled:YES];
}

- (CGFloat)heightForCellAtIndexPath: (NSIndexPath *) indexPath {
    // Getting the rect for the row instead of the cell is more reliable since the row may not be visible
    CGRect rect = [self.tableView rectForRowAtIndexPath:indexPath];
    return rect.size.height;
    
//    UITableViewCell *cell =  [self.tableView cellForRowAtIndexPath:indexPath];
//    CGFloat cellHeight = cell.frame.size.height;
//    return cellHeight;
}

- (void)handleAPIResponse:(NSURLResponse*)response data:(NSData*)data error:(NSError*)error completion:(void(^)(NSArray *newStories))completion top:(BOOL)top {
    // Check for network errors
    if(error) {
        [self showRetryAlertWithError:error];
        if(completion) {
            completion(nil);
        }
        return;
    }
    
    // Unserialize JSON
    NSError* JSONError;
    NSDictionary* responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&JSONError];
    
    if(JSONError) {
        [self showRetryAlertWithError:JSONError];
        if(completion) {
            completion(nil);
        }
        return;
    }
    
    // Decode models on background queue
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block NSMutableArray* newStories = [NSMutableArray new];
        
        for(NSDictionary* item in responseDict[kJSONResultsKey]) {
            [newStories addObject:[StoryModel modelWithDictionary:item]];
        }
        
        // Append new data on main thread and reload table
        dispatch_async(dispatch_get_main_queue(), ^{
            self.numPages = [responseDict[kJSONNumPagesKey] integerValue];
            
            if (top) {
                self.firstPage--;
            }
            else {
                self.lastPage++;
            }

            // Do not reload content here because top/bottom animation is better suited after finishInfiniteScrollXX animation is completed
        
            if(completion) {
                completion(newStories);
            }
        });
    });
}

- (void)loadRemoteDataWithDelay:(BOOL)withDelay completion:(void(^)(NSArray *newStories))completion top:(BOOL)top page:(NSInteger)page
{
    // Show network activity indicator
    [[UIApplication sharedApplication] startNetworkActivity];
    
    // Calculate optimal number of results to load
    NSInteger hitsPerPage = CGRectGetHeight(self.tableView.bounds) / 44.0;
    
    self.retryPage = page;
    
    // Craft API URL
    NSString* requestURL = [NSString stringWithFormat:kAPIEndpointURL, (long)hitsPerPage, page];
    
    // Create request
    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:requestURL]];
    
    // Create NSDataTask
    NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleAPIResponse:response data:data error:error completion:completion top:top];
            
            // Hide network activity indicator
            [[UIApplication sharedApplication] stopNetworkActivity];
            
        });
    }];
    
    // Start network task
    
    // I run -[task resume] with delay because my network is too fast
    NSTimeInterval delay = (withDelay ? 1.0 : 0.0);
    
    [task performSelector:@selector(resume) withObject:nil afterDelay:delay];
}

@end
