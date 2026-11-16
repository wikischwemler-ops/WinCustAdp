PREFIX ?= arm-none-eabi
OCM3   := libopencm3
CFLAGS := -Os -g -mcpu=cortex-m3 -mthumb -DSTM32F1 -I$(OCM3)/include -Wall -ffunction-sections -fdata-sections
LDFLAGS:= -mcpu=cortex-m3 -mthumb -nostartfiles -Wl,--gc-sections -T stm32f103cb.ld -L$(OCM3)/lib \
          --specs=nano.specs --specs=nosys.specs
STLINK ?= "C:/tools/STLink/ST-LINK Utility/ST-LINK_CLI.exe"

all: build/fw.bin

$(OCM3)/lib/libopencm3_stm32f1.a:
	git clone --depth 1 https://github.com/libopencm3/libopencm3 $(OCM3)
	$(MAKE) -C $(OCM3) TARGETS=stm32/f1

build/fw.elf: main.c pins.h stm32f103cb.ld $(OCM3)/lib/libopencm3_stm32f1.a
	mkdir -p build
	$(PREFIX)-gcc $(CFLAGS) main.c $(LDFLAGS) -lopencm3_stm32f1 -o $@
	$(PREFIX)-size $@

build/fw.bin: build/fw.elf
	$(PREFIX)-objcopy -O binary $< $@

flash: build/fw.bin
	$(STLINK) -c SWD UR -P build/fw.bin 0x08000000 -V -Rst

.PHONY: all flash
