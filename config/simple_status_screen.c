/*
 * Simple test status screen to verify OLED initialization
 */

#include <zmk/display/status_screen.h>
#include <zephyr/logging/log.h>

LOG_MODULE_DECLARE(zmk, CONFIG_ZMK_LOG_LEVEL);

lv_obj_t *zmk_display_status_screen(void) {
    LOG_DBG("Creating simple test status screen");
    
    lv_obj_t *screen = lv_obj_create(NULL);
    if (screen == NULL) {
        LOG_ERR("Failed to create LVGL screen object");
        return NULL;
    }
    
    // Create a simple label to test if LVGL/display works
    lv_obj_t *label = lv_label_create(screen);
    if (label != NULL) {
        lv_label_set_text(label, "TEST");
        lv_obj_align(label, LV_ALIGN_CENTER, 0, 0);
        LOG_DBG("Test label created successfully");
    } else {
        LOG_ERR("Failed to create test label");
    }
    
    LOG_DBG("Simple status screen initialization complete");
    return screen;
}
