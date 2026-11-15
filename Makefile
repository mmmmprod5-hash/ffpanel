TARGET := iphone:clang:latest:14.0
ARCHS = arm64
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = FFMenu
FFMenu_FILES = Tweak.xm
FFMenu_FRAMEWORKS = UIKit Foundation QuartzCore
FFMenu_PRIVATE_FRAMEWORKS = IOKit
include $(THEOS)/makefiles/tweak.mk
