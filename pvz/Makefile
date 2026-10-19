export ARCHS = arm64 arm64e

THEOS_PACKAGE_SCHEME = roothide

export DEBUG = 0
export FINALPACKAGE = 1

TARGET := iphone:clang:16.5:15.0

INSTALL_TARGET_PROCESSES = pvz

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PVZAdFree
PVZAdFree_FILES = Tweak.xm
PVZAdFree_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
