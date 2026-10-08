# Peeker

A useful little Mac tool. Lives in the menu bar.

## Download

1. Grab `Peeker.zip` from the [latest release](../../releases/latest) and unzip it.
2. Drag `Peeker.app` into Applications.
3. The first time, right-click it → **Open** → **Open** (it isn't notarised, so macOS will ask).
4. Allow camera access when prompted.

Then click the 👁 in the menu bar and run **Calibrate Eyes…** once.

## Build from source

Needs macOS 13+ and Xcode Command Line Tools.

```sh
git clone https://github.com/TomWhitticase/peeker.git
cd peeker
./build.sh
open build/Peeker.app
```
