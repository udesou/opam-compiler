By default, the switch name is inferred from the branch:

  $ opam-compiler create --dry-run USER/REPO:BRANCH
  Run: OPAMCLI=2.0 opam switch create USER-REPO-BRANCH --empty --description "[opam-compiler] USER/REPO:BRANCH"
  Run: OPAMCLI=2.0 opam pin add --switch USER-REPO-BRANCH --yes ocaml-variants git+https://github.com/USER/REPO#BRANCH
  Run: OPAMCLI=2.0 opam switch set-base --switch USER-REPO-BRANCH ocaml-variants

It can also be set explicitly:

  $ opam-compiler create --dry-run USER/REPO:BRANCH --switch SWITCH-NAME
  Run: OPAMCLI=2.0 opam switch create SWITCH-NAME --empty --description "[opam-compiler] USER/REPO:BRANCH"
  Run: OPAMCLI=2.0 opam pin add --switch SWITCH-NAME --yes ocaml-variants git+https://github.com/USER/REPO#BRANCH
  Run: OPAMCLI=2.0 opam switch set-base --switch SWITCH-NAME ocaml-variants

Github PR numbers are also accepted:

  $ opam-compiler create --dry-run '#1234'
  Run: OPAMCLI=2.0 opam switch create ocaml-ocaml-1234 --empty --description "[opam-compiler] ocaml/ocaml#1234 - Title of ocaml-ocaml-1234"
  Run: OPAMCLI=2.0 opam pin add --switch ocaml-ocaml-1234 --yes ocaml-variants git+https://github.com/user-ocaml-ocaml-1234/repo-ocaml-ocaml-1234#branch-ocaml-ocaml-1234
  Run: OPAMCLI=2.0 opam switch set-base --switch ocaml-ocaml-1234 ocaml-variants

Github source urls are also accepted:

  $ opam-compiler create --dry-run 'https://github.com/ocaml/ocaml/pull/10831'
  Run: OPAMCLI=2.0 opam switch create ocaml-ocaml-10831 --empty --description "[opam-compiler] ocaml/ocaml#10831 - Title of ocaml-ocaml-10831"
  Run: OPAMCLI=2.0 opam pin add --switch ocaml-ocaml-10831 --yes ocaml-variants git+https://github.com/user-ocaml-ocaml-10831/repo-ocaml-ocaml-10831#branch-ocaml-ocaml-10831
  Run: OPAMCLI=2.0 opam switch set-base --switch ocaml-ocaml-10831 ocaml-variants

An explicit configure step can be passed:

  $ opam-compiler create --dry-run USER/REPO:BRANCH --configure-command "./configure --enable-x"
  Run: OPAMCLI=2.0 opam switch create USER-REPO-BRANCH --empty --description "[opam-compiler] USER/REPO:BRANCH"
  Run: OPAMEDITOR=sed -i -e 's#"./configure"#"./configure" "--enable-x"#g' OPAMCLI=2.0 opam pin add --switch USER-REPO-BRANCH --yes ocaml-variants git+https://github.com/USER/REPO#BRANCH --edit
  Run: OPAMCLI=2.0 opam switch set-base --switch USER-REPO-BRANCH ocaml-variants

Known variants can be supported using --with:

  $ opam-compiler create --dry-run USER/REPO:BRANCH --with afl
  Run: OPAMCLI=2.0 opam switch create USER-REPO-BRANCH --empty --description "[opam-compiler] USER/REPO:BRANCH"
  Run: OPAMEDITOR=sed -i -e 's#"./configure"#"./configure" "--with-afl"#g' OPAMCLI=2.0 opam pin add --switch USER-REPO-BRANCH --yes ocaml-variants git+https://github.com/USER/REPO#BRANCH --edit
  Run: OPAMCLI=2.0 opam switch set-base --switch USER-REPO-BRANCH ocaml-variants

Several of them can be specified:

  $ opam-compiler create --dry-run USER/REPO:BRANCH --with flambda,nnp
  Run: OPAMCLI=2.0 opam switch create USER-REPO-BRANCH --empty --description "[opam-compiler] USER/REPO:BRANCH"
  Run: OPAMEDITOR=sed -i -e 's#"./configure"#"./configure" "--enable-flambda" "--disable-naked-pointers"#g' OPAMCLI=2.0 opam pin add --switch USER-REPO-BRANCH --yes ocaml-variants git+https://github.com/USER/REPO#BRANCH --edit
  Run: OPAMCLI=2.0 opam switch set-base --switch USER-REPO-BRANCH ocaml-variants

An unrecognized variant is rejected:

  $ opam-compiler create --dry-run USER/REPO:BRANCH --with something > /dev/null 2>&1
  [124]

It is not possible to mix --configure-command and --with:

  $ opam-compiler create --dry-run USER/REPO:BRANCH --configure-command "./configure --enable-x" --with afl
  opam-compiler: --configure-command and --with cannot be passed together.
  [124]

A source in a repository named oxcaml is built with an oxcaml-compiler recipe
borrowed from oxcaml/opam-repository:

  $ TMPDIR=. opam-compiler create --dry-run oxcaml:main
  Run: OPAMCLI=2.0 opam switch create oxcaml-oxcaml-main --empty --description "[opam-compiler] oxcaml/oxcaml:main at 0401b35d00b0, built with oxcaml-compiler.DRY-RUN from oxcaml/opam-repository@a56316deae95" --repositories=oxcaml-a56316deae95=git+https://github.com/oxcaml/opam-repository.git#a56316deae95dcf4260cdf7df975002aa56316de,default
  Run: OPAMEDITOR=cp './opam-compiler-oxcaml-oxcaml-main.opam' OPAMCLI=2.0 opam pin add --switch oxcaml-oxcaml-main --yes oxcaml-compiler.DRY-RUN git+https://github.com/oxcaml/oxcaml#main --edit
  Run: OPAMCLI=2.0 opam switch set-base --switch oxcaml-oxcaml-main oxcaml-compiler

OxCaml recipes have their own configure step, so it cannot be replaced:

  $ opam-compiler create --dry-run oxcaml:main --with afl
  opam-compiler: internal error, uncaught exception:
                 Failure("--configure-command and --with are not supported for OxCaml sources: the build recipe comes from oxcaml/opam-repository.")
                 
  [125]
