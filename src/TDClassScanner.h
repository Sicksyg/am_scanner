#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const TDScannerErrorDomain;

typedef NS_ENUM(NSInteger, TDScannerError) {
    TDScannerErrorUnknownBundleID = 1,
    TDScannerErrorSpawnFailed     = 2,
    TDScannerErrorTaskForPID      = 3,
    TDScannerErrorDyldRead        = 4,
    TDScannerErrorSignaturesLoad  = 5,
};

// When enabled, prints step-by-step diagnostics (spawn attempts, errno
// values, file stat info, memory stats, task_for_pid results, etc.) to
// stderr as the scan progresses. Off by default; enabled via -v/--verbose.
void TDSetVerbose(BOOL verbose);

NSArray * _Nullable TDLoadSignatures(NSString *path, NSError **error);

NSArray<NSDictionary *> * _Nullable TDListInstalledUserApps(void);
NSArray<NSDictionary *> * _Nullable TDListInstalledUserAppsWithIcons(void);

NSDictionary * _Nullable TDScanBundleID(NSString *bundleID,
                                        NSArray *compiledSignatures,
                                        NSError **error);

// Collects the same on-device evidence as TDScanBundleID (RAM class names,
// static disk walk, privacy manifests, raw Info.plist fields) but performs
// no signature regex matching. Intended for callers that want to do
// signature matching off-device (e.g. against a signature list maintained
// on a computer, so updating detections never requires reinstalling the
// on-device tool).
NSDictionary * _Nullable TDDumpBundleID(NSString *bundleID, NSError **error);

NS_ASSUME_NONNULL_END
