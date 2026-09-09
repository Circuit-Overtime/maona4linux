# Testing

## Raw ALSA baseline

Run this before testing PipeWire, WirePlumber, OBS, or other applications:

```bash
./scripts/alsa-test.sh
```

The script discovers USB ID `31b2:0011`, resolves its ALSA capture PCM through sysfs, reads the advertised capture parameters from `/proc/asound`, probes the hardware, and records ten seconds. It does not assume a card number, change mixer controls, or route through PipeWire.

Results are stored in a new `captures/linux/YYYY-MM-DD-HHMMSS-alsa/` directory. Use `--duration SECONDS` or `--output-dir DIRECTORY` when needed.

Play the resulting WAV with a tool such as:

```bash
aplay captures/linux/YYYY-MM-DD-HHMMSS-alsa/capture-*.wav
```

Record whether it contains the expected signal, silence, distortion, dropouts, incorrect speed, or timing drift. Attach the text logs to issue #1 after reviewing them for identifying host information. Audio samples should only be shared deliberately.

If this raw ALSA test is correct but PipeWire recording is not, treat the failure as a PipeWire/WirePlumber problem rather than a kernel-audio failure.

