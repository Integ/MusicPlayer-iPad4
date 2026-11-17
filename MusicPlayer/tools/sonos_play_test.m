// Mac 上的实播测试：让指定音箱播放一个本地文件，中途跳转、暂停、继续，直到播完。
// 用法: sonos_play_test <音箱IP> <音频文件>
#import "../Sonos.h"
int main(int argc, char **argv) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IOLBF, 0);
        SonosDevice *d = [SonosDevice new];
        d.ip = @(argv[1]);
        NSString *url = [[SonosFileServer shared] urlForFile:@(argv[2])];
        NSString *key = [NSURL URLWithString:url].path;
        printf("url %s\n", url.UTF8String);
        __block int n = 0;
        __block BOOL started = NO;
        [d playURL:url completion:^(NSString *error) {
            printf("playURL -> %s\n", error ? error.UTF8String : "ok");
            if (error) exit(1);
            [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *t) {
                n++;
                if (n == 5) [d seek:12 completion:^(NSString *e) { printf("  seek 12 -> %s\n", e ? e.UTF8String : "ok"); }];
                if (n == 9) [d pause:^(NSString *e) { printf("  pause -> %s\n", e ? e.UTF8String : "ok"); }];
                if (n == 12) [d resume:^(NSString *e) { printf("  resume -> %s\n", e ? e.UTF8String : "ok"); }];
                [d getStatus:^(NSString *state, double pos, double dur, NSString *uri) {
                    printf("%2d %-16s pos=%.0f dur=%.0f uriMatch=%d\n", n, state.UTF8String, pos, dur, [uri containsString:key]);
                    if ([state isEqual:@"PLAYING"]) started = YES;
                    if (started && [state isEqual:@"STOPPED"]) { printf("ENDED\n"); exit(0); }
                    if (n > 60) { printf("TIMEOUT\n"); exit(2); }
                }];
            }];
        }];
        [[NSRunLoop mainRunLoop] run];
    }
}
