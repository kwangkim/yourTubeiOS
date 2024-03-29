//
//  RZSplitViewController.h
//
//  Created by Joe Goullaud on 8/6/12.

// Copyright 2014 Raizlabs and other contributors
// http://raizlabs.com/
//
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
// LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
// OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
// WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import <UIKit/UIKit.h>


@class SettingsTableViewController;

@interface SettingsTableViewCell : UITableViewCell

@property (nonatomic, strong) UIColor *selectionColor;
@property (nonatomic, strong) UIColor *viewBackgroundColor;

@end

@protocol DetailViewSelectionDelegate <NSObject>

- (void)selectedItemAtIndexPath:(NSIndexPath *)indexPath;

@end

@interface DetailViewController : UIViewController <DetailViewSelectionDelegate>


@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, weak) NSArray *imageNames;

@end

@protocol SettingsTableViewSelectionDelegate <NSObject>

- (void)itemSelectedAtIndexPath:(NSIndexPath *)indexPath;

@end

@interface SettingsTableViewController : UITableViewController <DetailViewSelectionDelegate>

@property (nonatomic, weak) id<SettingsTableViewSelectionDelegate> selectionDelegate;
@property (nonatomic, weak) id<DetailViewSelectionDelegate> delegate;
@property (nonatomic, strong) NSArray *itemNames;

- (void)focusedCell:(UITableViewCell *)focusedCell;

@end



@protocol RZSplitViewControllerDelegate;

@protocol SettingsViewDelegate <NSObject>

- (void)itemSelectedAtIndexPath:(NSIndexPath *)indexPath fromNavigationController:(UINavigationController *)nav;

@end

@interface SettingsViewController : UIViewController <SettingsTableViewSelectionDelegate>

/*

 properties copied over from the settings view
 
 */


@property (nonatomic, weak) id <SettingsViewDelegate> selectionDelegate;
@property (nonatomic, strong) NSArray *itemNames;
@property (nonatomic, strong) NSArray *imageNames;
@property (nonatomic, strong) NSString *viewTitle;
@property (nonatomic, strong) UIColor *backgroundColor;


@property (copy, nonatomic) NSArray *viewControllers;
@property (weak, nonatomic) id <RZSplitViewControllerDelegate> delegate;        // Not used yet
@property (strong, nonatomic) UIImage *collapseBarButtonImage;
@property (strong, nonatomic) UIImage *expandBarButtonImage;
@property (strong, nonatomic, readonly) UIBarButtonItem *collapseBarButton;
@property (assign, nonatomic, getter = isCollapsed) BOOL collapsed;
@property (nonatomic, assign) CGFloat masterWidth;
@property (strong, nonatomic) UIColor* viewBorderColor;
@property (nonatomic, assign) CGFloat viewCornerRadius;
@property (nonatomic, assign) CGFloat viewBorderWidth;
@property (readwrite, assign) CGFloat preferredPrimaryColumnWidthFraction; //doesnt do anything right now

@property (nonatomic, readonly) UIViewController *masterViewController;
@property (nonatomic, readonly) UIViewController *detailViewController;

- (void)setCollapsed:(BOOL)collapsed animated:(BOOL)animated;
- (void)setDetailViewController:(UIViewController*)detailVC;
- (void)setMasterViewController:(UIViewController*)masterVC;

/*
 
 you MUST initialize with this method or nothing will work and everything will need to be done manually! (for now)
 
 */

+ (id)settingsViewControllerWithTitle:(NSString *)theTitle backgroundColor:(UIColor *)bgColor withItemNames:(NSArray *)names withImages:(NSArray *)images;

@end


// Delegate is not implemented yet
@protocol RZSplitViewControllerDelegate <NSObject>

- (BOOL)splitViewController:(SettingsViewController*)svc shouldHideViewController:(UIViewController *)vc inOrientation:(UIInterfaceOrientation)orientation;

- (void)splitViewController:(SettingsViewController *)svc willHideViewController:(UIViewController *)aViewController withBarButtonItem:(UIBarButtonItem *)barButtonItem forPopoverController:(UIPopoverController *)pc;

- (void)splitViewController:(SettingsViewController *)svc willShowViewController:(UIViewController *)aViewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem;

- (void)splitViewController:(SettingsViewController *)svc popoverController:(UIPopoverController *)pc willPresentViewController:(UIViewController *)aViewController;

@end


@interface UIViewController (RZSplitViewController)

@property (strong, nonatomic, readonly) SettingsViewController *rzSplitViewController;

@end