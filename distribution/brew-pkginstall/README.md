## Purpose

Install package(s) from an specific brew build.

## Parameters

The test supports the following environment variables:

- `BUILD_NVR`: Required, the build nvr with the package(s) to be installed.
- `PACKAGES_NAMES`: Optional, packages from the build that should be installed. Default to `BUILD_NVR`.
