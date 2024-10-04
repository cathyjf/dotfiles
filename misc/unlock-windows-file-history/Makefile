binary_name = unlock-windows-file-history
output_binary = bin/$(binary_name)
install_location = /var/root/$(binary_name)
magic_account_name := $(shell chezmoi execute-template '{{ .windowsFileHistory.magicAccountName }}')
magic_volume_id := $(shell chezmoi execute-template '{{ .windowsFileHistory.magicVolumeID }}')

all : $(output_binary)

$(output_binary) : src/main.cpp | bin
	clang $< -o $@ -arch x86_64 -arch arm64 -std=c++17 -lstdc++ -framework Security \
		-D MAGIC_ACCOUNT_NAME='"$(magic_account_name)"' \
		-D MAGIC_VOLUME_ID='"$(magic_volume_id)"'
	@make sign

sign : | $(output_binary)
	@IDENTITY=$$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep -o "[A-F0-9]\{25,\}"); \
	echo Signing $(output_binary) with identity $$IDENTITY.; \
	codesign -f --timestamp -s "$$IDENTITY" --options runtime $(output_binary)

bin :
	mkdir $@

$(install_location) : $(output_binary)
	@if [ -z "$$DRYRUN" ]; then \
		/bin/sh -x -c "sudo cp $< $@"; \
	else \
		echo "To install unlock-windows-file-history, run:"; \
		echo "    make install -C \"$$PWD\""; \
	fi

install : $(install_location)

clean :
	rm -f $(output_binary)

.DELETE_ON_ERROR:

.PHONY: all sign install clean