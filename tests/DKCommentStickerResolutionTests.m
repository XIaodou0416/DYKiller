#import <Foundation/Foundation.h>
#import "DKMediaResolver.h"
#import "DKMediaSelect.h"

static BOOL DKExpectStickerURL(NSDictionary *comment, NSString *expectedURL) {
    NSDictionary *resolved = DKResolveComment(comment);
    DKMediaSaveItem *item = DKSelectCommentSticker(resolved);
    NSString *actualURL = item.primary.firstObject.urls.firstObject;
    return item.kind == DKMediaKindAnimated && [actualURL isEqualToString:expectedURL];
}

int main(void) {
    @autoreleasepool {
        NSString *url = @"https://p3-pc-sign.douyinpic.com/aweme/1000x1000/test.gif";
        NSDictionary *homeComment = @{
            @"sticker": @{
                @"animateURLModel": @{@"originURLList": @[url]}
            }
        };
        NSDictionary *searchComment = @{
            @"content": @{
                @"commentSticker": @{
                    @"animateURLModel": @{@"originURLList": @[url]}
                }
            }
        };

        if (!DKExpectStickerURL(homeComment, url)) {
            NSLog(@"FAIL: canonical home comment sticker did not resolve");
            return 1;
        }
        if (!DKExpectStickerURL(searchComment, url)) {
            NSLog(@"FAIL: nested search-detail comment sticker did not resolve");
            return 1;
        }
        NSLog(@"PASS: home and nested search-detail comment stickers resolve to saveable GIF items");
    }
    return 0;
}
