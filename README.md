opam-compiler
=============

An opam plugin to manage compiler installations.

It can be used to create switches from various sources such as the main
repository, ocaml-multicore, or a local directories. It can use tag names,
branch names, or PR numbers to specify what to install.

<!-- TODO(docs): opam-compiler no longer has a reinstall subcommand (removed in 7f0d8f6, "Remove reinstall command"); this paragraph should drop the two reinstall modes. -->
Once installed, these are normal opam switches, and one can install packages in
them. To iterate on a compiler feature and try opam packages at the same time,
it supports to ways to reinstall the compiler: either a safe and slow technique
that will reinstall all packages, or a quick way that will just overwrite the
compiler in place.

Installing
----------

This is an [opam plugin](https://opam.ocaml.org/doc/Manual.html#Plugins).

Once installed, it will be available globally using `opam compiler ARGS`.
To install it, either run `opam install opam-compiler` to use the opam-repository
version or pin it to get a development version:

    opam pin add opam-compiler 'git+https://github.com/ocaml-opam/opam-compiler.git'

Creating a switch
-----------------

`opam compiler create` is a wrapper around `opam switch create` that will use a
custom OCaml compiler. The documentation can be found [here](doc/create.txt), but as an
example, the following is recognised:

    # Use this pull request number
    opam compiler create '#1234'

    # Use this branch
    opam compiler create 'myself/ocaml:mybranch'

    # Use this pull request
    opam compiler create https://github.com/ocaml/ocaml/pull/10831

It will try determine a switch name and description from the source name, but it
is also possible to pass an explicit switch name:

    # Use an explicit switch name
    opam compiler create '#1234' --switch optimize-list-map

The resulting switch can be used like a normal switch: one can install packages,
update them, etc.

By default, the compiler will be built using a plain `./configure` command,
which will create a vanilla compiler. It is possible to override this:

    # Just build the bytecode compiler from a pull request
    opam compiler create '#1234' --configure-command "./configure --disable-native-compiler"

    # Build the native compiler with flambda and frame pointers
    opam compiler create '#1234' --configure-command "./configure --enable-flambda --enable-frame-pointers"

OxCaml
------

Sources in a repository named `oxcaml` build
[OxCaml](https://github.com/oxcaml/oxcaml):

    # Use the main branch
    opam compiler create 'oxcaml:main'

    # Use this pull request
    opam compiler create 'oxcaml#1234'

OxCaml has no compiler opam file in its source tree, so the build recipe comes
from [oxcaml/opam-repository](https://github.com/oxcaml/opam-repository): the
`oxcaml-compiler` release nearest in history to the source among those that can
build it. The switch description records which one was used.
`--configure-command` and `--with` are not supported. Set `GITHUB_TOKEN` to
avoid GitHub's API rate limit (since creating an OxCaml switch requires
additional API calls to find the recipe).
