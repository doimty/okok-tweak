export ARCHS = arm64 arm64e

THEOS_PACKAGE_SCHEME = roothide

export DEBUG = 0
export FINALPACKAGE = 1

TARGET := iphone:clang:16.5:15.0

INSTALL_TARGET_PROCESSES = OKOK

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OKOKAdFree
OKOKAdFree_FILES = Tweak.xm
OKOKAdFree_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
