/*
 * Overrides the default output status widget to show custom BT profile names
 * while keeping all other output indicators identical to upstream ZMK.
 */

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
LOG_MODULE_DECLARE(zmk, CONFIG_ZMK_LOG_LEVEL);

#include <zmk/display.h>
#include <zmk/display/widgets/output_status.h>
#include <zmk/event_manager.h>
#include <zmk/events/ble_active_profile_changed.h>
#include <zmk/events/endpoint_changed.h>
#include <zmk/usb.h>
#include <zmk/ble.h>
#include <zmk/endpoints.h>

static sys_slist_t widgets = SYS_SLIST_STATIC_INIT(&widgets);

struct output_status_state {
    struct zmk_endpoint_instance selected_endpoint;
    bool active_profile_connected;
    bool active_profile_bonded;
};

static const char *const profile_names[] = {
    "Work",
    "iPad",
    "Phone",
    "Game",
    "Spare",
};

static struct output_status_state get_state(const zmk_event_t *_eh) {
    return (struct output_status_state){.selected_endpoint = zmk_endpoints_selected(),
                                        .active_profile_connected =
                                            zmk_ble_active_profile_is_connected(),
                                        .active_profile_bonded = !zmk_ble_active_profile_is_open()};
    ;
}

static void set_status_symbol(lv_obj_t *label, struct output_status_state state) {
    char text[48] = {};

    switch (state.selected_endpoint.transport) {
    case ZMK_TRANSPORT_USB:
        strcat(text, LV_SYMBOL_USB);
        break;
    case ZMK_TRANSPORT_BLE: {
        int idx = state.selected_endpoint.ble.profile_index;
        const char *name = (idx >= 0 && idx < ARRAY_SIZE(profile_names)) ? profile_names[idx]
                                                                          : "Profile";
        const char *status_icon;

        if (state.active_profile_bonded) {
            status_icon = state.active_profile_connected ? LV_SYMBOL_OK : LV_SYMBOL_CLOSE;
        } else {
            status_icon = LV_SYMBOL_SETTINGS;
        }

        snprintf(text, sizeof(text), LV_SYMBOL_WIFI " %d %s %s", idx + 1, name, status_icon);
        break;
    }
    }

    lv_label_set_text(label, text);
}

static void output_status_update_cb(struct output_status_state state) {
    struct zmk_widget_output_status *widget;
    SYS_SLIST_FOR_EACH_CONTAINER(&widgets, widget, node) { set_status_symbol(widget->obj, state); }
}

ZMK_DISPLAY_WIDGET_LISTENER(widget_output_status, struct output_status_state,
                            output_status_update_cb, get_state)
ZMK_SUBSCRIPTION(widget_output_status, zmk_endpoint_changed);
#if defined(CONFIG_ZMK_BLE)
ZMK_SUBSCRIPTION(widget_output_status, zmk_ble_active_profile_changed);
#endif

int zmk_widget_output_status_init(struct zmk_widget_output_status *widget, lv_obj_t *parent) {
    widget->obj = lv_label_create(parent);

    sys_slist_append(&widgets, &widget->node);

    widget_output_status_init();
    return 0;
}

lv_obj_t *zmk_widget_output_status_obj(struct zmk_widget_output_status *widget) {
    return widget->obj;
}
