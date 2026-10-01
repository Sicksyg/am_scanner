#import <Foundation/Foundation.h>
#import <stdio.h>
#import "TDClassScanner.h"

static NSString *const kDefaultSigPath = @"/var/jb/usr/share/am_scanner/signatures.json";

static void emitErrorJSON(NSString *msg) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:@{@"error": msg ?: @"unknown"}
                                                options:0
                                                  error:nil];
    fwrite(d.bytes, 1, d.length, stderr);
    fputc('\n', stderr);
}

static int usage(void) {
    fprintf(stderr,
        "am_scanner <bundleID>                scan one app, print JSON to stdout\n"
        "am_scanner --list                    list installed user apps (bundleID\\tname\\tversion)\n"
        "am_scanner --list --json             list apps and available icons as JSON\n"
        "am_scanner --dump <bundleID>         skip signature matching; print raw\n"
        "                                    evidence (classes, framework names,\n"
        "                                    plist tokens, permissions, bundleInfo)\n"
        "                                    for off-device matching\n"
        "am_scanner -v, --verbose             print diagnostic logging (spawn/exec\n"
        "                                    attempts, errno, vm_stat, rlimits) to\n"
        "                                    stderr while scanning; combine with\n"
        "                                    any of the above\n");
    return 2;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc < 2) return usage();

        NSString *bundleID = nil;
        BOOL list = NO;
        BOOL jsonOutput = NO;
        BOOL dump = NO;
        BOOL verbose = NO;

        int i = 1;
        while (i < argc) {
            const char *a = argv[i];
            if (strcmp(a, "--list") == 0) {
                list = YES; i++;
            } else if (strcmp(a, "--json") == 0) {
                jsonOutput = YES; i++;
            } else if (strcmp(a, "--dump") == 0) {
                dump = YES; i++;
            } else if (strcmp(a, "-v") == 0 || strcmp(a, "--verbose") == 0) {
                verbose = YES; i++;
            } else if (strcmp(a, "-h") == 0 || strcmp(a, "--help") == 0) {
                usage();
                return 0;
            } else if (a[0] == '-') {
                return usage();
            } else {
                if (bundleID) return usage();
                bundleID = [NSString stringWithUTF8String:a];
                i++;
            }
        }

        TDSetVerbose(verbose);

        if (jsonOutput && !list) return usage();

        if (list) {
            if (jsonOutput) {
                NSError *err = nil;
                NSArray *apps = TDListInstalledUserAppsWithIcons();
                NSData *out = [NSJSONSerialization dataWithJSONObject:@{@"apps": apps}
                                                              options:NSJSONWritingPrettyPrinted
                                                                error:&err];
                if (!out) {
                    emitErrorJSON(err.localizedDescription ?: @"app list JSON encode failed");
                    return 1;
                }
                fwrite(out.bytes, 1, out.length, stdout);
                fputc('\n', stdout);
            } else {
                for (NSDictionary *app in TDListInstalledUserApps()) {
                    printf("%s\t%s\t%s\n",
                           [app[@"bundleID"] UTF8String],
                           [app[@"name"] UTF8String],
                           [app[@"version"] UTF8String]);
                }
            }
            return 0;
        }

        if (!bundleID) return usage();

        NSError *err = nil;
        NSDictionary *result;
        if (dump) {
            result = TDDumpBundleID(bundleID, &err);
        } else {
            NSArray *sigs = TDLoadSignatures(kDefaultSigPath, &err);
            if (!sigs) {
                emitErrorJSON([NSString stringWithFormat:@"failed to load signatures from %@: %@",
                               kDefaultSigPath, err.localizedDescription]);
                return 1;
            }
            result = TDScanBundleID(bundleID, sigs, &err);
        }
        if (!result) {
            emitErrorJSON(err.localizedDescription ?: @"scan failed");
            return 1;
        }

        NSData *out = [NSJSONSerialization dataWithJSONObject:result
                                                      options:NSJSONWritingPrettyPrinted
                                                        error:&err];
        if (!out) {
            emitErrorJSON(err.localizedDescription ?: @"JSON encode failed");
            return 1;
        }
        fwrite(out.bytes, 1, out.length, stdout);
        fputc('\n', stdout);
        return 0;
    }
}
