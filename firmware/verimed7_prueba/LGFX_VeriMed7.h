// Configuracion de pantalla para VIEWE UEDX80480070E-WB-A V1.1 (7", 800x480, ESP32-S3)
// Libreria: LovyanGFX (Gestor de librerias -> "LovyanGFX" de lovyan03)
//
// Pines tomados de la configuracion oficial de Espressif (ESP32_Display_Panel,
// BOARD_VIEWE_UEDX80480070E_WB_A.h):
//   Panel RGB 16 bits (ST7262/EK9716), tactil GT911 por I2C (SDA 19, SCL 20),
//   retroiluminacion PWM en GPIO 2.
#pragma once

#if !defined(CONFIG_IDF_TARGET_ESP32S3)
#error "Placa incorrecta: en Herramientas -> Placa elige 'ESP32S3 Dev Module' (no 'ESP32 Dev Module')."
#endif

#define LGFX_USE_V1
#include <LovyanGFX.hpp>
#include <lgfx/v1/platforms/esp32s3/Panel_RGB.hpp>
#include <lgfx/v1/platforms/esp32s3/Bus_RGB.hpp>
#if __has_include(<driver/i2c_master.h>)
 #include <driver/i2c_master.h>
#else
 #include <driver/i2c.h>
#endif

// Frecuencia del reloj de pixeles. Si la imagen parpadea o se desplaza, baja a 14 MHz.
#ifndef VERIMED7_PCLK_HZ
#define VERIMED7_PCLK_HZ 16000000
#endif

class LGFX_VeriMed7 : public lgfx::LGFX_Device {
public:
  lgfx::Bus_RGB     _bus;
  lgfx::Panel_RGB   _panel;
  lgfx::Light_PWM   _luz;
  lgfx::Touch_GT911 _tactil;

  LGFX_VeriMed7(void) {
    {
      auto cfg = _panel.config();
      cfg.memory_width  = 800;
      cfg.memory_height = 480;
      cfg.panel_width   = 800;
      cfg.panel_height  = 480;
      cfg.offset_x = 0;
      cfg.offset_y = 0;
      _panel.config(cfg);
    }
    {
      auto cfg = _panel.config_detail();
      cfg.use_psram = 1;          // el framebuffer (750 KB) va en la PSRAM
      _panel.config_detail(cfg);
    }
    {
      auto cfg = _bus.config();
      cfg.panel = &_panel;
      // Azul B0..B4
      cfg.pin_d0  = GPIO_NUM_8;
      cfg.pin_d1  = GPIO_NUM_3;
      cfg.pin_d2  = GPIO_NUM_46;
      cfg.pin_d3  = GPIO_NUM_9;
      cfg.pin_d4  = GPIO_NUM_1;
      // Verde G0..G5
      cfg.pin_d5  = GPIO_NUM_5;
      cfg.pin_d6  = GPIO_NUM_6;
      cfg.pin_d7  = GPIO_NUM_7;
      cfg.pin_d8  = GPIO_NUM_15;
      cfg.pin_d9  = GPIO_NUM_16;
      cfg.pin_d10 = GPIO_NUM_4;
      // Rojo R0..R4
      cfg.pin_d11 = GPIO_NUM_45;
      cfg.pin_d12 = GPIO_NUM_48;
      cfg.pin_d13 = GPIO_NUM_47;
      cfg.pin_d14 = GPIO_NUM_21;
      cfg.pin_d15 = GPIO_NUM_14;
      // Sincronismo
      cfg.pin_henable = GPIO_NUM_40;   // DE
      cfg.pin_vsync   = GPIO_NUM_41;
      cfg.pin_hsync   = GPIO_NUM_39;
      cfg.pin_pclk    = GPIO_NUM_42;
      cfg.freq_write  = VERIMED7_PCLK_HZ;
      // Tiempos del panel (configuracion oficial)
      cfg.hsync_pulse_width = 48;
      cfg.hsync_back_porch  = 40;
      cfg.hsync_front_porch = 88;
      cfg.vsync_pulse_width = 6;
      cfg.vsync_back_porch  = 26;
      cfg.vsync_front_porch = 10;
      // Polaridades: equivalentes a la configuracion oficial de Espressif (esp_lcd):
      //   esp_lcd hsync_idle_low=0 / vsync_idle_low=0 -> reposo en ALTO -> polarity = 1
      //   esp_lcd pclk_active_neg=1 (flanco de bajada) -> en LovyanGFX ese registro
      //   (lcd_ck_out_edge) lo controla pclk_idle_high, NO pclk_active_neg.
      cfg.hsync_polarity    = 1;
      cfg.vsync_polarity    = 1;
      cfg.de_idle_high      = 0;
      cfg.pclk_idle_high    = 1;       // flanco de bajada (clave para que se vea imagen)
      cfg.pclk_active_neg   = 1;
      _bus.config(cfg);
    }
    _panel.setBus(&_bus);
    {
      auto cfg = _luz.config();
      cfg.pin_bl = GPIO_NUM_2;
      cfg.invert = false;
      cfg.freq   = 44100;
      cfg.pwm_channel = 7;
      _luz.config(cfg);
    }
    _panel.light(&_luz);
    {
      auto cfg = _tactil.config();
      cfg.x_min = 0;   cfg.x_max = 799;
      cfg.y_min = 0;   cfg.y_max = 479;
      cfg.pin_int  = GPIO_NUM_NC;      // esta placa no conecta INT ni RST del GT911
      cfg.pin_rst  = GPIO_NUM_NC;
      cfg.bus_shared = false;
      cfg.offset_rotation = 0;
      cfg.i2c_port = I2C_NUM_0;
      cfg.pin_sda  = GPIO_NUM_19;
      cfg.pin_scl  = GPIO_NUM_20;
      cfg.freq     = 400000;
      cfg.i2c_addr = 0x5D;             // el driver prueba 0x5D y 0x14 automaticamente
      _tactil.config(cfg);
      _panel.setTouch(&_tactil);
    }
    setPanel(&_panel);
  }
};
