//
//  MeshListViewController.m
//  RoomCapture
//
//  Created by Rafay Hasan on 18/12/18.
//  Copyright © 2018 Occipital. All rights reserved.
//

#import "MeshListViewController.h"
#import "MeshCollectionViewCell.h"
#import "ViewController.h"
@interface MeshListViewController ()<UICollectionViewDelegate,UICollectionViewDataSource,UICollectionViewDelegateFlowLayout> {
    
}

- (IBAction)scanButtonAction:(id)sender;

@end

@implementation MeshListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
//    self.viewController = [ViewController viewController];
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return 10;
}

- ( UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"mesh";
    MeshCollectionViewCell *cell = (MeshCollectionViewCell *)[collectionView dequeueReusableCellWithReuseIdentifier:identifier forIndexPath:indexPath];
    return cell;
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    return 1;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return CGSizeMake(100, 100);
}

- (IBAction)scanButtonAction:(id)sender {
    self.viewController = [ViewController viewController];
    [self.navigationController pushViewController:self.viewController animated:YES];
}
@end
