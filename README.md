# Red Hat Kernel QE and CKI kernel tests repository

The main branch is continuously synced to the [internal
mirror](https://documentation.internal.cki-project.org/docs/test-maintainers/repository-setup/#mirroring-of-kernel-tests).

<details>
<summary>Click here for an example on how to trigger a Beaker job with it.</summary>

```xml
<job>
  <whiteboard>Beaker job for https://gitlab.com/redhat/centos-stream/tests/kernel/kernel-tests</whiteboard>
  <recipeSet>
    <recipe ks_meta="redhat_ca_cert">
      <distroRequires>
        <distro_arch op="=" value="x86_64"/>
        <variant op="=" value="BaseOS"/>
        <distro_family op="=" value="CentOSStream9"/>
      </distroRequires>
      <hostRequires/>
      <task name="/test/misc/machineinfo">
        <fetch url="https://${internal_gitlab_url}/api/v4/projects/kernel-qe%2fkernel-tests-public/repository/archive.zip?sha=refs/heads/main#test/misc/machineinfo"/>
        <params/>
      </task>
    </recipe>
  </recipeSet>
</job>
```
</details>

## How to run tests
Here is a list of common prerequisites for all beaker tests. Test-specific dependencies and steps can be found in the README.md within each test's directory.
~~~
$ sudo wget -O /etc/yum.repos.d/beaker-client.repo https://beaker-project.org/yum/beaker-client-Fedora.repo
$ sudo wget -O /etc/yum.repos.d/beaker-harness.repo https://beaker-project.org/yum/beaker-harness-Fedora.repo
$ sudo dnf install -y beaker-client beakerlib restraint-rhts
~~~

### How to check the tests

Every time a test is pushed it gets automatically checked for syntax or format
errors with [ShellCheck](https://github.com/koalaman/shellcheck) or [yamllint](https://www.redhat.com/sysadmin/check-yaml-yamllint) depending on the file type. It's convenient
to use it locally before to push the code, to save some time and be able to quickly
catch misspellings and silly errors.

To check locally for those errors for shell scripts it's recommended to install `ShellCheck` with
the package manager (e.g. `dnf install ShellCheck`) and to run this line in the
directory of the changed code:

```shell
$ shellcheck -S error *.sh
```

If there are more directories with scripts or libraries, they can be checked
recursively with the following:

```shell
$ find -name '*.sh' -exec shellcheck -S error {} +
```
Also, to check bash lines ending with white spaces use command:
```shell
$ grep -ne '\s$' <filename>
```

To check lint for yaml files, use yamllint:
 ```shell
$ yamllint -s <filename>
```


## Test onboarding

Currently, all onboarded tests must use the following combinations of
result/status fields:

* SKIP/COMPLETED if the test requirements aren't fulfilled (eg. test is running
on incompatible architecture/hardware)
* PASS/COMPLETED if the test finished successfully
* WARN/ABORTED in case of infrastructure issues or other errors (eg. the test
checks out a git repo and the git server is unavailable)
* WARN/COMPLETED or FAIL/COMPLETED in case of any test failures, based on how
serious they are (left to decide by test authors)

See examples below to properly abort or skip in beaker:
### Abort task if infrastructure failure is task only related
~~~
if [ $? -ne 0 ]; then
    echo "Aborting test because $reason"
    rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
    rstrnt-abort --server $RSTRNT_RECIPE_URL/tasks/$RSTRNT_TASKID/status
fi
~~~

### Abort recipe if infrastructure failure affects the entire recipe
~~~
if [ $? -ne 0 ]; then
    echo "Aborting recipe because $reason"
    rstrnt-report-result "${RSTRNT_TASKNAME}" WARN
    rstrnt-abort recipe
fi
~~~

### Skip the task (e.g. testing with unsupported hardware)
~~~
if [ $? -ne 0 ]; then
    echo "Skipping test because $reason"
    rstrnt-report-result "${RSTRNT_TASKNAME}" SKIP
    exit 0
fi
~~~

When onboarding a test, please check especially the point about infrastructure
issues: a lot of tests simply report a warning if eg. external server can’t be
reached and then continue. This kind of situation falls under infrastructure
issues and the test must use the WARN/ABORTED combination, otherwise the
infrastructure problem is reported to people as a bug in their code!

The order of Beaker tasks in the XML determines if the task is a preparation for
the testing or a test. Anything after kpkginstall task is treated as a test and
must follow the rules above. Anything except PASS before kpkginstall is treated
as infrastructure issue. Machineinfo (to get HW specification) is ran before
kpkginstall, so the same logic applies there. PANIC during kpkginstall means the
kernel is bad (can't boot).

In addition, please use the following guidelines while onboarding or updating
a test:
* If updating an existing test, be sure to trigger the bot to test related
  changes to verify nothing broke, the bot attaches to the MR and will provide
  instructions to trigger. Ask a project member with privileges to do so or
  request access for these rights
* Be sure to only use [Restraint compatible commands][01] and metadata vs
  Legacy RHTS/Makefile
* Use [cki lib](cki_lib) for common tasks
* Be sure there is nothing confidential and complies with open source
  guidelines, including a valid license header (e.g. GPLv3)
* Verify the test can be run stand alone without any internal dependencies to
  enable external contributors to reproduce failures

[01]: https://restraint.readthedocs.io/en/latest/commands.html#command-usage
