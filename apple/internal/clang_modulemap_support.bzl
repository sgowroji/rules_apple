# Copyright 2023 The Bazel Authors. All rights reserved.
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

"""Support methods for generating Clang module maps."""

load(
    "@build_bazel_rules_apple//apple/internal:intermediates.bzl",
    "intermediates",
)

visibility([
    "//apple/...",
    "//test/...",
])

def _get_link_declarations(dylibs = [], frameworks = []):
    """Returns the module map lines that link to the given dylibs and frameworks.

    Args:
        dylibs: A sequence of library names (which must begin with "lib") that will be referenced in
            the module map.
        frameworks: A sequence of framework names that will be referenced in the module map.

    Returns:
        A list of "link" and "link framework" lines that reference the given libraries and
        frameworks.
    """
    link_lines = []

    for dylib in dylibs:
        if not dylib.startswith("lib"):
            fail("Linked libraries must start with 'lib' but found %s" % dylib)
        link_lines.append('link "%s"' % dylib[3:])
    for framework in frameworks:
        link_lines.append('link framework "%s"' % framework)

    return link_lines

def _get_umbrella_header_declaration(basename):
    """Returns the module map line that references an umbrella header.

    Args:
        basename: The basename of the umbrella header file to be referenced in the module map.

    Returns:
        The module map line that references the umbrella header.
    """
    return 'umbrella header "%s"' % basename

def _modulemap_header_interface_contents(
        framework_modulemap,
        module_name,
        sdk_dylibs,
        sdk_frameworks,
        umbrella_header_filename):
    """Returns the contents of a header file interface within a Clang modulemap for a framework.

    Args:
        framework_modulemap: Boolean to indicate if the generated modulemap should be for a
            framework instead of a library or a generic module. Defaults to `True`.
        module_name: The name of the module to declare in the module map file.
        sdk_dylibs: A list of system dylibs to list in the module.
        sdk_frameworks: A list of system frameworks to list in the module.
        umbrella_header_filename: The basename of the umbrella header file, or None if there is no
            umbrella header.
    """
    declarations = []
    if umbrella_header_filename:
        declarations.extend([
            _get_umbrella_header_declaration(umbrella_header_filename),
            "\n",
        ])
    declarations.extend([
        "export *",
        "module * { export * }",
    ])
    declarations.extend(_get_link_declarations(sdk_dylibs, sdk_frameworks))

    return (
        "{module_with_qualifier} {module_name} {{\n".format(
            module_with_qualifier = "framework module" if framework_modulemap else "module",
            module_name = module_name,
        ) +
        "\n".join(["  " + decl for decl in declarations]) +
        "\n}\n"
    )

def _create_umbrella_header(*, actions, output, public_hdrs):
    """Creates an umbrella header that imports a list of other headers.

    This uses quotes instead of angled brackets to reference headers, currently to support existing
    behavior with regards to "static frameworks", which is corrected to act as a module-level import
    when declared as an umbrella header in a Clang module map.

    Args:
        actions: The `actions` module from a rule or aspect context.
        output: A declared `File` to which the umbrella header will be written.
        public_hdrs: A list of header files to be imported by the umbrella header.
    """
    import_lines = ["#import \"{header_file}\"".format(
        header_file = f.basename,
    ) for f in sorted(public_hdrs)]
    content = "\n".join(import_lines) + "\n"
    actions.write(output = output, content = content)

def _exported_headers(
        *,
        public_hdrs,
        generated_umbrella_header_file):
    """Determines if the generated umbrella header needs to be an output of public headers.

    Args:
        public_hdrs: The list of headers to bundle.
        generated_umbrella_header_file: The umbrella header file, or None if there is no umbrella
            header.
    """
    for public_hdr in public_hdrs:
        if public_hdr.basename == generated_umbrella_header_file.basename:
            return public_hdrs
    return public_hdrs + [generated_umbrella_header_file]

def _process_headers(
        *,
        actions,
        label_name,
        module_name,
        output_discriminator,
        public_hdrs):
    """Validates the umbrella header against a set of public headers, generating one if necessary.

    Args:
        actions: The `actions` module from a rule or aspect context.
        label_name: Name of the target being built.
        module_name: The name of the module to reference in an umbrella header, if one is generated.
        output_discriminator: A string to differentiate between different target intermediate files
            or `None`.
        public_hdrs: A list of public headers to present in addition to the generated header. Useful
            for mixed interface Swift and Objective-C SDKs. Optional.

    Returns:
        A tuple where the first field is a list of Files representing headers that need to be
        bundled, and the second field is a String representing the filename of the umbrella header
        or None if an umbrella header was not found.
    """
    if not public_hdrs:
        return ([], None)

    # Automatically generate an umbrella header for the provided publicly visible headers, in the
    # absence of a user-defined umbrella header.
    umbrella_header_filename = "{}.h".format(module_name)
    generated_umbrella_header_file = intermediates.file(
        actions = actions,
        target_name = label_name,
        output_discriminator = output_discriminator,
        file_name = umbrella_header_filename,
    )
    _create_umbrella_header(
        actions = actions,
        output = generated_umbrella_header_file,
        public_hdrs = public_hdrs,
    )

    # Don't bundle the umbrella header if there is only one public header with the same name.
    if len(public_hdrs) == 1 and public_hdrs[0].basename == umbrella_header_filename:
        return (public_hdrs, public_hdrs[0].basename)

    export_headers = _exported_headers(
        public_hdrs = public_hdrs,
        generated_umbrella_header_file = generated_umbrella_header_file,
    )
    return (export_headers, umbrella_header_filename)

clang_modulemap_support = struct(
    process_headers = _process_headers,
    modulemap_header_interface_contents = _modulemap_header_interface_contents,
)