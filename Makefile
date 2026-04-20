KERNEL_REPO = https://github.com/sophgo/linux-riscv.git
KERNEL_COMMIT = 641c5b68a4595cb6ab45cbfa6b8b3d7a165c3f76
KERNEL_DIR = $(shell pwd)/linux-riscv
KERNEL_CONFIG = config/kernel/sgrec_kernel_defconfig

BUILDROOT_REPO = https://github.com/buildroot/buildroot.git
BUILDROOT_COMMIT = 2026.02
BUILDROOT_DIR = $(shell pwd)/buildroot
BUILDROOT_CONFIG = config/buildroot/sgrec_buildroot_defconfig

LINUX_FIRMWARE_DIR = $(shell pwd)/linux-firmware
LINUX_FIRMWARE_REPO = https://github.com/endlessm/linux-firmware.git

GRUB_CONFIG = config/grub/grub.cfg

BUILD_DIR = $(shell pwd)/build

ISO_FILE = $(BUILD_DIR)/sophgo-recovery.iso
ISO_DIR = $(BUILD_DIR)/iso
EFI_IMG = $(BUILD_DIR)/efi.img
EFI_DIR = $(BUILD_DIR)/EFI
ROOTFS_DIR = $(BUILD_DIR)/rootfs

QEMU = qemu-system-riscv64

SUPPORT_AMD_GPU ?= y
SUPPORT_NVIDIA_GPU ?= y

# for native build, let it empty
CROSS_COMPILE =

ARCH = riscv

all: $(ISO_FILE)
	echo 'Done'

tools: FORCE
	sudo dnf install grub2-efi-riscv64-modules mtools dosfstools

	
clean: buildroot-clean kernel-clean target-clean
	echo 'Clean done'

buildroot-clean: FORCE
	if [ -d $(BUILDROOT_DIR) ]; then \
		make -C $(BUILDROOT_DIR) distclean; \
	fi

buildroot-source: FORCE
	if [ ! -d $(BUILDROOT_DIR) ]; then \
		git clone $(BUILDROOT_REPO) $(BUILDROOT_DIR) && \
		cd $(BUILDROOT_DIR) && \
		git checkout $(BUILDROOT_COMMIT); \
	fi
	cp $(BUILDROOT_CONFIG) $(BUILDROOT_DIR)/.config
	make -C $(BUILDROOT_DIR) olddefconfig

target-clean:
	rm -rf $(BUILD_DIR)

buildroot-target: buildroot-source
	make -C $(BUILDROOT_DIR) -j$$(nproc)

kernel-clean: FORCE
	if [ -d $(KERNEL_DIR) ]; then \
		make -C $(KERNEL_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) distclean
	fi

kernel-source: FORCE
	if [ ! -d $(KERNEL_DIR) ]; then \
		git clone $(KERNEL_REPO) && \
		cd $(KERNEL_DIR) && \
		git checkout $(KERNEL_COMMIT); \
	fi
	cp $(KERNEL_CONFIG) $(KERNEL_DIR)/.config
	make -C $(KERNEL_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) olddefconfig

kernel-target: kernel-source
	make -C $(KERNEL_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -j$$(nproc) Image.gz

rootfs: # buildroot-target kernel-source
	mkdir -p $(ISO_DIR)/boot
	rm -rf $(ROOTFS_DIR) && mkdir -p $(ROOTFS_DIR)
	cd $(ROOTFS_DIR) && fakeroot cpio -imd < $(BUILDROOT_DIR)/output/images/rootfs.cpio
	echo 'Remove OSC 8003 for compatible consideration'
	rm -rf $(ROOTFS_DIR)/etc/profile.d/80-systemd-osc-context.sh
	rm -rf $(ROOTFS_DIR)/usr/lib/tmpfiles.d/20-systemd-osc-context.conf
	make -C $(KERNEL_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -j$$(nproc) INSTALL_MOD_PATH=$(ROOTFS_DIR)/usr INSTALL_MOD_STRIP=1 modules_install
ifeq ($(strip $(SUPPORT_AMD_GPU)), y)
	cp -r $(LINUX_FIRMWARE_DIR)/amdgpu $(ROOTFS_DIR)/usr/lib
endif
ifeq ($(strip $(SUPPORT_NVIDIA_GPU)), y)
	cp -r $(LINUX_FIRMWARE_DIR)/nvidia $(ROOTFS_DIR)/usr/lib
endif
	cd $(ROOTFS_DIR) && find . | cpio -H newc -o -R 0:0 | gzip > $(ISO_DIR)/boot/rootfs.cpio.gz

kernel-image: kernel-target
	mkdir -p $(ISO_DIR)/boot
	cp $(KERNEL_DIR)/arch/riscv/boot/Image.gz $(ISO_DIR)/boot/Image.gz

linux-firmware-source: FORCE
	if [ ! -d $(LINUX_FIRMWARE_DIR) ]; then \
		git clone $(LINUX_FIRMWARE_REPO) $(LINUX_FIRMWARE_DIR); \
	fi
	cd $(LINUX_FIRMWARE_DIR) && git pull

$(ISO_DIR)/boot/grub/grub.cfg: $(GRUB_CONFIG)
	mkdir -p $(dir $@)
	cp $< $@

$(EFI_IMG): FORCE
	rm -rf $(EFI_IMG) $(EFI_DIR)
	mkdir -p $(EFI_DIR)/BOOT
	grub2-mkimage	-O riscv64-efi \
			-o $(EFI_DIR)/BOOT/BOOTRISCV64.EFI \
			-p /boot/grub \
			iso9660 linux normal fat exfat \
			echo file hello help loadenv probe \
			search boot true reboot configfile gzio
	mkfs.vfat -C -n SGREC $(EFI_IMG) 4096
	mcopy -i $(EFI_IMG) -s $(EFI_DIR) ::

efi-image: $(EFI_IMG)
grub-config: $(ISO_DIR)/boot/grub/grub.cfg

$(ISO_FILE):  FORCE efi-image rootfs kernel-image grub-config
	xorriso		-as mkisofs \
			-r \
			-V "SOPHGO-RECOVERY" \
			-o $@ \
			-J \
			-joliet-long \
			-cache-inodes \
			-no-emul-boot \
			-append_partition 2 0xef $(EFI_IMG) \
			-partition_cyl_align all $(ISO_DIR)

run: FORCE
	$(QEMU) \
		-machine virt,acpi=off -m 4G -smp 4 -nographic   \
		-drive if=pflash,format=raw,unit=0,file=binary/RISCV_VIRT_CODE.fd,readonly=on \
		-drive if=pflash,format=raw,unit=1,file=binary/RISCV_VIRT_VARS.fd \
		-drive if=virtio,media=cdrom,readonly=on,file=$(ISO_FILE)

FORCE:

.PHONY: FORCE

