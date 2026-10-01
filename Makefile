TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TOOL_NAME = am_scanner
am_scanner_FILES = src/main.m src/TDClassScanner.m src/LSApplicationProxy+AltList.m
am_scanner_CFLAGS = -fobjc-arc
am_scanner_CODESIGN_FLAGS = -Ssrc/entitlements.plist
am_scanner_INSTALL_PATH = /usr/local/bin
am_scanner_FRAMEWORKS = Foundation UIKit
am_scanner_PRIVATE_FRAMEWORKS = MobileCoreServices

include $(THEOS_MAKE_PATH)/tool.mk

after-stage::
	install -d $(THEOS_STAGING_DIR)/usr/share/am_scanner
	install -m 644 src/signatures.json $(THEOS_STAGING_DIR)/usr/share/am_scanner/
