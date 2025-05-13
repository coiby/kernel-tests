# Math testing of the AMD in-tree driver using rocBLAS
Use rocBLAS to test mathematical operations with the AMD in-tree driver 

## How to run it
Please refer to the top-level README.md for common dependencies.

### Install dependencies
```bash
root# bash ../../cki_bin/pkgs_install.sh metadata
```

### Execute the test
```bash
bash ./runtest.sh
```

### Variables
```bash
ROCBLAS_SKIP_BUILD: If true, skips build phase
ROCBLAS_FULL_TEST: If true, enables full rocBLAS test (Long, and can hang the SUT)
```
