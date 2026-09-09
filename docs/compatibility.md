# Compatibility result

The MAONO/DCMT USB Condenser Microphone (`31b2:0011`) works with Linux's standard USB Audio driver. A device-specific kernel audio driver or quirk is not required for the tested capture path.

## Verified stack

```text
MAONO/DCMT microphone
        ↓
snd-usb-audio
        ↓
ALSA
        ↓
PipeWire and applications
```

Raw ALSA hardware tests successfully produced clear recordings with:

| Format | Channels | Rate | Result |
| --- | ---: | ---: | --- |
| `S16_LE` | 1 | 48 kHz | Clear |
| `S24_3LE` | 1 | 48 kHz | Captured successfully |

The device advertises mono `S16_LE` and `S24_3LE` capture at 44.1, 48, 88.2, 96, 176.4, and 192 kHz. This project defaults to `S24_3LE` at 48 kHz as the best practical balance for voice and common production workflows.

Linux reports a gap in interface numbering because the device exposes Audio interfaces `0` and `1` and HID interface `3`, with interface `2` absent. The warning did not prevent enumeration, driver binding, ALSA capability discovery, or clear recording in the verified tests.

Proprietary HID controls were not required for basic audio and are outside the completed scope. They can be investigated later if a concrete missing hardware-control feature is identified.
