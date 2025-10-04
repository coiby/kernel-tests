# AMD Accelerators Include Library

This library provides shared functions and utilities for AMD accelerator testing, specifically designed for ROCm (Radeon Open Compute) installation and validation on RHEL 9 and RHEL 10 systems.

## Overview

The library includes functions for:

- Repository management (AMD GPU, ROCm, EPEL 10)
- Package installation and dependency resolution
- Environment configuration for AMD GPU development
- ROCm installation automation for different RHEL versions

## Main functions

- AmdROCmCleanUp: Cleans up existing ROCm installations and related packages.
- AmdROCmSetUp: Cleans up existing ROCm installations and related packages.

## Usage

To use the library (include.sh), source it in your shell script.
