# Only override the output status widget to customize BT profile names
# All other display functionality remains unchanged from main branch
target_sources(app PRIVATE custom_output_status.c)