# Captures

This directory holds sanitized evidence used to understand the device.

- `linux/` is for USB descriptors, ALSA capabilities, logs, and PipeWire state.
- `windows/` is for controlled USBPcap/Wireshark captures used to compare one hardware-control change at a time.

Timestamped local bundles and packet captures are ignored by default because they can contain hostnames, device serial numbers, unrelated hardware details, and application metadata. Review and minimize every capture before deliberately adding it to Git.

