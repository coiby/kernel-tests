# Enable repository that contains kernel packages for running gcov kernel
Test Maintainer: [Bruno Goncalves](mailto:bgoncalv@redhat.com)

## How to run it
The task does the following:
 * Enable kernel gcov repository for the running kernel (it assumes kernel gcov is already running)

### Install dependencies
Please refer to the top-level README.md for common dependencies.
```bash
root# bash ../../cki_bin/pkgs_install.sh metadata
```

### Execute the test
```bash
bash ./runtest.sh
```

