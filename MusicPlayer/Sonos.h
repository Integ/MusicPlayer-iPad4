// Sonos 支持：SSDP 发现、UPnP(SOAP) 控制、以及给音箱供流的内置 HTTP 文件服务。
// 思路与 soco-cli 的 play_file 相同：本机起 HTTP 服务，让音箱来拉取文件。
// 只依赖 Foundation 和 POSIX socket，可在 iOS 10 和 macOS 上编译。
#import <Foundation/Foundation.h>

@interface SonosDevice : NSObject
@property (copy) NSString *ip;
@property (copy) NSString *name;  // 房间名
@property (copy) NSString *model; // 例如 "Sonos Play:5"

/// 在局域网里搜索 Sonos 音箱；completion 在主线程回调。
+ (void)discoverWithTimeout:(NSTimeInterval)timeout completion:(void (^)(NSArray<SonosDevice *> *devices))completion;

// 以下回调都在主线程；error 为 nil 表示成功。
- (void)playURL:(NSString *)url completion:(void (^)(NSString *error))completion;
/// 让音箱自己去拉一个网络电台流（不经过本机）。
- (void)playRadioURL:(NSString *)url title:(NSString *)title completion:(void (^)(NSString *error))completion;
- (void)resume:(void (^)(NSString *error))completion;
- (void)pause:(void (^)(NSString *error))completion;
- (void)stop:(void (^)(NSString *error))completion;
- (void)seek:(double)seconds completion:(void (^)(NSString *error))completion;
/// state: PLAYING / PAUSED_PLAYBACK / STOPPED / TRANSITIONING；失败时为 nil。
- (void)getStatus:(void (^)(NSString *state, double position, double duration, NSString *uri))completion;
- (void)getVolume:(void (^)(int volume))completion; // 失败时为 -1
- (void)setVolume:(int)volume;
@end

@interface SonosFileServer : NSObject
+ (instancetype)shared;
/// 启动（可重复调用）。失败返回 NO。
- (BOOL)start;
/// 登记一个本地文件，返回音箱可访问的 http 地址；无法确定本机 IP 时返回 nil。
- (NSString *)urlForFile:(NSString *)path;
/// 音箱能否解码这种扩展名。
+ (BOOL)supportsExtension:(NSString *)ext;
/// 本机 Wi‑Fi 的 IPv4 地址。
+ (NSString *)localIP;
@end
