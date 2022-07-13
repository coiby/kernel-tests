# Real Time Unit Testing

The `framework/rtut.py` file provides a framework for tests defined in
the `pkg` directory to implement in order to execute unittests for Real
Time userspace packages using python's unittest framework.

## How To Add a New Unit Test

1. `mkdir pkg/$pkgname && cd pkg/$pkgname`
2. `ln -s ../../framework/rtut.py .`
3. Define a new `test.py` file that:
   * Defines a class that implements `rtut.RTUnitTest`
   * Creates `setUp` and `tearDown` functions if needed
   * Implements `test_*` unittest functions that call `run_cmd`, optionally setting `status=#` for commands expecting to return non-zero
   * Invokes `.run_unittests()` on the class object in the main function
   * Passes `pylint -d C0115,C0116 test.py` with a 10.00/10 score
4. Define a `metadata` file for restraint execution

> Note: for step 2 we opt to use a symlink instead of importing `rtut` from the parent directory via `sys.path.append(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))` as we want restraint to only package `rtut.py` + the test itself for execution.  This same reasoning applies for why we have chosen not to implement the tests as modules of `rtut.py` instead.

## How To Run Unit Tests

Simply `cd` to the directory of the package to test and run `python3 test.py`.
