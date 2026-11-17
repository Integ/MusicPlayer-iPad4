// 把 .app 安装到 USB 连接的 iOS 设备（基于 libimobiledevice，适用于 Xcode 已不支持的旧系统）。
// 用法: install <udid> <path/to/App.app>
#include <dirent.h>
#include <libgen.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <libimobiledevice/afc.h>
#include <libimobiledevice/installation_proxy.h>
#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/lockdown.h>

static int done = 0, failed = 0;

static int upload(afc_client_t afc, const char *local, const char *remote) {
    struct stat st;
    if (stat(local, &st) != 0) return -1;
    if (S_ISDIR(st.st_mode)) {
        afc_make_directory(afc, remote);
        DIR *d = opendir(local);
        if (!d) return -1;
        struct dirent *e;
        int rc = 0;
        while (rc == 0 && (e = readdir(d))) {
            if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
            char l[4096], r[4096];
            snprintf(l, sizeof l, "%s/%s", local, e->d_name);
            snprintf(r, sizeof r, "%s/%s", remote, e->d_name);
            rc = upload(afc, l, r);
        }
        closedir(d);
        return rc;
    }
    FILE *f = fopen(local, "rb");
    if (!f) return -1;
    uint64_t h = 0;
    if (afc_file_open(afc, remote, AFC_FOPEN_WRONLY, &h) != AFC_E_SUCCESS) {
        fclose(f);
        return -1;
    }
    char buf[65536];
    size_t n;
    int rc = 0;
    while (rc == 0 && (n = fread(buf, 1, sizeof buf, f)) > 0) {
        uint32_t off = 0;
        while (off < n) {
            uint32_t w = 0;
            if (afc_file_write(afc, h, buf + off, (uint32_t)n - off, &w) != AFC_E_SUCCESS || w == 0) {
                rc = -1;
                break;
            }
            off += w;
        }
    }
    afc_file_close(afc, h);
    fclose(f);
    return rc;
}

static void status_cb(plist_t command, plist_t status, void *user) {
    char *name = NULL, *err = NULL, *desc = NULL;
    uint64_t code = 0;
    instproxy_status_get_name(status, &name);
    instproxy_status_get_error(status, &err, &desc, &code);
    if (err) {
        fprintf(stderr, "安装失败: %s (%s) 0x%llx\n", err, desc ? desc : "", (unsigned long long)code);
        failed = done = 1;
    } else if (name) {
        int pct = -1;
        instproxy_status_get_percent_complete(status, &pct);
        printf("  %s %d%%\n", name, pct);
        if (!strcmp(name, "Complete")) done = 1;
    }
    free(name);
    free(err);
    free(desc);
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <udid> <App.app>\n", argv[0]);
        return 2;
    }
    idevice_t dev = NULL;
    lockdownd_client_t ld = NULL;
    lockdownd_service_descriptor_t svc = NULL;
    afc_client_t afc = NULL;
    instproxy_client_t ip = NULL;

    if (idevice_new(&dev, argv[1]) != IDEVICE_E_SUCCESS) return fprintf(stderr, "找不到设备\n"), 1;
    if (lockdownd_client_new_with_handshake(dev, &ld, "install") != LOCKDOWN_E_SUCCESS)
        return fprintf(stderr, "无法与设备握手（设备需解锁并信任此电脑）\n"), 1;

    if (lockdownd_start_service(ld, AFC_SERVICE_NAME, &svc) != LOCKDOWN_E_SUCCESS ||
        afc_client_new(dev, svc, &afc) != AFC_E_SUCCESS)
        return fprintf(stderr, "无法启动 AFC 服务\n"), 1;
    lockdownd_service_descriptor_free(svc);
    svc = NULL;

    char *path = strdup(argv[2]);
    char remote[1024];
    snprintf(remote, sizeof remote, "PublicStaging/%s", basename(path));
    afc_make_directory(afc, "PublicStaging");
    afc_remove_path_and_contents(afc, remote);
    printf("上传 %s …\n", remote);
    if (upload(afc, argv[2], remote) != 0) return fprintf(stderr, "上传失败\n"), 1;

    if (lockdownd_start_service(ld, INSTPROXY_SERVICE_NAME, &svc) != LOCKDOWN_E_SUCCESS ||
        instproxy_client_new(dev, svc, &ip) != INSTPROXY_E_SUCCESS)
        return fprintf(stderr, "无法启动安装服务\n"), 1;
    lockdownd_service_descriptor_free(svc);
    lockdownd_client_free(ld);

    plist_t opts = instproxy_client_options_new();
    instproxy_client_options_add(opts, "PackageType", "Developer", NULL);
    printf("安装中 …\n");
    if (instproxy_install(ip, remote, opts, status_cb, NULL) != INSTPROXY_E_SUCCESS)
        return fprintf(stderr, "无法发起安装\n"), 1;
    for (int i = 0; !done && i < 1200; i++) usleep(100000);
    instproxy_client_options_free(opts);
    afc_remove_path_and_contents(afc, remote);
    instproxy_client_free(ip);
    afc_client_free(afc);
    idevice_free(dev);
    if (!done) return fprintf(stderr, "安装超时\n"), 1;
    if (failed) return 1;
    printf("安装完成\n");
    return 0;
}
