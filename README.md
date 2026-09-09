# maona4linux

Linux investigation and support tooling for the MAONO/DCMT USB Condenser Microphone identified by USB VID/PID `31b2:0011`.

The device already exposes standard USB Audio interfaces and Linux binds them to `snd-usb-audio`. It also exposes a HID interface handled by `usbhid`. This project begins by finding the layer that actually fails; it will not replace the standard audio stack without evidence that the transport is non-standard.

## Current status

The investigation is at the evidence-gathering stage. Reports so far show:

- USB Audio interfaces `0` and `1`;
- HID interface `3`, with interface `2` absent;
- Linux warnings about the non-contiguous interface numbering;
- an ALSA capture device and a PipeWire mono source.

These observations do not yet prove that a kernel quirk is necessary. Follow the work in the [project roadmap](https://github.com/Circuit-Overtime/maona4linux/issues/9).

## Collect diagnostics

Requirements vary by distribution. The collector uses available tools and records missing optional commands instead of failing the whole run. Useful packages commonly provide `lsusb`, `usb-devices`, `arecord`, `amixer`, `wpctl`, and `pactl`.

```bash
./scripts/collect-debug.sh
```

By default, results are written to a new timestamped directory under `captures/linux/`. Choose another parent directory with:

```bash
./scripts/collect-debug.sh --output-dir /tmp/maono-captures
```

The collector is read-only: it does not change mixer settings, send HID reports, reload modules, or alter system configuration. Some descriptor details may be unavailable without elevated USB permissions; run it as your normal desktop user first.

Before publishing a bundle, review it for hostnames, usernames, USB serial numbers, unrelated audio devices, and application metadata. Do not attach a bundle you have not inspected.

## Test raw ALSA capture

After collecting diagnostics, bypass PipeWire and record directly from the dynamically discovered ALSA device:

```bash
./scripts/alsa-test.sh
```

See [docs/testing.md](docs/testing.md) for result interpretation.

## Design constraints

- Match the device by VID/PID, never by its product string alone.
- Never assume ALSA card `2`, USB path `1-10`, or a fixed `/dev/hidrawX` node.
- Test raw ALSA before diagnosing PipeWire or applications.
- Keep HID discovery read-only until commands are supported by controlled captures.
- Prefer no kernel patch; if one is required, scope it to `31b2:0011`.

## License

This project is licensed under `GPL-2.0-only`. See [LICENSE](LICENSE).
