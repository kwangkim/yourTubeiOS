//
//  KBYTSearchResultsViewController.m
//  yourTubeiOS
//
//  Created by Kevin Bradley on 3/7/16.
//
//

#import "KBYTSearchResultsViewController.h"
#import "YTTVStandardCollectionViewCell.h"
#import "SVProgressHUD.h"
#import "KBYourTube.h"
#import "UIImageView+WebCache.h"
#import "KBYTChannelViewController.h"
#import "SVProgressHUD.h"
#import "YTTVPlaylistViewController.h"

@interface KBYTSearchResultsViewController ()

@property (readwrite, assign) NSInteger currentPage;
@property (readwrite, assign) NSInteger rows; //5 items per row
@property (nonatomic, strong) NSString *filterString;
@property (nonatomic, strong) NSMutableArray *searchResults; // Filtered search results
@property (readwrite, assign) NSInteger totalResults; // Filtered search results
@property (readwrite, assign) NSInteger pageCount;


@end

@implementation KBYTSearchResultsViewController

@synthesize pageCount, currentPage, filterString;

static NSString * const reuseIdentifier = @"NewStandardCell";

- (void)viewDidLoad {
    [super viewDidLoad];
    
    
    // Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
 #pragma mark - Navigation
 
 // In a storyboard-based application, you will often want to do a little preparation before navigation
 - (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
 // Get the new view controller using [segue destinationViewController].
 // Pass the selected object to the new view controller.
 }
 */

- (void)viewDidAppear:(BOOL)animated
{
    
    [super viewDidAppear:animated];
    UISearchController *sc = [(UISearchContainerViewController*)self.presentingViewController searchController];
    [sc.searchBar becomeFirstResponder];
    
    //NSString *recurse = [sc.searchBar performSelector:@selector(recursiveDescription)];
    //NSLog(@"recurse: %@", recurse);
}


- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    UISearchController *sc = [(UISearchContainerViewController*)self.presentingViewController searchController];
    [sc.searchBar resignFirstResponder];
    //NSLog(@"sc: %@", sc);
    
}

#pragma mark <UICollectionViewDataSource>

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    
    return 1;
}


- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    
    
    return self.searchResults.count;
}

- (void)collectionView:(UICollectionView *)collectionView didHighlightItemAtIndexPath:(NSIndexPath *)indexPath
{

  
}

 - (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath
 {
     
     //check to see if we are on the last row
     NSInteger rowCount = self.searchResults.count / 5;
     NSInteger currentRow = indexPath.row / 5;
   //  NSLog(@"indexRow : %lu currentRow: %lu rowCount: %lu, searchCount: %lu", indexPath.row, currentRow, rowCount, self.searchResults.count);
     if (currentRow+1 >= rowCount)
     {
         [self getNextPage];
     }
 
 }
 
 


- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    YTTVStandardCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:reuseIdentifier forIndexPath:indexPath];
    
    KBYTSearchResult *currentItem = [self.searchResults objectAtIndex:indexPath.row];
    if (currentItem.resultType != kYTSearchResultTypeVideo)
    {
        cell.overlayView.hidden = false;
        cell.overlayInfo.text = currentItem.details;
 
    } else {
        cell.overlayView.hidden = true;
        cell.overlayInfo.text = @"";
    }
    NSURL *imageURL = [NSURL URLWithString:currentItem.imagePath];
    UIImage *theImage = [UIImage imageNamed:@"YTPlaceholder"];
    [cell.image sd_setImageWithURL:imageURL placeholderImage:theImage options:SDWebImageAllowInvalidSSLCertificates];
    cell.title.text = [NSString stringWithFormat:@"%@ - %@", currentItem.author, currentItem.title];
    // Configure the cell
    
    return cell;
}

- (void)updateSearchResults:(NSArray *)newResults
{
    if (self.currentPage > 1)
    {
        [[self searchResults] addObjectsFromArray:newResults];
    } else {
        self.searchResults = [newResults mutableCopy];
    }
}

- (void)itemDidFinishPlaying:(NSNotification *)n
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:n.object];
    [[self.presentingViewController navigationController] popViewControllerAnimated:true];
}


- (void)playFirstStreamForResult:(KBYTSearchResult *)searchResult
{
    [SVProgressHUD setBackgroundColor:[UIColor clearColor]];
    [SVProgressHUD show];
    [[KBYourTube sharedInstance] getVideoDetailsForID:searchResult.videoId completionBlock:^(KBYTMedia *videoDetails) {
        
        [SVProgressHUD dismiss];
        NSURL *playURL = [[videoDetails.streams firstObject] url];
        AVPlayerViewController *playerView = [[AVPlayerViewController alloc] init];
        AVPlayerItem *singleItem = [AVPlayerItem playerItemWithURL:playURL];
        playerView.player = [AVQueuePlayer playerWithPlayerItem:singleItem];
        [[self.presentingViewController navigationController] pushViewController:playerView animated:true];
        [playerView.player play];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidFinishPlaying:) name:AVPlayerItemDidPlayToEndTimeNotification object:singleItem];
        
        
    } failureBlock:^(NSString *error) {
        
    }];
    
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    self.currentPage = 1; //reset for new search
    self.filterString = searchController.searchBar.text;
 
    
    [[KBYourTube sharedInstance] youTubeSearch:self.filterString pageNumber:self.currentPage includeAllResults:true completionBlock:^(NSDictionary *searchDetails) {
        
        //  NSLog(@"search details: %@", searchDetails);
        
        self.totalResults = [searchDetails[@"resultCount"] integerValue];
        self.pageCount = [searchDetails[@"pageCount"] integerValue];
        //self.searchResults = searchDetails[@"results"];
        [self updateSearchResults:searchDetails[@"results"]];
        [self.collectionView reloadData];
        
        
    } failureBlock:^(NSString *error) {
        //
        [SVProgressHUD dismiss];
        
    }];
}

- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator
{

    //YTTVStandardCollectionViewCell *selectedCell = (YTTVStandardCollectionViewCell*)context.nextFocusedView;
    //self.selectedItem=  [[self collectionView] indexPathForCell:selectedCell];
}

- (void)getNextPage
{
    if (_gettingPage) return;
    NSInteger nextPage = self.currentPage + 1;
    if (self.pageCount > nextPage)
    {
        _gettingPage = true;
        self.currentPage = nextPage;
        [[KBYourTube sharedInstance] youTubeSearch:self.filterString pageNumber:self.currentPage includeAllResults:true completionBlock:^(NSDictionary *searchDetails) {
            
            //  NSLog(@"search details: %@", searchDetails);
            if (self.currentPage == 1)
                [SVProgressHUD dismiss];
            
            self.totalResults = [searchDetails[@"resultCount"] integerValue];
            self.pageCount = [searchDetails[@"pageCount"] integerValue];
            //self.searchResults = searchDetails[@"results"];
            
            [self updateSearchResults:searchDetails[@"results"]];
           // NSIndexPath *currentIndexPath = [[self collectionView] indexPathsForSelectedItems][0];
            [self.collectionView reloadDataWithCompletion:^{
                
                /*
                [self.collectionView selectItemAtIndexPath:self.selectedItem animated:false scrollPosition:UICollectionViewScrollPositionCenteredVertically];
                UISearchController *sc = [(UISearchContainerViewController*)self.presentingViewController searchController];
                [sc.searchBar resignFirstResponder];
                */
                _gettingPage = false;
            }];
            
            
        } failureBlock:^(NSString *error) {
            //
            [SVProgressHUD dismiss];
            
        }];
    
    }
    
}

#pragma mark <UICollectionViewDelegate>


// Uncomment this method to specify if the specified item should be highlighted during tracking
- (BOOL)collectionView:(UICollectionView *)collectionView shouldHighlightItemAtIndexPath:(NSIndexPath *)indexPath {
    LOG_SELF;
    return YES;
}



// Uncomment this method to specify if the specified item should be selected
- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath {
        LOG_SELF;
    return YES;
}


- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    KBYTSearchResult *searchResult = [self.searchResults objectAtIndex:indexPath.row];
    if (searchResult.resultType == kYTSearchResultTypeVideo)
    {
        [self playFirstStreamForResult:searchResult];
    } else if (searchResult.resultType == kYTSearchResultTypeChannel)
    {
        UIStoryboard *sb = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
        KBYTChannelViewController *cv = [sb instantiateViewControllerWithIdentifier:@"channelViewController"];
        [SVProgressHUD setBackgroundColor:[UIColor clearColor]];
        [SVProgressHUD show];
        [[KBYourTube sharedInstance] getChannelVideos:searchResult.videoId completionBlock:^(NSDictionary *searchDetails) {
            
            [SVProgressHUD dismiss];
            
          //  NSLog(@"searchDeets: %@", searchDetails);
            
            cv.searchResults = searchDetails[@"results"];
            cv.pageCount = 1;
            cv.nextHREF = searchDetails[@"loadMoreREF"];
            cv.bannerURL = searchDetails[@"banner"];
            cv.channelTitle = searchDetails[@"name"];
            cv.subscribers = searchDetails[@"subscribers"];
          
            [[self.presentingViewController navigationController] pushViewController:cv animated:true];
            
        } failureBlock:^(NSString *error) {
            //
        }];
    } else if (searchResult.resultType == kYTSearchResultTypePlaylist)
    {
        [SVProgressHUD setBackgroundColor:[UIColor clearColor]];
        [SVProgressHUD show];
        [[KBYourTube sharedInstance] getPlaylistVideos:searchResult.videoId completionBlock:^(NSDictionary *searchDetails) {
            
            [SVProgressHUD dismiss];
            
            NSString *nextHREF = searchDetails[@"loadMoreREF"];
            YTTVPlaylistViewController *playlistViewController = [YTTVPlaylistViewController playlistViewControllerWithTitle:searchResult.title backgroundColor:[UIColor blackColor] withPlaylistItems:searchDetails[@"results"]];
            playlistViewController.loadMoreHREF = nextHREF;
            
            [[self.presentingViewController navigationController] pushViewController:playlistViewController animated:true];
            
        } failureBlock:^(NSString *error) {
            //
        }];
    }
    
}

/*
 // Uncomment these methods to specify if an action menu should be displayed for the specified item, and react to actions performed on the item
 - (BOOL)collectionView:(UICollectionView *)collectionView shouldShowMenuForItemAtIndexPath:(NSIndexPath *)indexPath {
	return NO;
 }
 
 - (BOOL)collectionView:(UICollectionView *)collectionView canPerformAction:(SEL)action forItemAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
	return NO;
 }
 
 - (void)collectionView:(UICollectionView *)collectionView performAction:(SEL)action forItemAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
	
 }
 */

@end
