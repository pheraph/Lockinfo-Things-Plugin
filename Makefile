CC=/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/arm-apple-darwin9-gcc-4.2.1
CPP=/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/arm-apple-darwin9-g++-4.2.1
LD=$(CC)

SDKVER=2.2.1
SDK=/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS$(SDKVER).sdk

LDFLAGS= -framework Foundation \
	-framework UIKit \
	-framework CoreFoundation \
	-framework CoreGraphics \
	-framework Preferences \
	-framework GraphicsServices \
	-L../Common \
	-L$(SDK)/usr/lib \
	-F$(SDK)/System/Library/Frameworks \
	-F$(SDK)/System/Library/PrivateFrameworks \
	-lsqlite3 \
	-lobjc

CFLAGS= -I$(SDK)/var/include \
  -I/var/include \
  -I/var/include/gcc/darwin/4.0 \
  -I.. \
  -I"$(SDK)/usr/include" \
  -I"$(SDK)/var/include" \
  -I"/Developer/Platforms/iPhoneOS.platform/Developer/usr/include" \
  -I"/Developer/Platforms/iPhoneOS.platform/Developer/usr/lib/gcc/arm-apple-darwin9/4.2.1/include" \
  -DDEBUG -Diphoneos_version_min=2.0 -objc-exceptions
  
  CFLAGS += -I"/Developer/Platforms/iPhoneOS.platform/Developer/usr/lib/gcc/arm-apple-darwin9/4.2.1/include/"
CFLAGS += -I"$(SDK)/usr/include"
CFlags += -I"$(SDK)/var/include"
CFLAGS += -I"/Developer/Platforms/iPhoneOS.platform/Developer/usr/include/"
CFLAGS += -I"/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator$(SDKVER).sdk/usr/include"
CFLAGS += -DDEBUG -std=c99
CFLAGS += -Diphoneos_version_min=2.0
CFLAGS += -F"$(SDK)/System/Library/Frameworks"
CFLAGS += -F"$(SDK)/System/Library/PrivateFrameworks"
CFLAGS += -Wall


Name=ThingsPlugin
Bundle=com.jakewalk.lockinfo.$(Name).bundle

all:	package

$(Name):	$(Name).o
		$(LD) $(LDFLAGS) -bundle -o $@ $^
		./ldid -S $@
		chmod 755 $@

%.o:	%.mm
		$(CPP) -c $(CFLAGS) $< -o $@

clean:
		rm -f *.o $(Name)
		rm -rf package

package: 	$(Name)
	mkdir -p package/DEBIAN
	mkdir -p package/Library/LockInfo/Plugins/$(Bundle)
	cp -r Bundle/* package/Library/LockInfo/Plugins/$(Bundle)
	cp ThingsPlugin package/Library/LockInfo/Plugins/$(Bundle)
	cp control package/DEBIAN
	find package -name .svn -print0 | xargs -0 rm -rf
	dpkg-deb -b package $(Name)_$(shell grep ^Version: control | cut -d ' ' -f 2).deb
