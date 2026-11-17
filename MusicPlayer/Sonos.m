#import "Sonos.h"
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <netinet/in.h>
#import <netinet/tcp.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <unistd.h>

#pragma mark - 小工具

static NSString *XMLEscape(NSString *s) {
    s = [s stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    s = [s stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    s = [s stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    return [s stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
}

static NSString *XMLUnescape(NSString *s) {
    s = [s stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    s = [s stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    s = [s stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    s = [s stringByReplacingOccurrencesOfString:@"&apos;" withString:@"'"];
    return [s stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
}

/// 取 <tag>…</tag> 的文本内容（第一处）。
static NSString *XMLTag(NSString *xml, NSString *tag) {
    if (!xml) return nil;
    NSString *pattern = [NSString stringWithFormat:@"<%@(?:\\s[^>]*)?>(.*?)</%@>", tag, tag];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                        options:NSRegularExpressionDotMatchesLineSeparators
                                                                          error:NULL];
    NSTextCheckingResult *m = [re firstMatchInString:xml options:0 range:NSMakeRange(0, xml.length)];
    return m ? XMLUnescape([xml substringWithRange:[m rangeAtIndex:1]]) : nil;
}

/// "H:MM:SS" → 秒；无法解析（如 NOT_IMPLEMENTED）返回 0。
static double ParseTime(NSString *s) {
    NSArray<NSString *> *p = [s componentsSeparatedByString:@":"];
    if (p.count != 3) return 0;
    return p[0].doubleValue * 3600 + p[1].doubleValue * 60 + p[2].doubleValue;
}

static NSURLSession *Session(void) {
    static NSURLSession *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *c = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        c.timeoutIntervalForRequest = 5;
        s = [NSURLSession sessionWithConfiguration:c];
    });
    return s;
}

#pragma mark - SonosDevice

static NSString *const kAVTransport = @"AVTransport";
static NSString *const kRendering = @"RenderingControl";

@implementation SonosDevice

- (void)soap:(NSString *)service
      action:(NSString *)action
        args:(NSArray<NSString *> *)args // 名、值交替，顺序有意义
  completion:(void (^)(NSString *xml, NSString *error))completion {
    NSMutableString *body = [NSMutableString string];
    for (NSUInteger i = 0; i + 1 < args.count; i += 2) [body appendFormat:@"<%@>%@</%@>", args[i], XMLEscape(args[i + 1]), args[i]];
    NSString *urn = [NSString stringWithFormat:@"urn:schemas-upnp-org:service:%@:1", service];
    NSString *envelope = [NSString stringWithFormat:
        @"<?xml version=\"1.0\" encoding=\"utf-8\"?>"
        @"<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">"
        @"<s:Body><u:%@ xmlns:u=\"%@\"><InstanceID>0</InstanceID>%@</u:%@></s:Body></s:Envelope>",
        action, urn, body, action];
    NSString *url = [NSString stringWithFormat:@"http://%@:1400/MediaRenderer/%@/Control", self.ip, service];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    req.HTTPMethod = @"POST";
    req.HTTPBody = [envelope dataUsingEncoding:NSUTF8StringEncoding];
    [req setValue:@"text/xml; charset=\"utf-8\"" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"\"%@#%@\"", urn, action] forHTTPHeaderField:@"SOAPACTION"];
    [[Session() dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSString *xml = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        NSString *error = nil;
        NSInteger status = [(NSHTTPURLResponse *)resp statusCode];
        if (err) {
            error = err.localizedDescription;
        } else if (status != 200) {
            NSString *code = XMLTag(xml, @"errorCode");
            error = code ? [NSString stringWithFormat:@"音箱拒绝了 %@（UPnP 错误 %@）", action, code]
                         : [NSString stringWithFormat:@"音箱返回 HTTP %ld", (long)status];
        }
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(error ? nil : xml, error); });
    }] resume];
}

- (void)playURL:(NSString *)url completion:(void (^)(NSString *))completion {
    // 与 soco 的 play_uri 一致：先设置地址（元数据留空），再 Play。
    [self soap:kAVTransport action:@"SetAVTransportURI" args:@[@"CurrentURI", url, @"CurrentURIMetaData", @""]
        completion:^(NSString *xml, NSString *error) {
            if (error) {
                if (completion) completion(error);
                return;
            }
            [self resume:completion];
        }];
}

- (void)playRadioURL:(NSString *)url title:(NSString *)title completion:(void (^)(NSString *))completion {
    // 与 soco 的 play_uri(force_radio=True) 一致：把 http(s):// 换成 x-rincon-mp3radio://，音箱才会按电台流处理；
    // HLS（.m3u8）保持原样。附带一段 DIDL 元数据，Sonos App 里才能显示电台名。
    NSString *uri = url;
    NSRange colon = [url rangeOfString:@":"];
    if (colon.location != NSNotFound && ![[NSURL URLWithString:url].pathExtension.lowercaseString isEqual:@"m3u8"])
        uri = [@"x-rincon-mp3radio" stringByAppendingString:[url substringFromIndex:colon.location]];
    NSString *didl = [NSString stringWithFormat:
        @"<DIDL-Lite xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\" "
        @"xmlns:r=\"urn:schemas-rinconnetworks-com:metadata-1-0/\" xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\">"
        @"<item id=\"R:0/0/0\" parentID=\"R:0/0\" restricted=\"true\"><dc:title>%@</dc:title>"
        @"<upnp:class>object.item.audioItem.audioBroadcast</upnp:class>"
        @"<desc id=\"cdudn\" nameSpace=\"urn:schemas-rinconnetworks-com:metadata-1-0/\">SA_RINCON65031_</desc></item></DIDL-Lite>",
        XMLEscape(title ?: @"")];
    void (^then)(NSString *, NSString *) = ^(NSString *xml, NSString *error) {
        if (error) {
            if (completion) completion(error);
            return;
        }
        [self resume:completion];
    };
    [self soap:kAVTransport action:@"SetAVTransportURI" args:@[@"CurrentURI", uri, @"CurrentURIMetaData", didl]
        completion:^(NSString *xml, NSString *error) {
            if (!error) {
                then(xml, nil);
                return;
            }
            // 元数据不被接受时退回不带元数据的方式
            [self soap:kAVTransport action:@"SetAVTransportURI" args:@[@"CurrentURI", uri, @"CurrentURIMetaData", @""] completion:then];
        }];
}

- (void)resume:(void (^)(NSString *))completion {
    [self soap:kAVTransport action:@"Play" args:@[@"Speed", @"1"] completion:^(NSString *xml, NSString *error) {
        if (completion) completion(error);
    }];
}

- (void)pause:(void (^)(NSString *))completion {
    [self soap:kAVTransport action:@"Pause" args:@[] completion:^(NSString *xml, NSString *error) {
        if (completion) completion(error);
    }];
}

- (void)stop:(void (^)(NSString *))completion {
    [self soap:kAVTransport action:@"Stop" args:@[] completion:^(NSString *xml, NSString *error) {
        if (completion) completion(error);
    }];
}

- (void)seek:(double)seconds completion:(void (^)(NSString *))completion {
    int t = (int)MAX(0, seconds);
    NSString *target = [NSString stringWithFormat:@"%d:%02d:%02d", t / 3600, (t / 60) % 60, t % 60];
    [self soap:kAVTransport action:@"Seek" args:@[@"Unit", @"REL_TIME", @"Target", target]
        completion:^(NSString *xml, NSString *error) {
            if (completion) completion(error);
        }];
}

- (void)getStatus:(void (^)(NSString *, double, double, NSString *))completion {
    [self soap:kAVTransport action:@"GetTransportInfo" args:@[] completion:^(NSString *xml, NSString *error) {
        NSString *state = XMLTag(xml, @"CurrentTransportState");
        if (!state) {
            completion(nil, 0, 0, nil);
            return;
        }
        [self soap:kAVTransport action:@"GetPositionInfo" args:@[] completion:^(NSString *xml2, NSString *error2) {
            completion(state, ParseTime(XMLTag(xml2, @"RelTime")), ParseTime(XMLTag(xml2, @"TrackDuration")),
                       XMLTag(xml2, @"TrackURI"));
        }];
    }];
}

- (void)getVolume:(void (^)(int))completion {
    [self soap:kRendering action:@"GetVolume" args:@[@"Channel", @"Master"] completion:^(NSString *xml, NSString *error) {
        NSString *v = XMLTag(xml, @"CurrentVolume");
        completion(v ? v.intValue : -1);
    }];
}

- (void)setVolume:(int)volume {
    volume = MAX(0, MIN(100, volume));
    [self soap:kRendering action:@"SetVolume"
          args:@[@"Channel", @"Master", @"DesiredVolume", [NSString stringWithFormat:@"%d", volume]]
        completion:nil];
}

#pragma mark 发现

+ (void)discoverWithTimeout:(NSTimeInterval)timeout completion:(void (^)(NSArray<SonosDevice *> *))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableOrderedSet<NSString *> *ips = [NSMutableOrderedSet orderedSet];
        int fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (fd >= 0) {
            int on = 1;
            setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, sizeof on);
            unsigned char ttl = 2;
            setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, sizeof ttl);
            NSString *local = [SonosFileServer localIP];
            if (local) { // 多网卡时确保从 Wi‑Fi 发出
                struct in_addr a;
                inet_pton(AF_INET, local.UTF8String, &a);
                setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &a, sizeof a);
            }
            // 用接收超时代替 select()：新 SDK 的 FD_SET 会引用 iOS 10 上不存在的符号
            struct timeval tv = {0, 200000};
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
            const char *msg = "M-SEARCH * HTTP/1.1\r\n"
                              "HOST: 239.255.255.250:1900\r\n"
                              "MAN: \"ssdp:discover\"\r\n"
                              "MX: 1\r\n"
                              "ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n";
            struct sockaddr_in dst = {0};
            dst.sin_family = AF_INET;
            dst.sin_port = htons(1900);
            NSDate *end = [NSDate dateWithTimeIntervalSinceNow:timeout];
            NSDate *nextSend = [NSDate date];
            while ([end timeIntervalSinceNow] > 0) {
                if ([nextSend timeIntervalSinceNow] <= 0) { // UDP 会丢包，每秒重发；组播和广播各发一份
                    inet_pton(AF_INET, "239.255.255.250", &dst.sin_addr);
                    sendto(fd, msg, strlen(msg), 0, (struct sockaddr *)&dst, sizeof dst);
                    dst.sin_addr.s_addr = htonl(INADDR_BROADCAST);
                    sendto(fd, msg, strlen(msg), 0, (struct sockaddr *)&dst, sizeof dst);
                    nextSend = [NSDate dateWithTimeIntervalSinceNow:1];
                }
                char buf[2048];
                struct sockaddr_in from;
                socklen_t len = sizeof from;
                ssize_t n = recvfrom(fd, buf, sizeof buf - 1, 0, (struct sockaddr *)&from, &len);
                if (n <= 0) continue;
                buf[n] = 0;
                if (!strstr(buf, "Sonos") && !strstr(buf, "ZonePlayer")) continue;
                char ip[INET_ADDRSTRLEN];
                inet_ntop(AF_INET, &from.sin_addr, ip, sizeof ip);
                [ips addObject:@(ip)];
            }
            close(fd);
        }

        NSMutableArray<SonosDevice *> *out = [NSMutableArray array];
        dispatch_group_t group = dispatch_group_create();
        for (NSString *ip in ips) {
            SonosDevice *d = [SonosDevice new];
            d.ip = ip;
            d.name = ip;
            d.model = @"Sonos";
            [out addObject:d];
            NSURL *u = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@:1400/xml/device_description.xml", ip]];
            dispatch_group_enter(group);
            [[Session() dataTaskWithURL:u completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
                NSString *xml = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
                NSString *room = XMLTag(xml, @"roomName"), *model = XMLTag(xml, @"modelName");
                if (room.length) d.name = room;
                if (model.length) d.model = model;
                dispatch_group_leave(group);
            }] resume];
        }
        dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC));
        [out sortUsingComparator:^NSComparisonResult(SonosDevice *a, SonosDevice *b) { return [a.name compare:b.name]; }];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(out); });
    });
}

@end

#pragma mark - SonosFileServer

@implementation SonosFileServer {
    int _listenFd;
    int _port;
    NSMutableDictionary<NSString *, NSString *> *_files; // URL 路径 → 本地文件
    NSUInteger _nextId;
}

+ (instancetype)shared {
    static SonosFileServer *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [SonosFileServer new];
        s->_listenFd = -1;
        s->_files = [NSMutableDictionary dictionary];
    });
    return s;
}

+ (NSDictionary<NSString *, NSString *> *)mimeTypes {
    return @{@"mp3": @"audio/mpeg", @"m4a": @"audio/mp4", @"m4b": @"audio/mp4", @"mp4": @"audio/mp4",
             @"aac": @"audio/aac", @"wav": @"audio/wav", @"aif": @"audio/aiff", @"aiff": @"audio/aiff",
             @"flac": @"audio/flac", @"ogg": @"application/ogg", @"wma": @"audio/x-ms-wma"};
}

+ (BOOL)supportsExtension:(NSString *)ext { return [self mimeTypes][ext.lowercaseString] != nil; }

+ (NSString *)localIP {
    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) != 0) return nil;
    NSString *best = nil;
    for (struct ifaddrs *i = list; i; i = i->ifa_next) {
        if (!i->ifa_addr || i->ifa_addr->sa_family != AF_INET) continue;
        if (!(i->ifa_flags & IFF_UP) || (i->ifa_flags & IFF_LOOPBACK)) continue;
        char ip[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &((struct sockaddr_in *)i->ifa_addr)->sin_addr, ip, sizeof ip);
        if (!strncmp(ip, "169.254.", 8)) continue;
        if (!strcmp(i->ifa_name, "en0")) { // iPad 的 Wi‑Fi
            best = @(ip);
            break;
        }
        if (!best) best = @(ip);
    }
    freeifaddrs(list);
    return best;
}

- (BOOL)start {
    @synchronized(self) {
        if (_listenFd >= 0) return YES;
        int fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0) return NO;
        int on = 1;
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof on);
        struct sockaddr_in a = {0};
        a.sin_family = AF_INET;
        a.sin_addr.s_addr = htonl(INADDR_ANY);
        BOOL bound = NO;
        for (int port = 54000; port <= 54099 && !bound; port++) { // 与 soco-cli 相同的端口段
            a.sin_port = htons(port);
            if (bind(fd, (struct sockaddr *)&a, sizeof a) == 0) {
                bound = YES;
                _port = port;
            }
        }
        if (!bound || listen(fd, 8) != 0) {
            close(fd);
            return NO;
        }
        _listenFd = fd;
        [NSThread detachNewThreadSelector:@selector(acceptLoop:) toTarget:self withObject:@(fd)];
        return YES;
    }
}

- (NSString *)urlForFile:(NSString *)path {
    NSString *ip = [SonosFileServer localIP];
    if (!ip || ![self start]) return nil;
    @synchronized(self) {
        // 路径里只用数字和扩展名，避免文件名里的特殊字符给音箱带来麻烦
        NSString *key = [NSString stringWithFormat:@"/m/%lu/track.%@", (unsigned long)++_nextId, path.pathExtension.lowercaseString];
        _files[key] = path;
        if (_files.count > 50) [_files removeObjectForKey:[_files.allKeys sortedArrayUsingSelector:@selector(compare:)].firstObject];
        return [NSString stringWithFormat:@"http://%@:%d%@", ip, _port, key];
    }
}

- (void)acceptLoop:(NSNumber *)fdNumber {
    int fd = fdNumber.intValue;
    for (;;) {
        int c = accept(fd, NULL, NULL);
        if (c < 0) {
            if (errno == EINTR) continue;
            usleep(200000); // 例如进程被挂起后恢复；稍等再试
            continue;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [self handle:c];
            close(c);
        });
    }
}

static BOOL SendAll(int fd, const void *buf, size_t len) {
    const char *p = buf;
    while (len > 0) {
        ssize_t n = send(fd, p, len, 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return NO;
        p += n;
        len -= (size_t)n;
    }
    return YES;
}

static void SendStatus(int fd, const char *status) {
    char buf[160];
    int n = snprintf(buf, sizeof buf, "HTTP/1.1 %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", status);
    SendAll(fd, buf, (size_t)n);
}

- (void)handle:(int)fd {
    int on = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
    struct timeval tv = {30, 0};
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);

    char req[8192];
    size_t got = 0;
    while (got < sizeof req - 1) {
        ssize_t n = recv(fd, req + got, sizeof req - 1 - got, 0);
        if (n <= 0) return;
        got += (size_t)n;
        req[got] = 0;
        if (strstr(req, "\r\n\r\n")) break;
    }
    char method[8] = "", path[512] = "";
    if (sscanf(req, "%7s %511s", method, path) != 2) return SendStatus(fd, "400 Bad Request");
    BOOL head = !strcmp(method, "HEAD");
    if (!head && strcmp(method, "GET")) return SendStatus(fd, "405 Method Not Allowed");

    NSString *file;
    @synchronized(self) { file = _files[@(path)]; }
    FILE *f = file ? fopen(file.fileSystemRepresentation, "rb") : NULL;
    if (!f) return SendStatus(fd, "404 Not Found");
    struct stat st;
    fstat(fileno(f), &st);
    long long size = st.st_size, start = 0, end = size - 1;

    // Range: bytes=a-b / a- / -n
    BOOL partial = NO;
    char *r = strcasestr(req, "\r\nRange:");
    if (r && (r = strstr(r, "bytes="))) {
        r += 6;
        long long a = -1, b = -1;
        if (*r == '-') {
            b = atoll(r + 1);
            if (b > 0) {
                start = MAX(0, size - b);
                partial = YES;
            }
        } else {
            a = atoll(r);
            char *dash = strchr(r, '-');
            if (dash && dash[1] >= '0' && dash[1] <= '9') b = atoll(dash + 1);
            if (a >= size) {
                char hdr[160];
                int n = snprintf(hdr, sizeof hdr, "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */%lld\r\n"
                                                  "Content-Length: 0\r\nConnection: close\r\n\r\n", size);
                SendAll(fd, hdr, (size_t)n);
                fclose(f);
                return;
            }
            start = a;
            if (b >= a && b < size) end = b;
            partial = YES;
        }
    }

    NSString *mime = [SonosFileServer mimeTypes][file.pathExtension.lowercaseString] ?: @"application/octet-stream";
    char hdr[512];
    int n = snprintf(hdr, sizeof hdr, "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %lld\r\nAccept-Ranges: bytes\r\n",
                     partial ? "206 Partial Content" : "200 OK", mime.UTF8String, end - start + 1);
    if (partial) n += snprintf(hdr + n, sizeof hdr - (size_t)n, "Content-Range: bytes %lld-%lld/%lld\r\n", start, end, size);
    n += snprintf(hdr + n, sizeof hdr - (size_t)n, "Connection: close\r\n\r\n");
    if (SendAll(fd, hdr, (size_t)n) && !head) {
        fseeko(f, start, SEEK_SET);
        static const size_t kChunk = 64 * 1024;
        char *buf = malloc(kChunk);
        long long left = end - start + 1;
        while (left > 0) {
            size_t want = (size_t)MIN((long long)kChunk, left);
            size_t rd = fread(buf, 1, want, f);
            if (rd == 0 || !SendAll(fd, buf, rd)) break;
            left -= (long long)rd;
        }
        free(buf);
    }
    fclose(f);
}

@end
