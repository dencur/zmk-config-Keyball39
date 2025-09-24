# Replace only the output status widget with a custom implementation.
# Everything else stays exactly as in upstream ZMK.
target_sources(app PRIVATE custom_output_status.c)
