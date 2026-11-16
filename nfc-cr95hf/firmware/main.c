/* MB1054A: USB-CDC <-> SPI-Bruecke zum CR95HF.
 * PC sendet CR95HF-Befehl [cmd][len][data], Antwort [code][len][data].
 * Eigener Befehl 0xF0 = CR95HF reset/wake. Timeout -> Antwort FE 00. */
#include <libopencm3/stm32/rcc.h>
#include <libopencm3/stm32/gpio.h>
#include <libopencm3/stm32/spi.h>
#include <libopencm3/stm32/usart.h>
#include <libopencm3/usb/usbd.h>
#include <libopencm3/usb/cdc.h>
#include <stddef.h>
#include "pins.h"

static void delay_ms(uint32_t ms) { for (volatile uint32_t i = 0; i < ms * 6000; i++); }

/* ---------- USB-Deskriptoren (CDC ACM) ---------- */
static const struct usb_device_descriptor dev_desc = {
	.bLength = USB_DT_DEVICE_SIZE, .bDescriptorType = USB_DT_DEVICE, .bcdUSB = 0x0200,
	.bDeviceClass = USB_CLASS_CDC, .bMaxPacketSize0 = 64, .idVendor = 0x0483, .idProduct = 0x5740,
	.bcdDevice = 0x0100, .iManufacturer = 1, .iProduct = 2, .iSerialNumber = 3, .bNumConfigurations = 1 };
static const struct usb_endpoint_descriptor comm_ep[] = {{
	.bLength = USB_DT_ENDPOINT_SIZE, .bDescriptorType = USB_DT_ENDPOINT, .bEndpointAddress = 0x83,
	.bmAttributes = USB_ENDPOINT_ATTR_INTERRUPT, .wMaxPacketSize = 16, .bInterval = 255 }};
static const struct usb_endpoint_descriptor data_ep[] = {
	{ .bLength = USB_DT_ENDPOINT_SIZE, .bDescriptorType = USB_DT_ENDPOINT, .bEndpointAddress = 0x01,
	  .bmAttributes = USB_ENDPOINT_ATTR_BULK, .wMaxPacketSize = 64, .bInterval = 1 },
	{ .bLength = USB_DT_ENDPOINT_SIZE, .bDescriptorType = USB_DT_ENDPOINT, .bEndpointAddress = 0x82,
	  .bmAttributes = USB_ENDPOINT_ATTR_BULK, .wMaxPacketSize = 64, .bInterval = 1 }};
static const struct {
	struct usb_cdc_header_descriptor h; struct usb_cdc_call_management_descriptor cm;
	struct usb_cdc_acm_descriptor acm; struct usb_cdc_union_descriptor u;
} __attribute__((packed)) cdc_func = {
	.h = { sizeof(struct usb_cdc_header_descriptor), CS_INTERFACE, USB_CDC_TYPE_HEADER, 0x0110 },
	.cm = { sizeof(struct usb_cdc_call_management_descriptor), CS_INTERFACE, USB_CDC_TYPE_CALL_MANAGEMENT, 0, 1 },
	.acm = { sizeof(struct usb_cdc_acm_descriptor), CS_INTERFACE, USB_CDC_TYPE_ACM, 0 },
	.u = { sizeof(struct usb_cdc_union_descriptor), CS_INTERFACE, USB_CDC_TYPE_UNION, 0, 1 } };
static const struct usb_interface_descriptor comm_if[] = {{
	.bLength = USB_DT_INTERFACE_SIZE, .bDescriptorType = USB_DT_INTERFACE, .bInterfaceNumber = 0,
	.bNumEndpoints = 1, .bInterfaceClass = USB_CLASS_CDC, .bInterfaceSubClass = USB_CDC_SUBCLASS_ACM,
	.bInterfaceProtocol = USB_CDC_PROTOCOL_AT, .endpoint = comm_ep, .extra = &cdc_func, .extralen = sizeof(cdc_func) }};
static const struct usb_interface_descriptor data_if[] = {{
	.bLength = USB_DT_INTERFACE_SIZE, .bDescriptorType = USB_DT_INTERFACE, .bInterfaceNumber = 1,
	.bNumEndpoints = 2, .bInterfaceClass = USB_CLASS_DATA, .endpoint = data_ep }};
static const struct usb_interface ifaces[] = {{ .num_altsetting = 1, .altsetting = comm_if },
                                              { .num_altsetting = 1, .altsetting = data_if }};
static const struct usb_config_descriptor cfg_desc = {
	.bLength = USB_DT_CONFIGURATION_SIZE, .bDescriptorType = USB_DT_CONFIGURATION, .bNumInterfaces = 2,
	.bConfigurationValue = 1, .bmAttributes = 0x80, .bMaxPower = 0x32, .interface = ifaces };
static const char *usb_str[] = { "Eigenbau", "CR95HF NFC Bridge", "MB1054A" };
static uint8_t ctrl_buf[128];
static struct usb_cdc_line_coding line = { 115200, USB_CDC_1_STOP_BITS, USB_CDC_NO_PARITY, 8 };

static uint8_t rx[300]; static volatile uint16_t rx_len;

static enum usbd_request_return_codes ctrl_req(usbd_device *d, struct usb_setup_data *req, uint8_t **buf,
	uint16_t *len, void (**complete)(usbd_device *, struct usb_setup_data *)) {
	(void)d; (void)complete;
	switch (req->bRequest) {
	case USB_CDC_REQ_SET_CONTROL_LINE_STATE: return USBD_REQ_HANDLED;
	case USB_CDC_REQ_SET_LINE_CODING: return *len < sizeof(line) ? USBD_REQ_NOTSUPP : USBD_REQ_HANDLED;
	case 0x21: *buf = (uint8_t *)&line; *len = sizeof(line); return USBD_REQ_HANDLED; /* GET_LINE_CODING */
	}
	return USBD_REQ_NOTSUPP;
}
static void data_rx(usbd_device *d, uint8_t ep) {
	(void)ep; uint8_t b[64]; int n = usbd_ep_read_packet(d, 0x01, b, 64);
	for (int i = 0; i < n && rx_len < sizeof(rx); i++) rx[rx_len++] = b[i];
}
static void set_cfg(usbd_device *d, uint16_t v) {
	(void)v;
	usbd_ep_setup(d, 0x01, USB_ENDPOINT_ATTR_BULK, 64, data_rx);
	usbd_ep_setup(d, 0x82, USB_ENDPOINT_ATTR_BULK, 64, NULL);
	usbd_ep_setup(d, 0x83, USB_ENDPOINT_ATTR_INTERRUPT, 16, NULL);
	usbd_register_control_callback(d, USB_REQ_TYPE_CLASS | USB_REQ_TYPE_INTERFACE,
		USB_REQ_TYPE_TYPE | USB_REQ_TYPE_RECIPIENT, ctrl_req);
}

/* ---------- CR95HF: Verbindung wird beim Start automatisch gesucht ---------- */
typedef struct { uint8_t uart; uint32_t per, nport; uint16_t npin; } link_t;
static const link_t links[] = {
	{0, SPI1, GPIOA, GPIO4}, {0, SPI2, GPIOB, GPIO12},          /* SPI1 PA5-7, SPI2 PB13-15 */
	{1, USART1, GPIOA, GPIO9}, {1, USART2, GPIOA, GPIO2}, {1, USART3, GPIOB, GPIO10} }; /* npin = TX */
/* Moegliche IRQ_IN-Leitungen (MCU -> CR95HF) */
static const struct { uint32_t port; uint16_t pin; } irq_c[] = {
	{GPIOA, GPIO0}, {GPIOA, GPIO1}, {GPIOA, GPIO2}, {GPIOA, GPIO3}, {GPIOA, GPIO8}, {GPIOA, GPIO9},
	{GPIOA, GPIO10}, {GPIOA, GPIO15}, {GPIOB, GPIO1}, {GPIOB, GPIO10}, {GPIOB, GPIO11} };
static int lk = -1;                                   /* gefundene Verbindung */

static void delay_us(uint32_t us) { for (volatile uint32_t i = 0; i < us * 6; i++); }
static uint8_t x(uint8_t b) { return (uint8_t)spi_xfer(links[lk].per, b); }
static void nss(int on) { if (on) gpio_clear(links[lk].nport, links[lk].npin); else gpio_set(links[lk].nport, links[lk].npin); }

static void link_setup(int i) {
	const link_t *l = &links[i]; lk = i;
	if (!l->uart) {
		if (l->per == SPI1) {
			gpio_set_mode(GPIOA, GPIO_MODE_OUTPUT_50_MHZ, GPIO_CNF_OUTPUT_ALTFN_PUSHPULL, GPIO5 | GPIO7);
			gpio_set_mode(GPIOA, GPIO_MODE_INPUT, GPIO_CNF_INPUT_FLOAT, GPIO6);
		} else {
			gpio_set_mode(GPIOB, GPIO_MODE_OUTPUT_50_MHZ, GPIO_CNF_OUTPUT_ALTFN_PUSHPULL, GPIO13 | GPIO15);
			gpio_set_mode(GPIOB, GPIO_MODE_INPUT, GPIO_CNF_INPUT_FLOAT, GPIO14);
		}
		gpio_set(l->nport, l->npin);
		gpio_set_mode(l->nport, GPIO_MODE_OUTPUT_2_MHZ, GPIO_CNF_OUTPUT_PUSHPULL, l->npin);
		spi_init_master(l->per, l->per == SPI1 ? SPI_CR1_BAUDRATE_FPCLK_DIV_64 : SPI_CR1_BAUDRATE_FPCLK_DIV_32,
			SPI_CR1_CPOL_CLK_TO_0_WHEN_IDLE, SPI_CR1_CPHA_CLK_TRANSITION_1, SPI_CR1_DFF_8BIT, SPI_CR1_MSBFIRST);
		spi_enable_software_slave_management(l->per); spi_set_nss_high(l->per); spi_enable(l->per);
	} else {
		gpio_set_mode(l->nport, GPIO_MODE_OUTPUT_50_MHZ, GPIO_CNF_OUTPUT_ALTFN_PUSHPULL, l->npin);
		usart_set_baudrate(l->per, 57600); usart_set_databits(l->per, 8); usart_set_stopbits(l->per, USART_STOPBITS_1);
		usart_set_parity(l->per, USART_PARITY_NONE); usart_set_flow_control(l->per, USART_FLOWCONTROL_NONE);
		usart_set_mode(l->per, USART_MODE_TX_RX); usart_enable(l->per);
	}
}
static void link_off(void) {
	const link_t *l = &links[lk];
	if (l->uart) usart_disable(l->per); else spi_disable(l->per);
	gpio_set_mode(GPIOA, GPIO_MODE_INPUT, GPIO_CNF_INPUT_FLOAT, GPIO2 | GPIO4 | GPIO5 | GPIO7 | GPIO9);
	gpio_set_mode(GPIOB, GPIO_MODE_INPUT, GPIO_CNF_INPUT_FLOAT, GPIO10 | GPIO12 | GPIO13 | GPIO15);
}
static int u_rx(void) {                              /* UART-Byte oder -1 nach ~300 ms */
	for (uint32_t t = 0; t < 2000000; t++) if (USART_SR(links[lk].per) & USART_SR_RXNE) return USART_DR(links[lk].per) & 0xFF;
	return -1;
}
static void u_tx(uint8_t b) { usart_send_blocking(links[lk].per, b); }

/* Weckpuls: kurzer Low-Puls (Open-Drain) auf alle moeglichen IRQ_IN-Leitungen */
static void wake_pulse(void) {
	for (unsigned i = 0; i < sizeof(irq_c) / sizeof(irq_c[0]); i++) {
		if (lk >= 0 && links[lk].uart) break;         /* UART: Weckpuls kommt ueber TX */
		gpio_clear(irq_c[i].port, irq_c[i].pin);
		gpio_set_mode(irq_c[i].port, GPIO_MODE_OUTPUT_2_MHZ, GPIO_CNF_OUTPUT_OPENDRAIN, irq_c[i].pin);
		delay_us(100);
		gpio_set_mode(irq_c[i].port, GPIO_MODE_INPUT, GPIO_CNF_INPUT_FLOAT, irq_c[i].pin);
	}
	if (lk >= 0 && links[lk].uart) u_tx(0x00);
	delay_ms(15);
}

/* Sendet Befehl, wartet, liest Antwort nach out. Rueckgabe Laenge oder 0 bei Timeout. */
static int cr_cmd(const uint8_t *cmd, uint8_t *out) {
	if (lk < 0) return 0;
	if (links[lk].uart) {
		for (int i = 0; i < cmd[1] + 2; i++) u_tx(cmd[i]);
		int c = u_rx(), n = c < 0 ? -1 : u_rx(); if (n < 0) return 0;
		out[0] = c; out[1] = n;
		for (int i = 0; i < n; i++) { int b = u_rx(); if (b < 0) return 0; out[2 + i] = b; }
		return n + 2;
	}
	nss(1); x(0x00); for (int i = 0; i < cmd[1] + 2; i++) x(cmd[i]); nss(0);
	nss(1); x(0x03); int ok = 0;
	for (uint32_t t = 0; t < 400000; t++) if (x(0x03) & 0x08) { ok = 1; break; }
	nss(0); if (!ok) return 0;
	nss(1); x(0x02); out[0] = x(0); out[1] = x(0); for (int i = 0; i < out[1]; i++) out[2 + i] = x(0); nss(0);
	return out[1] + 2;
}

static void cr_wake(void) {
	if (lk >= 0 && !links[lk].uart) { nss(1); x(0x01); nss(0); delay_ms(2); }   /* SPI-Reset */
	wake_pulse();
}

/* Probiert alle Verbindungen, bis IDN mit Code 00 antwortet */
static void cr_find(void) {
	static const uint8_t idn[] = {0x01, 0x00}; static uint8_t o[260];
	for (unsigned i = 0; i < sizeof(links) / sizeof(links[0]); i++) {
		link_setup(i); cr_wake();
		if (cr_cmd(idn, o) > 2 && o[0] == 0x00) return;
		link_off();
	}
	lk = -1;
}

static void hw_init(void) {
	rcc_clock_setup_pll(&rcc_hse_configs[RCC_CLOCK_HSE8_72MHZ]);
	rcc_periph_clock_enable(RCC_GPIOA); rcc_periph_clock_enable(RCC_GPIOB); rcc_periph_clock_enable(RCC_AFIO);
	rcc_periph_clock_enable(RCC_SPI1); rcc_periph_clock_enable(RCC_SPI2);
	rcc_periph_clock_enable(RCC_USART1); rcc_periph_clock_enable(RCC_USART2); rcc_periph_clock_enable(RCC_USART3);
	/* USB neu anmelden: D+ kurz auf low */
	gpio_set_mode(GPIOA, GPIO_MODE_OUTPUT_2_MHZ, GPIO_CNF_OUTPUT_PUSHPULL, GPIO12);
	gpio_clear(GPIOA, GPIO12); delay_ms(20);
	gpio_set_mode(GPIOA, GPIO_MODE_INPUT, GPIO_CNF_INPUT_FLOAT, GPIO12);
}

int main(void) {
	hw_init(); delay_ms(50); cr_find();
	usbd_device *usb = usbd_init(&st_usbfs_v1_usb_driver, &dev_desc, &cfg_desc, usb_str, 3, ctrl_buf, sizeof(ctrl_buf));
	usbd_register_set_config_callback(usb, set_cfg);
	gpio_set_mode(USB_PU_PORT, GPIO_MODE_OUTPUT_2_MHZ, GPIO_CNF_OUTPUT_PUSHPULL, USB_PU_PIN);
	gpio_clear(USB_PU_PORT, USB_PU_PIN);
	static uint8_t out[260];
	for (;;) {
		usbd_poll(usb);
		if (rx_len < 2 || rx_len < rx[1] + 2u) continue;
		int n;
		if (rx[0] == 0xF0) { cr_wake(); out[0] = 0xF0; out[1] = 0; n = 2; }
		else if (rx[0] == 0xF1) { if (lk < 0) cr_find(); out[0] = 0xF1; out[1] = 1; out[2] = (uint8_t)lk; n = 3; }
		else if (!(n = cr_cmd(rx, out))) { out[0] = 0xFE; out[1] = 0; n = 2; }
		rx_len = 0;
		for (int p = 0; p < n; ) {
			int c = n - p > 64 ? 64 : n - p;
			while (!usbd_ep_write_packet(usb, 0x82, out + p, c)) usbd_poll(usb);
			p += c;
		}
	}
}
