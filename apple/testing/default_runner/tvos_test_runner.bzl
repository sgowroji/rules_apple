# Copyright 2019 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""tvOS test runner rule."""

load(
    "@build_bazel_rules_apple//apple:providers.bzl",
    "apple_provider",
)

visibility("public")

def _get_template_substitutions(*, device_type, os_version, testrunner):
    """Returns the template substitutions for this runner."""
    subs = {
        "device_type": device_type,
        "os_version": os_version,
        "testrunner_binary": testrunner,
    }
    return {"%(" + k + ")s": subs[k] for k in subs}

def _get_execution_environment(*, xcode_config):
    """Returns environment variables the test runner requires"""
    execution_environment = {}
    xcode_version = str(xcode_config.xcode_version())
    if xcode_version:
        execution_environment["XCODE_VERSION"] = xcode_version

    return execution_environment

def _tvos_test_runner_impl(ctx):
    """Implementation for the tvos_test_runner rule."""
    ctx.actions.expand_template(
        template = ctx.file._test_template,
        output = ctx.outputs.test_runner_template,
        substitutions = _get_template_substitutions(
            device_type = ctx.attr.device_type,
            os_version = ctx.attr.os_version,
            testrunner = ctx.executable._testrunner.short_path,
        ),
    )
    return [
        apple_provider.make_apple_test_runner_info(
            test_runner_template = ctx.outputs.test_runner_template,
            execution_requirements = ctx.attr.execution_requirements,
            execution_environment = _get_execution_environment(
                xcode_config = ctx.attr._xcode_config[apple_common.XcodeVersionConfig],
            ),
        ),
        DefaultInfo(
            runfiles = ctx.runfiles(
                files = [ctx.file._testrunner],
            ),
        ),
    ]

tvos_test_runner = rule(
    _tvos_test_runner_impl,
    attrs = {
        "device_type": attr.string(
            default = "",
            doc = """
The device type of the tvOS simulator to run test. The supported types correspond
to the output of `xcrun simctl list devicetypes`. E.g., Apple TV, AppleTV 4K.
By default, it is the latest supported Apple TV type.'
""",
        ),
        "execution_requirements": attr.string_dict(
            allow_empty = False,
            default = {"requires-darwin": ""},
            doc = """
Dictionary of strings to strings which specifies the execution requirements for
the runner. In most common cases, this should not be used.
""",
        ),
        "os_version": attr.string(
            default = "",
            doc = """
The os version of the tvOS simulator to run test. The supported os versions
correspond to the output of `xcrun simctl list runtimes`. ' 'E.g., 11.2, 9.1.
By default, it is the latest supported version of the device type.'
""",
        ),
        "_test_template": attr.label(
            default = Label(
                "@build_bazel_rules_apple//apple/testing/default_runner:tvos_test_runner.template.sh",
            ),
            allow_single_file = True,
        ),
        "_testrunner": attr.label(
            default = Label(
                "@xctestrunner//file",
            ),
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            doc = """
It is the rule that needs to provide the AppleTestRunnerInfo provider. This
dependency is the test runner binary.
""",
        ),
        "_xcode_config": attr.label(
            default = configuration_field(
                fragment = "apple",
                name = "xcode_config_label",
            ),
        ),
    },
    outputs = {
        "test_runner_template": "%{name}.sh",
    },
    fragments = ["apple", "objc"],
    doc = """
Rule to identify a tvOS runner that runs tests for tvOS.

The runner will create a new simulator according to the given arguments to run
tests.

Outputs:
  AppleTestRunnerInfo:
    test_runner_template: Template file that contains the specific mechanism
        with which the tests will be performed.
    execution_requirements: Dictionary that represents the specific hardware
        requirements for this test.
  Runfiles:
    files: The files needed during runtime for the test to be performed.
""",
)
