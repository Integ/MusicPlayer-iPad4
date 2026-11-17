// 音乐播放器 — 面向 32 位老 iPad（iPad mini 1 / iPad 4，iOS 9–10）。纯代码界面，无 storyboard。
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import "Sonos.h"

#define RGB(r, g, b) [UIColor colorWithRed:(r) / 255.0 green:(g) / 255.0 blue:(b) / 255.0 alpha:1]
#define ACCENT RGB(255, 55, 95)
#define BG RGB(18, 18, 22)
#define PANEL RGB(28, 28, 34)

#pragma mark - Track

@interface Track : NSObject
@property NSString *title;
@property NSString *artist;
@property NSURL *url;
@property MPMediaItem *item;
@property UIImage *art;
@property BOOL artTried; // 已经尝试过联网找封面
@property BOOL stream;   // 网络电台（直播流）：没有时长，不能拖动进度
@end
@implementation Track
@end

#pragma mark - Icons

typedef NS_ENUM(NSInteger, Icon) { IconPlay, IconPause, IconNext, IconPrev };

static UIImage *MakeIcon(Icon icon, CGFloat s) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
    [[UIColor whiteColor] setFill];
    UIBezierPath *p = [UIBezierPath bezierPath];
    void (^tri)(CGFloat, CGFloat, BOOL) = ^(CGFloat x0, CGFloat x1, BOOL right) {
        CGFloat a = right ? x0 : x1, b = right ? x1 : x0;
        [p moveToPoint:CGPointMake(a, s * 0.18)];
        [p addLineToPoint:CGPointMake(b, s * 0.5)];
        [p addLineToPoint:CGPointMake(a, s * 0.82)];
        [p closePath];
    };
    switch (icon) {
        case IconPlay: tri(s * 0.24, s * 0.84, YES); break;
        case IconPause:
            [p appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(s * 0.22, s * 0.18, s * 0.2, s * 0.64) cornerRadius:s * 0.04]];
            [p appendPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(s * 0.58, s * 0.18, s * 0.2, s * 0.64) cornerRadius:s * 0.04]];
            break;
        case IconNext:
            tri(s * 0.10, s * 0.50, YES);
            tri(s * 0.46, s * 0.86, YES);
            [p appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(s * 0.84, s * 0.2, s * 0.08, s * 0.6)]];
            break;
        case IconPrev:
            tri(s * 0.50, s * 0.90, NO);
            tri(s * 0.14, s * 0.54, NO);
            [p appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(s * 0.08, s * 0.2, s * 0.08, s * 0.6)]];
            break;
    }
    [p fill];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

typedef NS_ENUM(NSInteger, ModeIcon) { ModeShuffle, ModeRepeat, ModeRepeatOne };

/// 随机 / 循环的线条图标（模板图，颜色由按钮的 tintColor 决定）。
static UIImage *MakeModeIcon(ModeIcon icon, CGFloat s) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
    [[UIColor whiteColor] set];
    UIBezierPath *p = [UIBezierPath bezierPath];
    p.lineWidth = s * 0.075;
    p.lineCapStyle = kCGLineCapRound;
    p.lineJoinStyle = kCGLineJoinRound;
#define P(x, y) CGPointMake(s * (x), s * (y))
    void (^chevron)(CGFloat, CGFloat, CGFloat) = ^(CGFloat tipX, CGFloat y, CGFloat dir) { // dir: 1 朝右，-1 朝左
        [p moveToPoint:P(tipX - dir * 0.12, y - 0.12)];
        [p addLineToPoint:P(tipX, y)];
        [p addLineToPoint:P(tipX - dir * 0.12, y + 0.12)];
    };
    if (icon == ModeShuffle) {
        // 两条交叉的 S 形线，右端带箭头
        [p moveToPoint:P(0.12, 0.30)];
        [p addLineToPoint:P(0.24, 0.30)];
        [p addCurveToPoint:P(0.66, 0.70) controlPoint1:P(0.46, 0.30) controlPoint2:P(0.44, 0.70)];
        [p addLineToPoint:P(0.86, 0.70)];
        chevron(0.88, 0.70, 1);
        [p moveToPoint:P(0.12, 0.70)];
        [p addLineToPoint:P(0.24, 0.70)];
        [p addCurveToPoint:P(0.66, 0.30) controlPoint1:P(0.46, 0.70) controlPoint2:P(0.44, 0.30)];
        [p addLineToPoint:P(0.86, 0.30)];
        chevron(0.88, 0.30, 1);
    } else {
        // 首尾相接的两段圆角折线，各带一个箭头
        [p moveToPoint:P(0.13, 0.54)];
        [p addLineToPoint:P(0.13, 0.46)];
        [p addQuadCurveToPoint:P(0.29, 0.30) controlPoint:P(0.13, 0.30)];
        [p addLineToPoint:P(0.80, 0.30)];
        chevron(0.82, 0.30, 1);
        [p moveToPoint:P(0.87, 0.46)];
        [p addLineToPoint:P(0.87, 0.54)];
        [p addQuadCurveToPoint:P(0.71, 0.70) controlPoint:P(0.87, 0.70)];
        [p addLineToPoint:P(0.20, 0.70)];
        chevron(0.18, 0.70, -1);
    }
    [p stroke];
    if (icon == ModeRepeatOne) {
        NSDictionary *attr = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:s * 0.3],
                               NSForegroundColorAttributeName: [UIColor whiteColor]};
        CGSize sz = [@"1" sizeWithAttributes:attr];
        [@"1" drawAtPoint:CGPointMake((s - sz.width) / 2, (s - sz.height) / 2) withAttributes:attr];
    }
#undef P
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static UIImage *PlaceholderArt(void) {
    static UIImage *img;
    if (img) return img;
    CGFloat s = 600;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), YES, 1);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[(id)RGB(70, 40, 110).CGColor, (id)RGB(200, 50, 90).CGColor];
    CGGradientRef g = CGGradientCreateWithColors(cs, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(ctx, g, CGPointZero, CGPointMake(s, s), 0);
    CGGradientRelease(g);
    CGColorSpaceRelease(cs);
    NSDictionary *attr = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:300],
                           NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.85]};
    CGSize sz = [@"♪" sizeWithAttributes:attr];
    [@"♪" drawAtPoint:CGPointMake((s - sz.width) / 2, (s - sz.height) / 2) withAttributes:attr];
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

static NSString *FormatTime(double t) {
    if (!isfinite(t) || t < 0) t = 0;
    int n = (int)t;
    return [NSString stringWithFormat:@"%d:%02d", n / 60, n % 60];
}

#pragma mark - Player view controller

typedef NS_ENUM(NSInteger, RepeatMode) { RepeatOff, RepeatAll, RepeatOne };

@interface PlayerVC : UIViewController <UITableViewDataSource, UITableViewDelegate>
@end

@implementation PlayerVC {
    // 数据
    NSArray<Track *> *_library, *_files, *_stations, *_queue;
    UIButton *_addStationBtn;
    NSInteger _index;
    BOOL _shuffle, _scrubbing, _wantsPlay, _libraryDenied;
    RepeatMode _repeat;
    AVPlayer *_player;
    id _timeObserver;
    // 界面
    UIView *_side, *_panel;
    UISegmentedControl *_seg;
    UITableView *_table;
    UILabel *_empty, *_titleLabel, *_artistLabel, *_elapsed, *_remain;
    UIImageView *_artView;
    UISlider *_slider;
    UIButton *_playBtn, *_prevBtn, *_nextBtn, *_shuffleBtn, *_repeatBtn;
    MPVolumeView *_volume;
    // Sonos 输出。选中音箱后，本机播放器静音“陪跑”：既让 App 在后台保持存活（内置 HTTP 服务不能停），
    // 也让进度条和锁屏控制照常工作；真正出声的是音箱。
    SonosDevice *_sonos;          // nil = 用 iPad 自己播放（含 AirPlay / 蓝牙）
    NSArray<SonosDevice *> *_sonosDevices; // 后台搜到的音箱，输出菜单直接用
    BOOL _discovering;
    MPVolumeView *_routeView;     // 只为借用它的系统 AirPlay 选择器，本身不可见
    UIButton *_outputBtn;
    UILabel *_status;
    UISlider *_sonosVol;
    NSTimer *_sonosTimer;
    NSUInteger _sonosGen;         // 每次换歌/换输出加一，用来丢弃过期的异步回调
    BOOL _sonosLoaded;            // 音箱上已载入当前这首
    BOOL _sonosStarted;           // 音箱已经开始播放过当前这首
    BOOL _polling;
    NSInteger _pollFailures;
    NSString *_sonosKey;          // 当前这首在内置 HTTP 服务上的路径
    NSDate *_sonosSentAt, *_sonosQuietUntil, *_localEndedAt, *_lastVolSend;
    UIBackgroundTaskIdentifier _bgTask;
}

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = BG;
    self.view.tintColor = ACCENT;
    _index = -1;
    _library = @[];
    _files = @[];
    _queue = @[];

    _side = [UIView new];
    _side.backgroundColor = PANEL;
    [self.view addSubview:_side];

    _seg = [[UISegmentedControl alloc] initWithItems:@[@"资料库", @"文件", @"电台"]];
    _seg.selectedSegmentIndex = 0;
    [_seg addTarget:self action:@selector(sourceChanged) forControlEvents:UIControlEventValueChanged];
    [_side addSubview:_seg];

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.dataSource = self;
    _table.delegate = self;
    _table.backgroundColor = [UIColor clearColor];
    _table.separatorColor = [UIColor colorWithWhite:1 alpha:0.08];
    _table.rowHeight = 60;
    _table.tableFooterView = [UIView new];
    _table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [_side addSubview:_table];

    _empty = [UILabel new];
    _empty.numberOfLines = 0;
    _empty.textAlignment = NSTextAlignmentCenter;
    _empty.textColor = [UIColor colorWithWhite:1 alpha:0.45];
    _empty.font = [UIFont systemFontOfSize:15];
    [_side addSubview:_empty];

    _panel = [UIView new];
    [self.view addSubview:_panel];

    _artView = [[UIImageView alloc] initWithImage:PlaceholderArt()];
    _artView.contentMode = UIViewContentModeScaleAspectFill;
    _artView.clipsToBounds = YES;
    _artView.layer.cornerRadius = 14;
    [_panel addSubview:_artView];

    _titleLabel = [self label:26 bold:YES alpha:1];
    _titleLabel.text = @"未在播放";
    _artistLabel = [self label:18 bold:NO alpha:0.6];
    _artistLabel.text = @"从左侧选择一首歌曲";
    _elapsed = [self label:13 bold:NO alpha:0.6];
    _elapsed.textAlignment = NSTextAlignmentLeft;
    _elapsed.text = @"0:00";
    _remain = [self label:13 bold:NO alpha:0.6];
    _remain.textAlignment = NSTextAlignmentRight;
    _remain.text = @"0:00";

    _slider = [UISlider new];
    _slider.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.2];
    [_slider addTarget:self action:@selector(scrubBegan) forControlEvents:UIControlEventTouchDown];
    [_slider addTarget:self action:@selector(scrubChanged) forControlEvents:UIControlEventValueChanged];
    [_slider addTarget:self action:@selector(scrubEnded)
      forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [_panel addSubview:_slider];

    _prevBtn = [self iconButton:MakeIcon(IconPrev, 44) action:@selector(previous)];
    _playBtn = [self iconButton:MakeIcon(IconPlay, 64) action:@selector(togglePlay)];
    _nextBtn = [self iconButton:MakeIcon(IconNext, 44) action:@selector(next)];
    _prevBtn.tintColor = _playBtn.tintColor = _nextBtn.tintColor = [UIColor whiteColor];
    _shuffleBtn = [self modeButton:@selector(toggleShuffle)];
    _repeatBtn = [self modeButton:@selector(toggleRepeat)];

    _volume = [MPVolumeView new];
    _volume.showsRouteButton = NO; // AirPlay 入口并入下方的“输出”菜单
    [_panel addSubview:_volume];
    _routeView = [MPVolumeView new];
    _routeView.showsVolumeSlider = NO;
    _routeView.alpha = 0;
    _routeView.userInteractionEnabled = NO;
    [_panel addSubview:_routeView];

    _sonosVol = [UISlider new];
    _sonosVol.maximumValue = 100;
    _sonosVol.hidden = YES;
    _sonosVol.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.2];
    [_sonosVol addTarget:self action:@selector(sonosVolumeChanged) forControlEvents:UIControlEventValueChanged];
    [_sonosVol addTarget:self action:@selector(sonosVolumeEnded)
        forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [_panel addSubview:_sonosVol];
    _outputBtn = [self textButton:@selector(chooseOutput)];
    _outputBtn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    _outputBtn.layer.cornerRadius = 17;
    _outputBtn.contentEdgeInsets = UIEdgeInsetsMake(0, 18, 0, 18);
    _sonosDevices = @[];
    [self refreshSonos:nil];
    _status = [self label:13 bold:NO alpha:0.6];
    _status.numberOfLines = 2; // 错误原因可能较长
    _status.adjustsFontSizeToFitWidth = YES;
    _status.minimumScaleFactor = 0.7;
    _bgTask = UIBackgroundTaskInvalid;
    [self updateOutputButton];
    [[NSFileManager defaultManager] removeItemAtPath:[self sonosCacheDir] error:NULL]; // 上次转换的缓存

    _shuffle = [[NSUserDefaults standardUserDefaults] boolForKey:@"shuffle"];
    _repeat = [[NSUserDefaults standardUserDefaults] integerForKey:@"repeat"];
    [self updateModeButtons];

    _addStationBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _addStationBtn.frame = CGRectMake(0, 0, 320, 50);
    _addStationBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    [_addStationBtn setTitle:@"＋ 添加电台" forState:UIControlStateNormal];
    [_addStationBtn addTarget:self action:@selector(addStation) forControlEvents:UIControlEventTouchUpInside];
    [self loadStations];

    [self setupAudio];
    [self loadFiles];
    [self requestLibrary];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(appActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(itemEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [nc addObserver:self selector:@selector(itemFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:nil];
    [nc addObserver:self selector:@selector(interrupted:) name:AVAudioSessionInterruptionNotification object:nil];
    [nc addObserver:self selector:@selector(routeChanged:) name:AVAudioSessionRouteChangeNotification object:nil];
}

- (UILabel *)label:(CGFloat)size bold:(BOOL)bold alpha:(CGFloat)alpha {
    UILabel *l = [UILabel new];
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.textColor = [UIColor colorWithWhite:1 alpha:alpha];
    l.textAlignment = NSTextAlignmentCenter;
    [_panel addSubview:l];
    return l;
}

- (UIButton *)iconButton:(UIImage *)img action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setImage:img forState:UIControlStateNormal];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:b];
    return b;
}

/// 随机 / 循环按钮：线条图标，开启时变成强调色并在下方亮一个小圆点。
- (UIButton *)modeButton:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(0, 0, 48, 48);
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(22, 42, 4, 4)];
    dot.backgroundColor = ACCENT;
    dot.layer.cornerRadius = 2;
    dot.userInteractionEnabled = NO;
    dot.tag = 99;
    [b addSubview:dot];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:b];
    return b;
}

- (UIButton *)textButton:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    b.layer.cornerRadius = 8;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [_panel addSubview:b];
    return b;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    CGFloat top = 20;
    CGFloat sideW = b.size.width > b.size.height ? 360 : 290;
    _side.frame = CGRectMake(0, 0, sideW, b.size.height);
    _seg.frame = CGRectMake(16, top + 12, sideW - 32, 32);
    CGFloat ty = CGRectGetMaxY(_seg.frame) + 12;
    _table.frame = CGRectMake(0, ty, sideW, b.size.height - ty);
    _empty.frame = CGRectInset(_table.frame, 24, 40);

    _panel.frame = CGRectMake(sideW, top, b.size.width - sideW, b.size.height - top);
    CGFloat w = _panel.bounds.size.width, h = _panel.bounds.size.height;
    CGFloat cw = MIN(w - 80, 520);              // 内容列宽
    CGFloat cx = (w - cw) / 2;
    CGFloat controlsH = 390;                    // 封面以下所有控件的高度
    CGFloat art = MAX(160, MIN(cw, h - controlsH - 50));
    CGFloat y = MAX(24, (h - art - controlsH) / 2);
    _artView.frame = CGRectMake((w - art) / 2, y, art, art);
    y += art + 26;
    _titleLabel.frame = CGRectMake(cx, y, cw, 32);
    y += 36;
    _artistLabel.frame = CGRectMake(cx, y, cw, 24);
    y += 40;
    _slider.frame = CGRectMake(cx, y, cw, 30);
    y += 30;
    _elapsed.frame = CGRectMake(cx, y, 80, 18);
    _remain.frame = CGRectMake(cx + cw - 80, y, 80, 18);
    y += 34;
    CGFloat mid = w / 2, cy = y + 36;
    _playBtn.frame = CGRectMake(mid - 40, cy - 40, 80, 80);
    _prevBtn.frame = CGRectMake(mid - 150, cy - 32, 64, 64);
    _nextBtn.frame = CGRectMake(mid + 86, cy - 32, 64, 64);
    _shuffleBtn.frame = CGRectMake(cx, cy - 24, 48, 48);
    _repeatBtn.frame = CGRectMake(cx + cw - 48, cy - 24, 48, 48);
    y += 96;
    _volume.frame = _sonosVol.frame = CGRectMake(cx, y, cw, 30);
    y += 42;
    CGFloat bw = MIN(cw, MAX(160, [_outputBtn sizeThatFits:CGSizeMake(cw, 34)].width));
    _outputBtn.frame = CGRectMake((w - bw) / 2, y, bw, 34);
    _routeView.frame = _outputBtn.frame; // 系统 AirPlay 选择器从这个位置弹出
    y += 38;
    _status.frame = CGRectMake(cx, y, cw, 34);
}

#pragma mark 数据源

- (NSArray<Track *> *)shown {
    NSInteger i = _seg.selectedSegmentIndex;
    return i == 0 ? _library : (i == 1 ? _files : _stations);
}

- (void)sourceChanged {
    if (_seg.selectedSegmentIndex == 1) [self loadFiles];
    [self reloadList];
}

- (void)appActive {
    [self refreshSonos:nil];
    [self updateOutputButton];
    [self loadFiles];
    if (_library.count == 0) [self requestLibrary];
}

- (void)reloadList {
    [_table reloadData];
    NSArray *list = [self shown];
    _empty.hidden = list.count > 0;
    if (_seg.selectedSegmentIndex == 0)
        _empty.text = _libraryDenied ? @"没有访问音乐资料库的权限。\n请在 设置 › 隐私 › 媒体与 Apple Music 中允许。"
                                     : @"资料库里没有可播放的歌曲。\n\n可以用电脑同步音乐到这台 iPad，或切换到“文件”标签。";
    else if (_seg.selectedSegmentIndex == 1)
        _empty.text = @"还没有音频文件。\n\n用数据线连接电脑，在 访达 / iTunes 的“文件共享”里把 mp3、m4a、wav 等文件拖进“音乐播放器”。";
    else
        _empty.text = @"还没有电台。\n\n点上方的“添加电台”，填入电台名称和它的音频流地址。";
    _table.tableHeaderView = _seg.selectedSegmentIndex == 2 ? _addStationBtn : nil;
    [self highlightCurrent];
}

- (void)requestLibrary {
    [MPMediaLibrary requestAuthorization:^(MPMediaLibraryAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_libraryDenied = status != MPMediaLibraryAuthorizationStatusAuthorized;
            if (!self->_libraryDenied) [self loadLibrary];
            [self reloadList];
        });
    }];
}

- (void)loadLibrary {
    NSMutableArray *out = [NSMutableArray array];
    for (MPMediaItem *it in [MPMediaQuery songsQuery].items) {
        if (!it.assetURL) continue; // 受 DRM 保护或仅在云端的歌曲无法用 AVPlayer 播放
        Track *t = [Track new];
        t.title = it.title ?: @"未知歌曲";
        t.artist = it.artist ?: @"未知艺人";
        t.url = it.assetURL;
        t.item = it;
        [out addObject:t];
    }
    _library = out;
}

- (void)loadFiles {
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSSet *exts = [NSSet setWithArray:@[@"mp3", @"m4a", @"aac", @"wav", @"aif", @"aiff", @"caf", @"m4b", @"mp4", @"alac"]];
    NSDictionary *old = [NSDictionary dictionaryWithObjects:_files forKeys:[_files valueForKey:@"url"]];
    NSMutableArray *out = [NSMutableArray array];
    NSDirectoryEnumerator *en = [[NSFileManager defaultManager] enumeratorAtPath:dir];
    for (NSString *rel in en) {
        if ([rel hasPrefix:@"."] || ![exts containsObject:rel.pathExtension.lowercaseString]) continue;
        NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:rel]];
        Track *t = old[url];
        if (!t) {
            t = [Track new];
            t.title = rel.lastPathComponent.stringByDeletingPathExtension;
            t.artist = @"";
            t.url = url;
            [self loadMetadata:t];
        }
        [out addObject:t];
    }
    [out sortUsingComparator:^NSComparisonResult(Track *a, Track *b) {
        return [a.url.path localizedStandardCompare:b.url.path];
    }];
    _files = out;
    if (_seg.selectedSegmentIndex == 1) [self reloadList];
}

- (void)loadMetadata:(Track *)t {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:t.url options:nil];
    [asset loadValuesAsynchronouslyForKeys:@[@"commonMetadata"] completionHandler:^{
        NSString *title = nil, *artist = nil;
        UIImage *art = nil;
        for (AVMetadataItem *m in asset.commonMetadata) {
            if ([m.commonKey isEqual:AVMetadataCommonKeyTitle]) title = m.stringValue;
            else if ([m.commonKey isEqual:AVMetadataCommonKeyArtist]) artist = m.stringValue;
            else if ([m.commonKey isEqual:AVMetadataCommonKeyArtwork] && m.dataValue) art = [UIImage imageWithData:m.dataValue];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (title.length) t.title = title;
            if (artist.length) t.artist = artist;
            if (art) t.art = art; // 没有内嵌封面时保留可能已从网上取到的
            else if (title.length || artist.length) t.artTried = NO; // 有了准确的歌名，值得再搜一次
            if (self->_seg.selectedSegmentIndex == 1) [self->_table reloadData], [self highlightCurrent];
            if (t == [self current]) [self showCurrent];
        });
    }];
}

#pragma mark 电台

- (Track *)stationNamed:(NSString *)name url:(NSString *)url {
    Track *t = [Track new];
    t.title = name;
    t.artist = @"网络电台";
    t.url = [NSURL URLWithString:url];
    t.stream = YES;
    return t.url ? t : nil;
}

/// 预置电台。地址都实测过可连接，且全程是 http（老系统对新的 https 证书支持不好）。
- (NSArray<NSDictionary *> *)presetStations {
    NSString *rf = @"http://icecast.radiofrance.fr/", *rp = @"http://stream.radioparadise.com/", *linn = @"http://radio.linn.co.uk:";
    NSArray *rows = @[
        // 古典
        @[@"Linn Classical（古典 · 320k）", [linn stringByAppendingString:@"8004/autodj"]],
        @[@"BR‑Klassik（古典 · 256k）", @"http://dispatcher.rndfnk.com/br/brklassik/live/mp3/high"],
        @[@"WDR 3（古典/文化 · 256k）", @"http://wdr-wdr3-live.icecast.wdr.de/wdr/wdr3/live/mp3/256/stream.mp3"],
        @[@"France Musique（古典 · 192k）", [rf stringByAppendingString:@"francemusique-hifi.aac"]],
        @[@"France Musique Classique Plus（古典 · 192k）", [rf stringByAppendingString:@"francemusiqueclassiqueplus-hifi.aac"]],
        @[@"France Musique Baroque（巴洛克 · 192k）", [rf stringByAppendingString:@"francemusiquebaroque-hifi.aac"]],
        @[@"NPO Klassiek（古典 · 192k）", @"http://icecast.omroep.nl/radio4-bb-mp3"],
        @[@"Radio Swiss Classic（古典）", @"http://stream.srg-ssr.ch/m/rsc_de/mp3_128"],
        @[@"Klara（古典）", @"http://icecast.vrtcdn.be/klara-high.mp3"],
        @[@"Classic FM（古典 · 英国）", @"http://media-ice.musicradio.com/ClassicFMMP3"],
        @[@"WQXR（古典 · 纽约）", @"http://stream.wqxr.org/wqxr"],
        @[@"WFMT（古典 · 芝加哥）", @"http://wfmt.streamguys1.com/main-mp3"],
        @[@"香港电台第四台（古典）", @"http://stm.rthk.hk/radio4"],
        // 爵士
        @[@"Linn Jazz（爵士 · 320k）", [linn stringByAppendingString:@"8000/autodj"]],
        @[@"FIP Jazz（爵士 · 192k）", [rf stringByAppendingString:@"fipjazz-hifi.aac"]],
        @[@"TSF Jazz（爵士 · 巴黎）", @"http://tsfjazz.ice.infomaniak.ch/tsfjazz-high.mp3"],
        @[@"Radio Swiss Jazz（爵士）", @"http://stream.srg-ssr.ch/m/rsj/mp3_128"],
        // 综合与其他
        @[@"Radio Paradise（综合 · 320k）", [rp stringByAppendingString:@"mp3-320"]],
        @[@"Radio Paradise Mellow（舒缓 · 320k）", [rp stringByAppendingString:@"mellow-320"]],
        @[@"Radio Paradise Global（世界音乐 · 320k）", [rp stringByAppendingString:@"global-320"]],
        @[@"Radio Paradise Rock（摇滚 · 320k）", [rp stringByAppendingString:@"rock-320"]],
        @[@"Linn Radio（综合 · 320k）", [linn stringByAppendingString:@"8003/autodj"]],
        @[@"FIP（综合 · 192k）", [rf stringByAppendingString:@"fip-hifi.aac"]],
        @[@"FIP Monde（世界音乐 · 192k）", [rf stringByAppendingString:@"fipworld-hifi.aac"]],
        @[@"KEXP（独立音乐 · 西雅图）", @"http://live-mp3-128.kexp.org/kexp128.mp3"],
        @[@"Radio Swiss Pop（流行）", @"http://stream.srg-ssr.ch/m/rsp/mp3_128"],
        @[@"香港电台第二台（粤语流行）", @"http://stm.rthk.hk/radio2"],
    ];
    NSMutableArray *out = [NSMutableArray array];
    for (NSArray *r in rows) [out addObject:@{@"name": r[0], @"url": r[1]}];
    return out;
}

- (void)loadStations {
    static const NSInteger kPresetVersion = 2; // 预置列表有新增时加一，已有用户会补上新电台（不会恢复他们删掉的旧电台）
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSArray *presets = [self presetStations];
    NSArray *saved = [ud arrayForKey:@"stations"];
    if (saved && [ud integerForKey:@"stationPresetVersion"] < kPresetVersion) {
        NSSet *have = [NSSet setWithArray:[saved valueForKey:@"url"]];
        NSMutableArray *merged = [saved mutableCopy];
        for (NSDictionary *d in presets)
            if (![have containsObject:d[@"url"]]) [merged addObject:d];
        saved = merged;
        [ud setObject:saved forKey:@"stations"];
    }
    [ud setInteger:kPresetVersion forKey:@"stationPresetVersion"];
    if (!saved) saved = presets; // 没改动过列表的用户始终用最新的预置
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *d in saved) {
        Track *t = [d isKindOfClass:[NSDictionary class]] ? [self stationNamed:d[@"name"] url:d[@"url"]] : nil;
        if (t) [out addObject:t];
    }
    _stations = out;
}

- (void)saveStations {
    NSMutableArray *out = [NSMutableArray array];
    for (Track *t in _stations) [out addObject:@{@"name": t.title, @"url": t.url.absoluteString}];
    [[NSUserDefaults standardUserDefaults] setObject:out forKey:@"stations"];
}

- (void)addStation {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"添加电台"
                                                                message:@"填入电台的音频流地址（mp3 / AAC / m3u8，也可以是 .pls 或 .m3u 播放列表）"
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"名称"; }];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder = @"http://…";
        f.keyboardType = UIKeyboardTypeURL;
        f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        f.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"添加" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
        NSString *name = [ac.textFields[0].text stringByTrimmingCharactersInSet:ws];
        NSString *url = [ac.textFields[1].text stringByTrimmingCharactersInSet:ws];
        NSURL *u = [NSURL URLWithString:url];
        if (!u.host.length || !([u.scheme isEqual:@"http"] || [u.scheme isEqual:@"https"])) {
            self->_status.text = @"电台地址需要以 http:// 或 https:// 开头";
            return;
        }
        if (!name.length) name = u.host;
        NSString *ext = u.pathExtension.lowercaseString;
        if (![ext isEqual:@"pls"] && ![ext isEqual:@"m3u"]) {
            [self insertStation:name url:url];
            return;
        }
        // .pls / .m3u 只是一个写着真实流地址的小文本，取出里面的第一个地址
        self->_status.text = @"正在读取播放列表…";
        [[[NSURLSession sharedSession] dataTaskWithURL:u completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
            NSString *text = data.length < 100000 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
            NSRange m = text ? [text rangeOfString:@"https?://[^\\s\"']+" options:NSRegularExpressionSearch] : NSMakeRange(NSNotFound, 0);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (m.location == NSNotFound) {
                    self->_status.text = @"没能从播放列表里读出流地址";
                    return;
                }
                self->_status.text = @"";
                [self insertStation:name url:[text substringWithRange:m]];
            });
        }] resume];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)insertStation:(NSString *)name url:(NSString *)url {
    Track *t = [self stationNamed:name url:url];
    if (!t) {
        _status.text = @"这个电台地址无效";
        return;
    }
    _stations = [_stations arrayByAddingObject:t];
    [self saveStations];
    if (_seg.selectedSegmentIndex == 2) [self reloadList];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    // 电台流里夹带的“正在播放”信息（ICY StreamTitle）
    NSString *now = nil;
    for (AVMetadataItem *m in _player.currentItem.timedMetadata)
        if ([m.value isKindOfClass:[NSString class]] && [(NSString *)m.value length]) now = (NSString *)m.value;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (now && [self current].stream && !self->_sonos) self->_artistLabel.text = now;
    });
}

#pragma mark 列表

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return [self shown].count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
        c.backgroundColor = [UIColor clearColor];
        c.textLabel.font = [UIFont systemFontOfSize:17];
        c.detailTextLabel.font = [UIFont systemFontOfSize:13];
        c.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:0.5];
        UIView *sel = [UIView new];
        sel.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
        c.selectedBackgroundView = sel;
    }
    Track *t = [self shown][ip.row];
    c.textLabel.text = t.title;
    c.detailTextLabel.text = t.artist.length ? t.artist : @" ";
    c.textLabel.textColor = t == [self current] ? ACCENT : [UIColor whiteColor];
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    _queue = [[self shown] copy];
    [self playIndex:ip.row];
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip { return _seg.selectedSegmentIndex >= 1; }

- (NSString *)tableView:(UITableView *)tv titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)ip { return @"删除"; }

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    BOOL station = _seg.selectedSegmentIndex == 2;
    Track *t = [self shown][ip.row];
    Track *cur = [self current];
    if (t == cur) {
        [self stop];
        cur = nil;
    }
    NSMutableArray *q = [_queue mutableCopy];
    [q removeObject:t];
    _queue = q;
    _index = cur ? (NSInteger)[q indexOfObject:cur] : -1;
    if (station) {
        NSMutableArray *st = [_stations mutableCopy];
        [st removeObject:t];
        _stations = st;
        [self saveStations];
        [self reloadList];
    } else {
        [[NSFileManager defaultManager] removeItemAtURL:t.url error:NULL];
        [self loadFiles];
    }
}

- (void)highlightCurrent {
    Track *cur = [self current];
    for (UITableViewCell *c in _table.visibleCells) {
        NSIndexPath *ip = [_table indexPathForCell:c];
        if (ip && ip.row < (NSInteger)[self shown].count)
            c.textLabel.textColor = [self shown][ip.row] == cur ? ACCENT : [UIColor whiteColor];
    }
}

#pragma mark 播放

- (void)setupAudio {
    AVAudioSession *s = [AVAudioSession sharedInstance];
    [s setCategory:AVAudioSessionCategoryPlayback error:NULL];
    _player = [AVPlayer new];
    __weak PlayerVC *weakSelf = self;
    _timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 2)
                                                          queue:dispatch_get_main_queue()
                                                     usingBlock:^(CMTime time) { [weakSelf tick]; }];
    [_player addObserver:self forKeyPath:@"currentItem.timedMetadata" options:0 context:NULL]; // 电台正在播的曲目名
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    MPRemoteCommandCenter *cc = [MPRemoteCommandCenter sharedCommandCenter];
    [cc.playCommand addTarget:self action:@selector(remotePlay)];
    [cc.pauseCommand addTarget:self action:@selector(remotePause)];
    [cc.togglePlayPauseCommand addTarget:self action:@selector(remoteToggle)];
    [cc.nextTrackCommand addTarget:self action:@selector(remoteNext)];
    [cc.previousTrackCommand addTarget:self action:@selector(remotePrev)];
    [cc.changePlaybackPositionCommand addTarget:self action:@selector(remoteSeek:)];
}

- (Track *)current { return (_index >= 0 && _index < (NSInteger)_queue.count) ? _queue[_index] : nil; }

- (double)duration {
    CMTime d = _player.currentItem.duration;
    double s = CMTIME_IS_NUMERIC(d) ? CMTimeGetSeconds(d) : 0;
    return isfinite(s) ? s : 0;
}

- (void)playIndex:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)_queue.count) return;
    _index = i;
    Track *t = _queue[i];
    [[AVAudioSession sharedInstance] setActive:YES error:NULL];
    // 电台输出到 Sonos 时由音箱自己拉流，iPad 不需要载入
    [_player replaceCurrentItemWithPlayerItem:(t.stream && _sonos) ? nil : [AVPlayerItem playerItemWithURL:t.url]];
    _wantsPlay = YES;
    if (_sonos) [self sonosStartAt:0];
    else [_player play];
    [self showCurrent];
}

- (void)stop {
    _wantsPlay = NO;
    if (_sonos) {
        _sonosGen++;
        _sonosLoaded = NO;
        _status.text = @"";
        [_sonos stop:nil];
    }
    [_player pause];
    [_player replaceCurrentItemWithPlayerItem:nil];
    _index = -1;
    [self showCurrent];
}

- (void)togglePlay {
    if (![self current]) {
        // 还没选歌：直接从当前列表开始
        NSArray *list = [self shown];
        if (list.count == 0) return;
        _queue = [list copy];
        [self playIndex:_shuffle ? arc4random_uniform((uint32_t)list.count) : 0];
        return;
    }
    BOOL stream = [self current].stream;
    if (stream && !_sonos && !_wantsPlay) {
        [self playIndex:_index]; // 直播流暂停后重新连接，而不是接着播放缓冲里的旧内容
        return;
    }
    _wantsPlay = !_wantsPlay;
    if (_wantsPlay) [[AVAudioSession sharedInstance] setActive:YES error:NULL];
    if (_sonos) {
        _sonosQuietUntil = [NSDate dateWithTimeIntervalSinceNow:2];
        if (!_wantsPlay) {
            if (stream) [_sonos stop:nil]; // 电台不能暂停，只能停止
            else [_sonos pause:nil];
            [_player pause];
        } else if (_sonosLoaded) {
            [_sonos resume:^(NSString *error) {
                if (error) [self sonosFailed:error];
            }];
            [_player play];
        } else {
            [self sonosStartAt:[self position]];
        }
    } else if (_wantsPlay) {
        [_player play];
    } else {
        [_player pause];
    }
    [self updatePlayButton];
    [self updateNowPlaying];
}

- (NSInteger)nextIndexAuto:(BOOL)automatic {
    NSInteger n = _queue.count;
    if (n == 0) return -1;
    if (_shuffle && n > 1) {
        NSInteger r;
        do r = arc4random_uniform((uint32_t)n); while (r == _index);
        return r;
    }
    if (_index + 1 < n) return _index + 1;
    return (automatic && _repeat == RepeatOff) ? -1 : 0;
}

- (void)next {
    NSInteger i = [self nextIndexAuto:NO];
    if (i >= 0) [self playIndex:i];
}

- (void)previous {
    if (![self current]) return;
    if (![self current].stream && (CMTimeGetSeconds(_player.currentTime) > 3 || _queue.count == 1)) {
        [self seekTo:0];
        return;
    }
    [self playIndex:_index > 0 ? _index - 1 : (NSInteger)_queue.count - 1];
}

- (void)itemEnded:(NSNotification *)n {
    if (n.object != _player.currentItem) return;
    if ([self current].stream) { // 直播流不该“播完”，到这里说明连接断了
        _wantsPlay = NO;
        [self updatePlayButton];
        [self updateNowPlaying];
        _artistLabel.text = @"电台连接已断开，点播放重新连接";
        return;
    }
    if (_sonos) {
        // 音箱比本机慢一点：等轮询看到音箱真的停了再切歌，这段时间靠后台任务保活
        _localEndedAt = [NSDate date];
        [self beginBackgroundTask];
        return;
    }
    [self trackEnded];
}

- (void)trackEnded {
    if (_repeat == RepeatOne) {
        if (_sonos) {
            [self playIndex:_index];
        } else {
            [_player seekToTime:kCMTimeZero];
            [_player play];
        }
        return;
    }
    NSInteger i = [self nextIndexAuto:YES];
    if (i >= 0) {
        [self playIndex:i];
    } else {
        _wantsPlay = NO;
        _sonosLoaded = NO;
        [_player pause];
        [_player seekToTime:kCMTimeZero];
        [self updatePlayButton];
        [self updateNowPlaying];
    }
}

- (double)position {
    double t = CMTimeGetSeconds(_player.currentTime);
    return isfinite(t) && t > 0 ? t : 0;
}

- (void)seekTo:(double)seconds {
    if ([self current].stream) { // 直播流不能跳转
        _scrubbing = NO;
        return;
    }
    if (_sonos && _sonosLoaded) {
        _sonosQuietUntil = [NSDate dateWithTimeIntervalSinceNow:2];
        _localEndedAt = nil;
        [_sonos seek:seconds completion:nil];
    }
    [_player seekToTime:CMTimeMakeWithSeconds(seconds, 600) completionHandler:^(BOOL finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_scrubbing = NO;
            [self updateNowPlaying];
        });
    }];
}

- (void)itemFailed:(NSNotification *)n {
    if (n.object != _player.currentItem) return;
    _wantsPlay = NO;
    [self updatePlayButton];
    _artistLabel.text = [self current].stream ? @"无法连接这个电台" : @"无法播放这个文件";
}

- (void)interrupted:(NSNotification *)n {
    NSUInteger type = [n.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (type == AVAudioSessionInterruptionTypeBegan) {
        [_player pause];
    } else if (_wantsPlay) {
        NSUInteger opt = [n.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
        if (opt & AVAudioSessionInterruptionOptionShouldResume) {
            [[AVAudioSession sharedInstance] setActive:YES error:NULL];
            [_player play];
        } else {
            _wantsPlay = NO;
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{ [self updatePlayButton]; });
}

- (void)routeChanged:(NSNotification *)n {
    // 拔掉耳机时暂停
    NSUInteger reason = [n.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateOutputButton]; }); // AirPlay / 蓝牙切换后更新“输出”按钮
    if (reason != AVAudioSessionRouteChangeReasonOldDeviceUnavailable) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_sonos) return; // 声音在音箱上，拔耳机不影响
        self->_wantsPlay = NO;
        [self->_player pause];
        [self updatePlayButton];
        [self updateNowPlaying];
    });
}

#pragma mark Sonos 输出

/// 当前系统音频线路如果是 AirPlay / 蓝牙等外部设备，返回它的名字；用 iPad 自己的扬声器或耳机时返回 nil。
- (NSString *)externalRouteName {
    AVAudioSessionPortDescription *port = [AVAudioSession sharedInstance].currentRoute.outputs.firstObject;
    if (!port) return nil;
    NSArray *builtIn = @[AVAudioSessionPortBuiltInSpeaker, AVAudioSessionPortHeadphones, AVAudioSessionPortBuiltInReceiver];
    return [builtIn containsObject:port.portType] ? nil : port.portName;
}

- (void)updateOutputButton {
    NSString *route = [self externalRouteName];
    NSString *name = _sonos ? _sonos.name : (route ?: @"这台 iPad");
    [_outputBtn setTitle:[@"输出：" stringByAppendingString:name] forState:UIControlStateNormal];
    _outputBtn.tintColor = (_sonos || route) ? ACCENT : [UIColor colorWithWhite:1 alpha:0.75];
    _volume.hidden = _sonos != nil;
    _sonosVol.hidden = _sonos == nil;
    [self.view setNeedsLayout]; // 按钮宽度随标题变化
}

/// 后台搜索 Sonos 音箱并缓存，这样点开输出菜单时不用等。
- (void)refreshSonos:(void (^)(void))done {
    if (_discovering) return;
    _discovering = YES;
    [SonosDevice discoverWithTimeout:2.5 completion:^(NSArray<SonosDevice *> *devices) {
        self->_discovering = NO;
        // 偶尔一次没搜到（UDP 丢包）不清空列表，除非正在用的音箱也该保留
        if (devices.count || !self->_sonos) self->_sonosDevices = devices;
        if (done) done();
    }];
}

/// 统一的输出菜单：iPad 本机、AirPlay / 蓝牙（系统选择器）、Sonos 音箱。
- (void)chooseOutput {
    NSString *route = [self externalRouteName];
    NSString *(^mark)(BOOL, NSString *) = ^(BOOL on, NSString *t) { return on ? [@"✓ " stringByAppendingString:t] : t; };
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"播放到"
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    [ac addAction:[UIAlertAction actionWithTitle:mark(!_sonos && !route, @"这台 iPad") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self setOutput:nil];
        if (route) [self showAirPlayPicker]; // 当前在 AirPlay / 蓝牙上：切回本机要在系统选择器里选
    }]];
    NSString *air = route ? [NSString stringWithFormat:@"AirPlay 与蓝牙：%@", route] : @"AirPlay 与蓝牙…";
    [ac addAction:[UIAlertAction actionWithTitle:mark(!_sonos && route, air) style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self setOutput:nil];
        [self showAirPlayPicker];
    }]];
    for (SonosDevice *d in _sonosDevices) {
        NSString *t = [NSString stringWithFormat:@"%@（%@）", d.name, d.model];
        [ac addAction:[UIAlertAction actionWithTitle:mark([d.ip isEqual:_sonos.ip], t) style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self setOutput:d];
        }]];
    }
    NSString *search = _sonosDevices.count ? @"重新搜索 Sonos 音箱" : @"搜索 Sonos 音箱";
    [ac addAction:[UIAlertAction actionWithTitle:search style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self->_outputBtn setTitle:@"正在搜索 Sonos 音箱…" forState:UIControlStateNormal];
        [self.view setNeedsLayout];
        self->_outputBtn.enabled = NO;
        void (^finish)(void) = ^{
            self->_outputBtn.enabled = YES;
            [self updateOutputButton];
            if (!self->_sonosDevices.count) self->_status.text = @"没有找到 Sonos 音箱，请确认它和 iPad 在同一个 Wi‑Fi";
            [self chooseOutput];
        };
        if (self->_discovering) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), finish);
        else [self refreshSonos:finish];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    ac.popoverPresentationController.sourceView = _outputBtn;
    ac.popoverPresentationController.sourceRect = _outputBtn.bounds;
    [self presentViewController:ac animated:YES completion:nil];
}

/// iOS 10 没有公开的 AirPlay 选择器接口，这里触发隐藏的 MPVolumeView 里的系统线路按钮。
- (void)showAirPlayPicker {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ // 等菜单收起
        for (UIView *v in self->_routeView.subviews) {
            if ([v isKindOfClass:[UIButton class]]) {
                [(UIButton *)v sendActionsForControlEvents:UIControlEventTouchUpInside];
                return;
            }
        }
        self->_status.text = @"无法打开 AirPlay 选择器，可从控制中心切换";
    });
}

- (void)setOutput:(SonosDevice *)device {
    if (device == _sonos || (device && [device.ip isEqual:_sonos.ip])) return;
    double pos = [self position];
    _sonosGen++;
    if (_sonos && _sonosLoaded) [_sonos pause:nil]; // 离开旧音箱时让它停下
    _sonos = device;
    _sonosLoaded = _sonosStarted = NO;
    _localEndedAt = nil;
    _pollFailures = 0;
    _status.text = @"";
    [_sonosTimer invalidate];
    _sonosTimer = nil;
    _player.muted = device != nil;
    [self updateOutputButton];
    if (!device) {
        // 回到 iPad：本机播放器一直在同步陪跑，取消静音即可接上
        if (_wantsPlay && [self current].stream) [self playIndex:_index]; // 电台之前没在本机载入，现在重新连接
        else if (_wantsPlay && [self current]) [_player play];
        [self endBackgroundTask];
        return;
    }
    _sonosTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(sonosPoll) userInfo:nil repeats:YES];
    [device getVolume:^(int v) {
        if (v >= 0 && self->_sonos == device) self->_sonosVol.value = v;
    }];
    if (_wantsPlay && [self current]) [self sonosStartAt:pos];
}

- (NSString *)sonosCacheDir { return [NSTemporaryDirectory() stringByAppendingPathComponent:@"sonos"]; }

/// 把当前这首交给音箱，从 pos 秒处开始。
- (void)sonosStartAt:(double)pos {
    Track *t = [self current];
    SonosDevice *dev = _sonos;
    if (!t || !dev) return;
    NSUInteger gen = ++_sonosGen;
    _sonosLoaded = _sonosStarted = NO;
    _localEndedAt = nil;
    [_player pause]; // 等音箱真正开始后本机再静音跟上
    [self beginBackgroundTask];
    _status.text = @"正在发送到 Sonos…";
    if (t.stream) {
        [_player replaceCurrentItemWithPlayerItem:nil]; // 音箱自己拉流，iPad 不用陪跑
        [dev playRadioURL:t.url.absoluteString title:t.title completion:^(NSString *playError) {
            if (gen != self->_sonosGen) return;
            if (playError) {
                [self sonosFailed:playError];
                return;
            }
            self->_sonosLoaded = YES;
            self->_sonosKey = nil; // 电台地址可能被音箱改写或重定向，不做“被别人换台”的判断
            self->_sonosSentAt = [NSDate date];
            self->_sonosQuietUntil = [NSDate dateWithTimeIntervalSinceNow:2];
            self->_status.text = @"";
            if (!self->_wantsPlay) [dev stop:nil];
            [self endBackgroundTask];
        }];
        return;
    }
    [self sonosFileFor:t completion:^(NSString *path, NSString *error) {
        if (gen != self->_sonosGen) return;
        NSString *url = path ? [[SonosFileServer shared] urlForFile:path] : nil;
        if (!url) {
            [self sonosFailed:error ?: @"无法启动本机的供流服务，请确认 iPad 已连接 Wi‑Fi"];
            return;
        }
        [dev playURL:url completion:^(NSString *playError) {
            if (gen != self->_sonosGen) return;
            if (playError) {
                [self sonosFailed:playError];
                return;
            }
            self->_sonosLoaded = YES;
            self->_sonosKey = [NSURL URLWithString:url].path;
            self->_sonosSentAt = [NSDate date];
            self->_sonosQuietUntil = [NSDate dateWithTimeIntervalSinceNow:2];
            self->_status.text = @"";
            void (^settle)(void) = ^{
                if (gen != self->_sonosGen) return;
                if (self->_wantsPlay) [self->_player play];
                else [dev pause:nil]; // 发送过程中用户按了暂停
            };
            if (pos > 2) [dev seek:pos completion:^(NSString *e) { settle(); }];
            else settle();
        }];
    }];
}

/// 准备一个音箱能直接拉取的文件：“文件”里的歌直接用；资料库里的歌先导出成 m4a。
- (void)sonosFileFor:(Track *)t completion:(void (^)(NSString *path, NSString *error))completion {
    if (!t.item) {
        NSString *ext = t.url.pathExtension;
        if ([SonosFileServer supportsExtension:ext]) completion(t.url.path, nil);
        else completion(nil, [NSString stringWithFormat:@"Sonos 不支持 .%@ 格式", ext]);
        return;
    }
    NSString *dir = [self sonosCacheDir];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *out = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%llu.m4a", t.item.persistentID]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:out]) {
        completion(out, nil);
        return;
    }
    _status.text = @"正在为 Sonos 准备歌曲…";
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:t.url options:nil];
    if (asset.hasProtectedContent) {
        completion(nil, @"这首歌受版权保护（DRM），无法提供给 Sonos");
        return;
    }
    // AAC/ALAC 的 m4a 可以原样导出（快）；其他格式（如 mp3）转成 AAC。原样导出失败时也退回转码。
    BOOL passthrough = [t.url.pathExtension.lowercaseString isEqual:@"m4a"];
    [self exportAsset:asset to:out preset:passthrough ? AVAssetExportPresetPassthrough : AVAssetExportPresetAppleM4A completion:^(NSString *error) {
        if (!error || !passthrough) {
            completion(error ? nil : out, error);
            return;
        }
        [self exportAsset:asset to:out preset:AVAssetExportPresetAppleM4A completion:^(NSString *error2) {
            completion(error2 ? nil : out, error2);
        }];
    }];
}

/// completion 在主线程回调；成功时 error 为 nil，失败时带上系统给出的真实原因。
- (void)exportAsset:(AVAsset *)asset to:(NSString *)out preset:(NSString *)preset completion:(void (^)(NSString *error))completion {
    NSString *tmp = [out stringByAppendingString:@".part.m4a"]; // 完成后再改名，避免半截文件被当成缓存
    [[NSFileManager defaultManager] removeItemAtPath:tmp error:NULL];
    NSString *ext = asset.isExportable ? @"" : @"，系统标记为不可导出";
    AVAssetExportSession *ex = [AVAssetExportSession exportSessionWithAsset:asset presetName:preset];
    if (!ex || ![ex.supportedFileTypes containsObject:AVFileTypeAppleM4A]) {
        completion([NSString stringWithFormat:@"无法导出这首歌（%@ 不支持%@）", ex ? @"m4a 输出" : @"该导出方式", ext]);
        return;
    }
    ex.outputURL = [NSURL fileURLWithPath:tmp];
    ex.outputFileType = AVFileTypeAppleM4A;
    ex.shouldOptimizeForNetworkUse = YES;
    [ex exportAsynchronouslyWithCompletionHandler:^{
        NSError *err = ex.error;
        if (ex.status == AVAssetExportSessionStatusCompleted)
            [[NSFileManager defaultManager] moveItemAtPath:tmp toPath:out error:&err];
        else if (!err)
            err = [NSError errorWithDomain:@"Export" code:ex.status userInfo:nil];
        BOOL ok = [[NSFileManager defaultManager] fileExistsAtPath:out];
        if (!ok) [[NSFileManager defaultManager] removeItemAtPath:tmp error:NULL];
        NSString *reason = [err.userInfo[NSLocalizedFailureReasonErrorKey] length] ? err.localizedFailureReason : err.localizedDescription;
        NSString *msg = ok ? nil : [NSString stringWithFormat:@"导出失败：%@（%@ %ld%@）", reason, err.domain, (long)err.code, ext];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(msg); });
    }];
}

- (void)sonosFailed:(NSString *)error {
    _status.text = [@"Sonos：" stringByAppendingString:error];
    _wantsPlay = NO;
    _sonosLoaded = NO;
    [_player pause];
    [self updatePlayButton];
    [self updateNowPlaying];
    [self endBackgroundTask];
}

/// 每秒问一次音箱的状态：对齐进度、发现播完、跟随别处（如 Sonos App）的暂停/继续。
- (void)sonosPoll {
    SonosDevice *dev = _sonos;
    if (!dev || !_sonosLoaded || _polling) return;
    NSUInteger gen = _sonosGen;
    _polling = YES;
    [dev getStatus:^(NSString *state, double pos, double duration, NSString *uri) {
        self->_polling = NO;
        if (gen != self->_sonosGen || dev != self->_sonos) return;
        if (!state) {
            if (++self->_pollFailures == 5) self->_status.text = @"Sonos：连接不上音箱";
            return;
        }
        if (self->_pollFailures >= 5) self->_status.text = @"";
        self->_pollFailures = 0;
        if (self->_sonosQuietUntil.timeIntervalSinceNow > 0) return; // 刚发过指令，状态还没稳定
        if (uri.length && self->_sonosKey && ![uri containsString:self->_sonosKey]) {
            // 音箱被别的 App 换成了别的内容：这边停下，不去抢
            [self sonosFailed:@"音箱正在播放其他内容"];
            return;
        }
        if ([state isEqual:@"PLAYING"]) {
            self->_sonosStarted = YES;
            if (!self->_wantsPlay) { // 在别处按了继续
                self->_wantsPlay = YES;
                [self updatePlayButton];
            }
            if (!self->_localEndedAt && ![self current].stream) {
                if (self->_player.rate == 0) [self->_player play];
                if (!self->_scrubbing && fabs([self position] - pos) > 1.5)
                    [self->_player seekToTime:CMTimeMakeWithSeconds(pos, 600)];
                [self endBackgroundTask];
            }
        } else if ([state isEqual:@"PAUSED_PLAYBACK"]) {
            if (self->_wantsPlay && self->_sonosStarted) { // 在别处按了暂停
                self->_wantsPlay = NO;
                [self->_player pause];
                [self updatePlayButton];
                [self updateNowPlaying];
            }
        } else if ([state isEqual:@"STOPPED"] && self->_wantsPlay) {
            if (self->_sonosStarted && [self current].stream) { // 电台在别处被停掉，或流断了
                self->_wantsPlay = NO;
                [self updatePlayButton];
                [self updateNowPlaying];
            } else if (self->_sonosStarted) [self trackEnded];
            else if (-self->_sonosSentAt.timeIntervalSinceNow > 15)
                [self sonosFailed:@"音箱没有开始播放（可能连不上 iPad，或不支持这个文件）"];
        }
    }];
}

- (void)sonosVolumeChanged {
    if (_lastVolSend && -_lastVolSend.timeIntervalSinceNow < 0.2) return;
    _lastVolSend = [NSDate date];
    [_sonos setVolume:(int)lroundf(_sonosVol.value)];
}

- (void)sonosVolumeEnded { [_sonos setVolume:(int)lroundf(_sonosVol.value)]; }

- (void)beginBackgroundTask {
    if (_bgTask != UIBackgroundTaskInvalid) return;
    _bgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{ [self endBackgroundTask]; }];
}

- (void)endBackgroundTask {
    if (_bgTask == UIBackgroundTaskInvalid) return;
    [[UIApplication sharedApplication] endBackgroundTask:_bgTask];
    _bgTask = UIBackgroundTaskInvalid;
}

#pragma mark 进度与模式

- (void)tick {
    if (_scrubbing) return;
    double d = [self duration], t = CMTimeGetSeconds(_player.currentTime);
    if (!isfinite(t)) t = 0;
    if ([self current].stream) {
        _slider.value = 0;
        _elapsed.text = _player.currentItem ? FormatTime(t) : @"";
        _remain.text = @"直播";
        return;
    }
    _slider.value = d > 0 ? t / d : 0;
    _elapsed.text = FormatTime(t);
    _remain.text = d > 0 ? [@"-" stringByAppendingString:FormatTime(d - t)] : @"0:00";
    NSDictionary *info = [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo;
    if ([self current] && d > 0 && [info[MPMediaItemPropertyPlaybackDuration] doubleValue] != d) [self updateNowPlaying];
}

- (void)scrubBegan { _scrubbing = YES; }

- (void)scrubChanged {
    double d = [self duration];
    _elapsed.text = FormatTime(_slider.value * d);
    _remain.text = [@"-" stringByAppendingString:FormatTime((1 - _slider.value) * d)];
}

- (void)scrubEnded {
    double d = [self duration];
    if (d <= 0) {
        _scrubbing = NO;
        return;
    }
    [self seekTo:_slider.value * d];
}

- (void)toggleShuffle {
    _shuffle = !_shuffle;
    [[NSUserDefaults standardUserDefaults] setBool:_shuffle forKey:@"shuffle"];
    [self updateModeButtons];
}

- (void)toggleRepeat {
    _repeat = (_repeat + 1) % 3;
    [[NSUserDefaults standardUserDefaults] setInteger:_repeat forKey:@"repeat"];
    [self updateModeButtons];
}

- (void)updateModeButtons {
    UIColor *off = [UIColor colorWithWhite:1 alpha:0.45];
    [_shuffleBtn setImage:MakeModeIcon(ModeShuffle, 30) forState:UIControlStateNormal];
    _shuffleBtn.tintColor = _shuffle ? ACCENT : off;
    [_shuffleBtn viewWithTag:99].hidden = !_shuffle;
    _shuffleBtn.accessibilityLabel = _shuffle ? @"随机播放：开" : @"随机播放：关";
    [_repeatBtn setImage:MakeModeIcon(_repeat == RepeatOne ? ModeRepeatOne : ModeRepeat, 30) forState:UIControlStateNormal];
    _repeatBtn.tintColor = _repeat ? ACCENT : off;
    [_repeatBtn viewWithTag:99].hidden = _repeat == RepeatOff;
    _repeatBtn.accessibilityLabel = @[@"循环：关", @"列表循环", @"单曲循环"][_repeat];
}

- (void)updatePlayButton {
    [_playBtn setImage:MakeIcon(_wantsPlay ? IconPause : IconPlay, 64) forState:UIControlStateNormal];
}

- (UIImage *)artFor:(Track *)t {
    if (t.art) return t.art;
    UIImage *img = [t.item.artwork imageWithSize:CGSizeMake(600, 600)];
    return img ?: PlaceholderArt();
}

- (void)showCurrent {
    Track *t = [self current];
    _titleLabel.text = t ? t.title : @"未在播放";
    _artistLabel.text = t ? t.artist : @"从左侧选择一首歌曲";
    _artView.image = t ? [self artFor:t] : PlaceholderArt();
    _slider.enabled = t && !t.stream;
    if (!t) {
        _slider.value = 0;
        _elapsed.text = _remain.text = @"0:00";
    }
    [self updatePlayButton];
    [self highlightCurrent];
    [self updateNowPlaying];
    if (t) [self fetchArtFor:t];
}

#pragma mark 联网封面

/// 歌曲自己没有封面时，按“艺人 + 歌名”到 iTunes Search API 找一张，并缓存到磁盘。
- (void)fetchArtFor:(Track *)t {
    if (t.stream || t.artTried || [self artFor:t] != PlaceholderArt()) return;
    t.artTried = YES;
    NSString *term = [[NSString stringWithFormat:@"%@ %@", t.artist ?: @"", t.title ?: @""]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (term.length < 2) return;

    NSString *dir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"artwork"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *name = [term.lowercaseString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]];
    if (name.length > 150) name = [name substringToIndex:150];
    NSString *file = [dir stringByAppendingPathComponent:[name stringByAppendingString:@".jpg"]];
    UIImage *cached = [UIImage imageWithContentsOfFile:file];
    if (cached) {
        [self setArt:cached for:t];
        return;
    }
    // 不同地区的商店曲库不同（中文歌多在台湾区），依次尝试，找到即停
    NSMutableOrderedSet<NSString *> *countries = [NSMutableOrderedSet orderedSet];
    NSString *local = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
    if (local.length == 2) [countries addObject:local.lowercaseString];
    [countries addObjectsFromArray:@[@"us", @"tw", @"cn"]];
    [self searchArt:term title:t.title countries:countries.array index:0 completion:^(NSData *data) {
        UIImage *img = data ? [UIImage imageWithData:data] : nil;
        if (!img) return;
        [data writeToFile:file atomically:YES];
        [self setArt:img for:t];
    }];
}

- (void)setArt:(UIImage *)img for:(Track *)t {
    t.art = img;
    if (t != [self current]) return;
    [UIView transitionWithView:_artView duration:0.3 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        self->_artView.image = img;
    } completion:nil];
    [self updateNowPlaying]; // 锁屏封面
}

/// completion 在主线程回调；找不到或出错时 data 为 nil。
- (void)searchArt:(NSString *)term title:(NSString *)title countries:(NSArray<NSString *> *)countries index:(NSUInteger)i
       completion:(void (^)(NSData *data))completion {
    if (i >= countries.count) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return;
    }
    NSURLComponents *c = [NSURLComponents componentsWithString:@"https://itunes.apple.com/search"];
    c.queryItems = @[[NSURLQueryItem queryItemWithName:@"term" value:term],
                     [NSURLQueryItem queryItemWithName:@"media" value:@"music"],
                     [NSURLQueryItem queryItemWithName:@"entity" value:@"song"],
                     [NSURLQueryItem queryItemWithName:@"limit" value:@"5"],
                     [NSURLQueryItem queryItemWithName:@"country" value:countries[i]]];
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithURL:c.URL completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
        if (e) { // 没有网络：不再换地区重试
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
            return;
        }
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSArray *results = [json isKindOfClass:[NSDictionary class]] ? json[@"results"] : nil;
        NSDictionary *pick = nil;
        for (NSDictionary *res in [results isKindOfClass:[NSArray class]] ? results : @[]) {
            if (![res isKindOfClass:[NSDictionary class]] || ![res[@"artworkUrl100"] isKindOfClass:[NSString class]]) continue;
            if (!pick) pick = res; // 默认取第一条
            NSString *name = [res[@"trackName"] isKindOfClass:[NSString class]] ? res[@"trackName"] : @"";
            if (title.length && [name rangeOfString:title options:NSCaseInsensitiveSearch].location != NSNotFound) { // 歌名对得上的优先
                pick = res;
                break;
            }
        }
        if (!pick) {
            [self searchArt:term title:title countries:countries index:i + 1 completion:completion];
            return;
        }
        NSString *url = [pick[@"artworkUrl100"] stringByReplacingOccurrencesOfString:@"100x100" withString:@"600x600"];
        [[session dataTaskWithURL:[NSURL URLWithString:url] completionHandler:^(NSData *img, NSURLResponse *r2, NSError *e2) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(e2 ? nil : img); });
        }] resume];
    }] resume];
}

- (void)updateNowPlaying {
    Track *t = [self current];
    if (!t) {
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
        return;
    }
    UIImage *art = [self artFor:t];
    double pos = CMTimeGetSeconds(_player.currentTime);
    NSMutableDictionary *info = [@{
        MPMediaItemPropertyTitle: t.title ?: @"",
        MPMediaItemPropertyArtist: t.artist ?: @"",
        MPMediaItemPropertyPlaybackDuration: @([self duration]),
        MPNowPlayingInfoPropertyElapsedPlaybackTime: @(isfinite(pos) ? pos : 0),
        MPNowPlayingInfoPropertyPlaybackRate: @(_wantsPlay ? 1.0 : 0.0),
    } mutableCopy];
    // initWithBoundsSize: 是 iOS 10 才有的；iOS 9 用旧的 initWithImage:
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
    if ([MPMediaItemArtwork instancesRespondToSelector:@selector(initWithBoundsSize:requestHandler:)])
        info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithBoundsSize:art.size
                                                                           requestHandler:^UIImage *(CGSize size) { return art; }];
    else
        info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithImage:art];
#pragma clang diagnostic pop
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
}

#pragma mark 锁屏 / 控制中心

- (MPRemoteCommandHandlerStatus)remotePlay {
    if (!_wantsPlay) [self togglePlay];
    return MPRemoteCommandHandlerStatusSuccess;
}
- (MPRemoteCommandHandlerStatus)remotePause {
    if (_wantsPlay) [self togglePlay];
    return MPRemoteCommandHandlerStatusSuccess;
}
- (MPRemoteCommandHandlerStatus)remoteToggle {
    [self togglePlay];
    return MPRemoteCommandHandlerStatusSuccess;
}
- (MPRemoteCommandHandlerStatus)remoteNext {
    [self next];
    return MPRemoteCommandHandlerStatusSuccess;
}
- (MPRemoteCommandHandlerStatus)remotePrev {
    [self previous];
    return MPRemoteCommandHandlerStatusSuccess;
}
- (MPRemoteCommandHandlerStatus)remoteSeek:(MPChangePlaybackPositionCommandEvent *)e {
    [self seekTo:e.positionTime];
    return MPRemoteCommandHandlerStatusSuccess;
}

@end

#pragma mark - App

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [PlayerVC new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
