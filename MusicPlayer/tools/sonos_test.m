// Mac 上的自测：发现音箱、只读查询状态、验证内置 HTTP 服务。不会让音箱播放任何东西。
// 用法: sonos_test <任意本地文件>
#import "../Sonos.h"
int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *file = argc > 1 ? @(argv[1]) : nil;
        if (file) printf("URL %s\n", [[SonosFileServer shared] urlForFile:file].UTF8String);
        printf("localIP %s\n", [SonosFileServer localIP].UTF8String);
        [SonosDevice discoverWithTimeout:3 completion:^(NSArray<SonosDevice *> *devs) {
            printf("found %lu\n", (unsigned long)devs.count);
            dispatch_group_t g = dispatch_group_create();
            for (SonosDevice *d in devs) {
                dispatch_group_enter(g);
                [d getStatus:^(NSString *state, double pos, double dur, NSString *uri) {
                    [d getVolume:^(int v) {
                        printf("%s | %s | %s | state=%s pos=%.0f dur=%.0f vol=%d\n", d.ip.UTF8String, d.name.UTF8String,
                               d.model.UTF8String, state.UTF8String, pos, dur, v);
                        dispatch_group_leave(g);
                    }];
                }];
            }
            dispatch_group_notify(g, dispatch_get_main_queue(), ^{
                if (!file) exit(0);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ exit(0); });
            });
        }];
        [[NSRunLoop mainRunLoop] run];
    }
}
