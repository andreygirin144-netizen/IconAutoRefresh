THEOS_PACKAGE_SCHEME = rootless

TARGET = iphone:clang:latest:15.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = IconAutoRefresh

IconAutoRefresh_FILES = Tweak.x
IconAutoRefresh_CFLAGS = -fobjc-arc
IconAutoRefresh_FRAMEWORKS = UIKit Foundation

include $(THEOS)/makefiles/tweak.mk
