KERNEL_REPO=https://github.com/sophgo/linux-riscv.git
KERNEL_COMMIT=641c5b68a4595cb6ab45cbfa6b8b3d7a165c3f76
KERNEL_DIR=linux-riscv
KERNEL_CONFIG=sgrec_kernel_defconfig

BUILDROOT_REPO=https://github.com/buildroot/buildroot.git
BUILDROOT_COMMIT=2026.02
BUILDROOT_DIR=buildroot
BUILDROOT_CONFIG=sgrec_buildroot_defconfig

BUILD_DIR=build

ISO_DIR=$(BUILD_DIR)/iso
RAMFS_DIR=$(BUILD_DIR)/ramfs

# for native build, let it empty
CROSS_COMPILE=

ARCH=riscv

tools: FORCE
	sudo dnf install grub2-efi-riscv64-modules mtools dosfstools

$(BUILDROOT_DIR):
	git clone $(BUILDROOT_REPO)

buildroot-source: $(BUILDROOT_DIR)
	cd $(BUILDROOT_DIR) && git checkout $(BUILDROOT_COMMIT)
	make -C $< distclean
	cp $(BUILDROOT_CONFIG) $</.config
	make -C $< olddefconfig

$(KERNEL_DIR):
	git clone $(KERNEL_REPO)

kernel-source: $(KERNEL_DIR)
	cd $< && git checkout $(KERNEL_COMMIT)
	make -C $< ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) distclean
	cp $(KERNEL_CONFIG) $</.config
	make -C $< ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) olddefconfig

$(KERNEL_DIR)/arch/riscv/boot/Image.gz: linux-source
	make -C $(KERNEL_DIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) -j$(nproc) modules Image.gz

$(ISO_DIR): FORCE
	mkdir -p $@

$(ISO_DIR)/boot: FORCE
	mkdir -p $@

$(ISO_DIR)/boot/vmlinuz: $(KERNEL_DIR)/arch/riscv/boot/Image.gz
	cp $< $@
	


FORCE:

.PHONY: FORCE

