# ACPI Enabled Test
Verify that ACPI is enabled at boot.  This is a sanity check for aarch64 (64-bit ARM) servers which can use either ACPI or \
DeviceTree, and RHEL does not support DeviceTree, so a failure here indicates a firmware problem with the server.

### Execute the test
```bash
bash ./runtest.sh
```
