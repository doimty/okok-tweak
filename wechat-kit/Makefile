TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME ?= roothide
FINALPACKAGE ?= 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeChatKit
WeChatKit_FILES = src/WCKBootstrap.m src/WCKRuntime.m src/WCKPolicy.c \
    src/WCKSettings.m src/WCKSettingsViewController.m src/WCKKeyboard.m \
    src/WCKSVG.m src/WCKReadAll.m src/WCKAlbumSheet.m src/WCKMomentsTime.m src/WCKVerifiedFeatures.m \
    src/WCKEntryRegistry.m src/WCKEntryUI.m src/WCKHostIdentity.m src/WCKSVGSelection.m \
    src/WCKSVGPalette.m src/WCKSVGColorViewController.m
WeChatKit_FRAMEWORKS = Foundation UIKit CoreGraphics
WeChatKit_CFLAGS = -fobjc-arc -Isrc -Wall -Wextra -Werror \
    -Wno-unused-parameter -Wno-deprecated-declarations
# Substrate is resolved via dlsym; package still declares its runtime dependency.

include $(THEOS_MAKE_PATH)/tweak.mk

# No after-install restart: installation/device changes require separate authorization.
