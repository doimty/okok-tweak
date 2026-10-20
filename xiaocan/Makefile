export ARCHS = arm64 arm64e

THEOS_PACKAGE_SCHEME = roothide

export DEBUG = 0
export FINALPACKAGE = 1

TARGET := iphone:clang:16.5:15.0

INSTALL_TARGET_PROCESSES = xiaocan

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = XiaocanAdFree
XiaocanAdFree_FILES = Tweak.xm HomePromotions.xm
XiaocanAdFree_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
