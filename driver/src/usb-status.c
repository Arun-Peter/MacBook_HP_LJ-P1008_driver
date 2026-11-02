/* P1008 USB presence reporting. GPL-2.0-or-later.
 * Observes IOKit registry events without opening the USB device. Runs as the
 * logged-in user. Changes only this queue's offline reason, never
 * its enabled/paused state, jobs, accepting-jobs flag, URI, or driver.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <cups/cups.h>
#include <cups/ipp.h>
#include <stdbool.h>
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

#define QUEUE "HP_LaserJet_P1008"
#define URI "ipp://localhost/printers/" QUEUE
#define REASON "offline-report"
#define MAX_REASONS 64
static const char *serial;
static bool observe_only;
static bool clearing;
static CFRunLoopTimerRef timer;
static int last_presence = -1;

static CFMutableDictionaryRef matching(void) {
    CFMutableDictionaryRef dict = IOServiceMatching("IOUSBHostDevice");
    CFMutableDictionaryRef props = CFDictionaryCreateMutable(NULL, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    int vid = 0x03f0, pid = 0x4917;
    CFNumberRef v = CFNumberCreate(NULL, kCFNumberIntType, &vid);
    CFNumberRef p = CFNumberCreate(NULL, kCFNumberIntType, &pid);
    CFDictionarySetValue(props, CFSTR("idVendor"), v);
    CFDictionarySetValue(props, CFSTR("idProduct"), p);
    CFDictionarySetValue(dict, CFSTR(kIOPropertyMatchKey), props);
    CFRelease(v); CFRelease(p); CFRelease(props);
    return dict;
}

static bool present(void) {
    io_iterator_t iter = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching(), &iter)
        != KERN_SUCCESS) {
        fprintf(stderr, "USB registry query failed; leaving queue unchanged.\n");
        exit(1);
    }
    io_service_t dev;
    bool found = false;
    while ((dev = IOIteratorNext(iter))) {
        CFTypeRef value = IORegistryEntryCreateCFProperty(dev,
            CFSTR("USB Serial Number"), NULL, 0);
        char buf[256];
        if (value && CFGetTypeID(value) == CFStringGetTypeID() &&
            CFStringGetCString(value, buf, sizeof(buf), kCFStringEncodingUTF8) &&
            !strcmp(buf, serial)) found = true;
        if (value) CFRelease(value);
        IOObjectRelease(dev);
    }
    IOObjectRelease(iter);
    return found;
}

static const char *no_password(const char *prompt, http_t *http,
    const char *method, const char *resource, void *data) { return NULL; }

static ipp_t *request(ipp_op_t op) {
    ipp_t *r = ippNewRequest(op);
    ippAddString(r, IPP_TAG_OPERATION, IPP_TAG_URI, "printer-uri", NULL, URI);
    ippAddString(r, IPP_TAG_OPERATION, IPP_TAG_NAME,
        "requesting-user-name", NULL, cupsUser());
    return r;
}

/* Keep every other reason, including manual pause and printer faults. */
static int merge(const char **old, int n, bool online, const char **out) {
    int count = 0;
    for (int i = 0; i < n; i++) {
        if (!strcmp(old[i], "none") || !strcmp(old[i], REASON)) continue;
        if (count >= MAX_REASONS - 1) return -1;
        out[count++] = old[i];
    }
    if (!online) out[count++] = REASON;
    if (!count) out[count++] = "none";
    return count;
}

static bool set_reasons(const char **reasons, int count) {
    char option[8192] = "printer-state-reasons=";
    size_t used = strlen(option);
    for (int i = 0; i < count; i++) {
        int written = snprintf(option + used, sizeof(option) - used,
            "%s%s", i ? "," : "", reasons[i]);
        if (written < 0 || (size_t)written >= sizeof(option) - used) return false;
        used += (size_t)written;
    }
    /* Use Apple's authorised administration client, with a fixed local server,
     * queue and attribute. No shell, credential storage or root daemon. */
    char *args[] = { "/usr/sbin/lpadmin", "-h", "/private/var/run/cupsd",
        "-p", QUEUE, "-o", option, NULL };
    extern char **environ;
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    pid_t pid;
    int rc = posix_spawn(&pid, args[0], &actions, NULL, args, environ);
    posix_spawn_file_actions_destroy(&actions);
    if (rc) return false;
    int status;
    while (waitpid(pid, &status, 0) < 0) { if (errno != EINTR) return false; }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static bool sync_status(bool online) {
    /* Local Unix socket only: never contact an external server. */
    http_t *http = httpConnect2("/private/var/run/cupsd", 0, NULL, AF_UNSPEC,
        HTTP_ENCRYPTION_NEVER, 1, 3000, NULL);
    if (!http) { fprintf(stderr, "Cannot reach local CUPS.\n"); return false; }
    ipp_t *r = request(IPP_OP_GET_PRINTER_ATTRIBUTES);
    const char *wanted[] = { "device-uri", "printer-state", "printer-state-reasons" };
    ippAddStrings(r, IPP_TAG_OPERATION, IPP_TAG_KEYWORD,
        "requested-attributes", 3, NULL, wanted);
    ipp_t *reply = cupsDoRequest(http, r, "/printers/" QUEUE);
    if (!reply || ippGetStatusCode(reply) >= IPP_STATUS_ERROR_BAD_REQUEST) {
        fprintf(stderr, "Cannot read P1008 queue: %s\n", cupsLastErrorString());
        if (reply) ippDelete(reply);
        httpClose(http); return false;
    }
    ipp_attribute_t *a = ippFindAttribute(reply, "device-uri", IPP_TAG_URI);
    const char *device_uri = a ? ippGetString(a, 0, NULL) : NULL;
    char scheme[32], user[256], host[256], resource[1024]; int port;
    bool valid = device_uri && httpSeparateURI(HTTP_URI_CODING_ALL, device_uri,
        scheme, sizeof(scheme), user, sizeof(user), host, sizeof(host), &port,
        resource, sizeof(resource)) >= HTTP_URI_STATUS_OK;
    char expected[300]; snprintf(expected, sizeof(expected), "serial=%s", serial);
    char *s = valid ? strstr(resource, "?serial=") : NULL;
    if (!s || strcmp(s + 1, expected) || strcmp(scheme, "hpp1008") ||
        strcmp(host, "Hewlett-Packard") ||
        strncmp(resource, "/HP LaserJet P1008?", 19)) {
        fprintf(stderr, "Queue identity/USB serial mismatch; refusing update.\n");
        ippDelete(reply); httpClose(http); return false;
    }
    a = ippFindAttribute(reply, "printer-state", IPP_TAG_ENUM);
    int state = a ? ippGetInteger(a, 0) : IPP_PRINTER_IDLE;
    const char *old[MAX_REASONS], *out[MAX_REASONS]; int n = 0;
    a = ippFindAttribute(reply, "printer-state-reasons", IPP_TAG_KEYWORD);
    if (a && ippGetCount(a) >= MAX_REASONS) {
        fprintf(stderr, "Too many reasons; refusing to overwrite status.\n");
        ippDelete(reply); httpClose(http); return false;
    }
    if (a) for (int i = 0; i < ippGetCount(a); i++) old[n++] = ippGetString(a, i, NULL);
    int count = merge(old, n, online, out);
    if (count < 0) { ippDelete(reply); httpClose(http); return false; }
    bool changed = count != n;
    if (!changed) for (int i = 0; i < n; i++) if (strcmp(old[i], out[i])) changed = true;
    if (changed && !observe_only) {
        bool ok = set_reasons(out, count);
        if (!ok) fprintf(stderr, "Cannot update P1008 status using local lpadmin.\n");
        if (!ok) { ippDelete(reply); httpClose(http); return false; }
    }
    if (clearing) fprintf(stderr, "P1008 monitor offline reason cleared; queue state %d preserved.\n", state);
    else if (last_presence != online || changed) {
        fprintf(stderr, "P1008 USB %s; %s; queue state %d preserved.\n",
            online ? "connected" : "disconnected",
            observe_only ? "read-only observation" : changed ? "status updated" : "status current", state);
    }
    last_presence = online;
    ippDelete(reply); httpClose(http); return true;
}

static void on_timer(CFRunLoopTimerRef t, void *context) {
    bool ok = sync_status(present());
    CFRunLoopTimerSetNextFireDate(t, CFAbsoluteTimeGetCurrent() + (ok ? 1.0e9 : 30));
}
static void on_event(void *context, io_iterator_t iter) {
    io_service_t dev;
    while ((dev = IOIteratorNext(iter))) IOObjectRelease(dev);
    /* Coalesce plug/unplug and short firmware re-enumeration into one scan. */
    if (timer) CFRunLoopTimerSetNextFireDate(timer, CFAbsoluteTimeGetCurrent() + 1.5);
}
static int self_test(void) {
    const char *a[] = { "paused", "media-empty-warning", REASON }, *b[MAX_REASONS];
    if (merge(a, 3, true, b) != 2 || strcmp(b[0], "paused") || strcmp(b[1], "media-empty-warning")) return 1;
    if (merge(a, 3, false, b) != 3 || strcmp(b[2], REASON)) return 1;
    const char *none[] = { "none" };
    if (merge(none, 1, false, b) != 1 || strcmp(b[0], REASON)) return 1;
    puts("PASS: preserves paused and other reasons; owns only the offline reason.");
    return 0;
}
int main(int argc, char **argv) {
    bool once = false, clear = false;
    if (argc == 2 && !strcmp(argv[1], "--self-test")) return self_test();
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--serial") && i + 1 < argc) serial = argv[++i];
        else if (!strcmp(argv[i], "--once")) once = true;
        else if (!strcmp(argv[i], "--clear")) clear = true;
        else if (!strcmp(argv[i], "--observe")) observe_only = true;
        else { fprintf(stderr, "Usage: %s --serial SERIAL [--once|--clear|--observe]\n", argv[0]); return 2; }
    }
    if (!serial || !*serial || strlen(serial) > 128) return 2;
    setvbuf(stderr, NULL, _IOLBF, 0);
    cupsSetPasswordCB2(no_password, NULL);
    clearing = clear;
    if (clear || once) return sync_status(clear || present()) ? 0 : 1;
    IONotificationPortRef notify = IONotificationPortCreate(kIOMainPortDefault);
    if (!notify) return 1;
    CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(notify), kCFRunLoopDefaultMode);
    timer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + 1.5, 1.0e9, 0, 0, on_timer, NULL);
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopDefaultMode);
    io_iterator_t added, removed;
    if (IOServiceAddMatchingNotification(notify, kIOFirstMatchNotification, matching(), on_event, NULL, &added) != KERN_SUCCESS ||
        IOServiceAddMatchingNotification(notify, kIOTerminatedNotification, matching(), on_event, NULL, &removed) != KERN_SUCCESS) return 1;
    on_event(NULL, added); on_event(NULL, removed);
    CFRunLoopRun();
    return 0;
}
