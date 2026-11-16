/* MB1054A (STM32F103CB + CR95HF). Die CR95HF-Verbindung (SPI1/SPI2/UART) sucht main.c beim Start selbst. */
#pragma once
#define USB_PU_PORT GPIOB         /* USB-D+-Pull-up, aktiv low (per Pin-Scan ermittelt) */
#define USB_PU_PIN  GPIO0
