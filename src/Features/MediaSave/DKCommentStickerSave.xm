// 评论表情长按菜单：在「添加到表情」后并列「保存表情包」，由评论 cell 响应并按评论模型保存原表情。
#import "DouyinHeaders.h"
#import "DKKeys.h"
#import "DKSettings.h"
#import "DKUtils.h"
#import "DKMediaResolver.h"
#import "DKMediaSaveDiagnostics.h"
#import "DKMediaSaveRuntime.h"
#import "DKMediaSaveTask.h"
#import "DKMediaSelect.h"

static NSString *const kDKCommentCellClass = @"AWECommentPanelListSwiftImpl.CommentNewCell";

@interface DKCommentNewCell : UICollectionViewCell
@end

@interface DKCommentNewCell (DKMediaSave)
- (void)dk_saveCommentSticker:(id)sender;
@end

static BOOL DKMenuHasAction(NSArray *items, SEL action) {
    for (id item in items) {
        if ([item isKindOfClass:UIMenuItem.class] && ((UIMenuItem *)item).action == action) return YES;
    }
    return NO;
}

static id DKUnwrapCommentModel(id value, NSUInteger depth) {
    Class commentClass = NSClassFromString(@"AWECommentModel");
    if (commentClass && [value isKindOfClass:commentClass]) return value;
    if (!value || depth >= 4) return nil;
    for (NSString *key in @[@"commentModel", @"comment", @"model", @"viewModel", @"dataModel", @"item"]) {
        id candidate = DKUnwrapCommentModel(DKMediaValue(value, key), depth + 1);
        if (candidate) return candidate;
    }
    return nil;
}

static NSArray *DKCommentSectionsFromOwner(id owner) {
    NSArray *directSections = DKMediaValue(owner, @"sectionViewModelsArray");
    if ([directSections isKindOfClass:NSArray.class]) return directSections;
    for (NSString *key in @[@"viewModel", @"commentViewModel", @"listViewModel", @"dataSource"]) {
        id nestedOwner = DKMediaValue(owner, key);
        NSArray *sections = DKMediaValue(nestedOwner, @"sectionViewModelsArray");
        if ([sections isKindOfClass:NSArray.class]) return sections;
    }
    return nil;
}

static NSString *DKResponderClassPath(UIResponder *responder) {
    NSMutableArray<NSString *> *classes = [NSMutableArray array];
    for (UIResponder *current = responder; current && classes.count < 12; current = current.nextResponder) {
        [classes addObject:NSStringFromClass([current class])];
    }
    return [classes componentsJoinedByString:@" -> "];
}

// 优先从可见 cell 自身取模型；列表控制器按 viewModel 结构查找，不依赖首页评论页的具体类名。
static id DKCommentForCell(UICollectionViewCell *cell, NSString **modelSource, UIViewController **modelController) {
    id directComment = DKUnwrapCommentModel(cell, 0);
    if (directComment) {
        if (modelSource) *modelSource = @"cell model";
        return directComment;
    }

    UICollectionView *list = nil;
    for (UIView *view = cell.superview; view; view = view.superview) {
        if ([view isKindOfClass:UICollectionView.class]) { list = (UICollectionView *)view; break; }
    }
    NSIndexPath *path = [list indexPathForCell:cell];
    UIViewController *controller = nil;
    NSArray *sections = nil;
    NSString *sectionSource = @"controller";
    for (UIResponder *responder = cell; responder; responder = responder.nextResponder) {
        if (![responder isKindOfClass:UIViewController.class]) continue;
        NSArray *candidate = DKCommentSectionsFromOwner(responder);
        if (!candidate) continue;
        controller = (UIViewController *)responder;
        sections = candidate;
        break;
    }
    if (!sections) {
        sections = DKCommentSectionsFromOwner(list.dataSource);
        if (sections) sectionSource = @"collection.dataSource";
    }
    if (!sections) {
        sections = DKCommentSectionsFromOwner(list.delegate);
        if (sections) sectionSource = @"collection.delegate";
    }
    if (modelController) *modelController = controller;
    if (!path || ![sections isKindOfClass:NSArray.class] || (NSUInteger)path.section >= sections.count) return nil;
    NSArray *models = DKMediaValue(sections[path.section], @"modelsArray");
    if (![models isKindOfClass:NSArray.class] || (NSUInteger)path.item >= models.count) return nil;
    id comment = DKUnwrapCommentModel(models[path.item], 0);
    if (comment && modelSource) *modelSource = [sectionSource stringByAppendingString:@".modelsArray"];
    return comment;
}

%group DKStickerMenuHooks
%hook UIMenuController
- (void)setMenuItems:(NSArray *)items {
    SEL save = @selector(dk_saveCommentSticker:);
    if (DKPrefBool(DKKeyMediaSaveCommentSticker) && DKMenuHasAction(items, NSSelectorFromString(@"addSticker")) && !DKMenuHasAction(items, save)) {
        NSMutableArray *extended = [items mutableCopy];
        [extended addObject:[[UIMenuItem alloc] initWithTitle:@"保存表情包" action:save]];
        DKMediaSaveHit(DKMediaSaveEntryStickerMenu);
        %orig(extended);
        return;
    }
    %orig;
}
%end
%end

%group DKStickerCellHooks
%hook DKCommentNewCell
- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(dk_saveCommentSticker:)) return DKPrefBool(DKKeyMediaSaveCommentSticker);
    return %orig;
}

%new
- (void)dk_saveCommentSticker:(id)sender {
    DKMediaSaveHit(DKMediaSaveEntryStickerCell);
    UICollectionViewCell *cell = (UICollectionViewCell *)self;
    NSString *modelSource = @"unresolved";
    UIViewController *modelController = nil;
    id comment = DKCommentForCell(cell, &modelSource, &modelController);
    NSDictionary *resolvedComment = comment ? DKResolveComment(comment) : nil;
    DKMediaSaveItem *item = resolvedComment ? DKSelectCommentSticker(resolvedComment) : nil;
    NSArray *stickerURLs = resolvedComment[@"sticker"][@"animate"][@"urls"]
        ?: resolvedComment[@"sticker"][@"static"][@"urls"];
    id content = DKMediaValue(comment, @"content") ?: DKMediaValue(comment, @"commentContent");
    NSMutableArray<NSString *> *modelFields = [NSMutableArray array];
    for (NSString *key in @[@"sticker", @"stickerModel", @"commentSticker", @"commentStickerModel"]) {
        if (DKMediaValue(comment, key)) [modelFields addObject:key];
        if (DKMediaValue(content, key)) [modelFields addObject:[@"content." stringByAppendingString:key]];
    }
    DKMediaSaveNote([NSString stringWithFormat:@"评论表情入口 source=%@ controller=%@ model=%@ fields=%@ stickerURLs=%lu item=%@",
                     modelSource,
                     modelController ? NSStringFromClass([modelController class]) : @"nil",
                     comment ? NSStringFromClass([comment class]) : @"nil",
                     modelFields.count ? [modelFields componentsJoinedByString:@","] : @"none",
                     (unsigned long)[stickerURLs count],
                     item ? @"resolved" : @"nil"]);
    if (!comment || !item) {
        UICollectionView *list = nil;
        for (UIView *view = cell.superview; view; view = view.superview) {
            if ([view isKindOfClass:UICollectionView.class]) { list = (UICollectionView *)view; break; }
        }
        NSIndexPath *path = [list indexPathForCell:cell];
        id dataSource = list.dataSource;
        id delegate = list.delegate;
        DKMediaSaveNote([NSString stringWithFormat:@"评论表情上下文 cell=%@ list=%@ controller=%@ dataSource=%@ delegate=%@ index=%@ responders=%@",
                         NSStringFromClass([self class]),
                         list ? NSStringFromClass([list class]) : @"nil",
                         modelController ? NSStringFromClass([modelController class]) : @"nil",
                         dataSource ? NSStringFromClass([dataSource class]) : @"nil",
                         delegate ? NSStringFromClass([delegate class]) : @"nil",
                         path ? [NSString stringWithFormat:@"%ld/%ld", (long)path.section, (long)path.item] : @"nil",
                         DKResponderClassPath(cell)]);
    }
    DKMediaSaveRun(item ? @[item] : @[], @"评论表情长按");
}
%end
%end

%ctor {
    DKSettingsRegister(DKKeyMediaSaveCommentSticker, ^AWESettingItemModel *{
        return DKMakeSwitch(DKKeyMediaSaveCommentSticker, @"保存评论区表情包",
                            @"长按评论表情的菜单、单击评论表情后的表情页里增加「保存表情包」；也可长按评论用「保存到相册」保存。动图存为 GIF。");
    });
    Class cell = NSClassFromString(kDKCommentCellClass);
    BOOL cellOK = DKMediaMethod(cell, @selector(canPerformAction:withSender:), "B:@");
    BOOL menuOK = cellOK && DKMediaMethod(UIMenuController.class, @selector(setMenuItems:), "v@");
    if (cellOK) %init(DKStickerCellHooks, DKCommentNewCell = cell);
    if (menuOK) %init(DKStickerMenuHooks);
    DKMediaSaveInstalled(DKMediaSaveEntryStickerCell, cellOK);
    DKMediaSaveInstalled(DKMediaSaveEntryStickerMenu, menuOK);
}
