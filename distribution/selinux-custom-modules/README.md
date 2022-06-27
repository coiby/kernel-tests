# Setup task for installing custom SElinux modules

## How to run it
The task does the following:
 * Build the custom module using the pre-built .te file from audit2allow
 * Install the SELinux custom module by running 'semodule -i module.pp'

### Install dependencies
Please refer to the top-level README.md for common dependencies.
```bash
root# bash ../../cki_bin/pkgs_install.sh metadata
```

### Execute the test
```bash
bash ./runtest.sh
```

