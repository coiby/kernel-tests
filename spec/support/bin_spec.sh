#!/bin/bash
eval "$(shellspec - -c) exit 1"

Describe 'spec/support/bin/dnf'
    # arguments
    # 1 - dnf arguments
    # 2 - dnf package name
    # 3 - expected arguments with globing
    # 4 - expected arguments when preventing globing
    Parameters
        "install -y" "bash" "install -y bash" "'install -y' bash"
        "install -y" "bash*" "install -y 'bash*'" "'install -y' 'bash*'"
    End
    It "can call dnf with $1 $2 (intentional globbing and word splitting)"
        # shellcheck disable=SC2086
        When call dnf $1 $2
        The line 1 should equal "dnf $3"
        The status should be success
    End
    It "can call dnf with \"$1\" \"$2\" (prevent globbing and word splitting)"
        # The dnf call is wrong, dnf command would fail, but the command call
        # is the same as would be called in bash
        When call dnf "$1" "$2"
        The line 1 should equal "dnf $4"
        The status should be success
    End
End
