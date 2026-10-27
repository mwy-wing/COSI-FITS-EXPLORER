# Synthetic demo

[Download synthetic-events.fits](https://github.com/mwy-wing/COSI-FITS-EXPLORER/releases/download/v0.1.1/synthetic-events.fits), then choose **Open file…** in COSI Explorer.

The file contains 1,200 invented events, sampled every 0.5 seconds, with EVENTID, TIME, ENERGY, NUMHIT, and EVENTCLASS columns. Time is elapsed seconds starting at zero; energy is an illustrative signal in keV. These values are not observations, a calibration source, or a physical simulation. The example is distributed under the project's MIT license.

Try **Column values → Time → ENERGY**, switch X to **Row number**, then try **Histogram**. Filter to **Compton (0)** to see how selected original row numbers keep their gaps.

To regenerate with CFITSIO installed:

```sh
cmake -S . -B build
cmake --build build --target cosi-make-demo
./build/cosi-make-demo /tmp/synthetic-events.fits
```

The generator refuses to overwrite an existing file. Its random seed is fixed; floating point results may vary slightly between platforms.
