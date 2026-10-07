export ARCHS = arm64 arm64e
export TARGET = iphone:clang:16.5:15.0
export THEOS_PACKAGE_SCHEME = roothide
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = Clipboard
Clipboard_FILES = Clipboard.xm Store.m
Clipboard_CFLAGS = -fobjc-arc
Clipboard_FRAMEWORKS = UIKit ImageIO AudioToolbox IOKit
Clipboard_LIBRARIES = sqlite3 roothide
Clipboard_INSTALL_PATH = /usr/lib/TweakInject
include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS = Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
