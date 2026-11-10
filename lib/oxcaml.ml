open! Import

type t = {
  source : Branch.t;
  commit : string;
  version : string;
  ocaml_version : string;
  dev : OpamFile.OPAM.t;
}

let short sha = if String.length sha > 12 then String.sub sha 0 12 else sha

let ocaml_version_re =
  Re.(
    compile
      (seq
         [
           bos; group (seq [ rep1 digit; rep1 (seq [ char '.'; rep1 digit ]) ]);
         ]))

let fetch client (source : Branch.t) =
  let open Let_syntax.Result in
  let fail fmt = Format.kasprintf (fun m -> Error (`Msg m)) fmt in
  let name = Printf.sprintf "%s/%s:%s" source.user source.repo source.branch in
  let* commit =
    match Github_client.resolve_ref client source with
    | Ok commit -> Ok commit
    | Error `Unknown -> fail "Cannot resolve %s" name
  in
  let at = { source with branch = commit } in
  let* version =
    match Github_client.get_file client at "VERSION" with
    | Ok contents ->
        Ok (String.trim (List.hd (String.split_on_char '\n' contents)))
    | Error `Unknown -> fail "Cannot read the VERSION of %s" name
  in
  let* ocaml_version =
    match Re.exec_opt ocaml_version_re version with
    | Some g -> Ok (Re.Group.get g 1)
    | None -> fail "Cannot read the VERSION of %s: %S" name version
  in
  let* dev =
    match Github_client.get_file client at "oxcaml-dev.opam" with
    | Error `Unknown ->
        fail "%s has no oxcaml-dev.opam, which is needed to build it" name
    | Ok contents -> (
        match OpamFile.OPAM.read_from_string contents with
        | dev -> Ok dev
        | exception _ -> fail "Cannot parse the oxcaml-dev.opam of %s" name)
  in
  Ok { source; commit; version; ocaml_version; dev }

let url t = Branch.git_url { t.source with branch = t.commit }
let package t = "ocaml-variants." ^ t.version

let build_opam t =
  let tools = [ "ocaml"; "dune"; "menhir" ] in
  let keep_tools ((name, _) as atom) =
    if List.mem (OpamPackage.Name.to_string name) tools then
      OpamFormula.Atom atom
    else OpamFormula.Empty
  in
  (* Otherwise opam can pick ocaml-system or another ocaml-variants. *)
  let base_compiler =
    OpamFormula.Atom
      (OpamPackage.Name.of_string "ocaml-base-compiler", OpamFormula.Empty)
  in
  let depends =
    OpamFormula.ands
      [
        base_compiler; OpamFormula.map keep_tools (OpamFile.OPAM.depends t.dev);
      ]
  in
  OpamFile.OPAM.write_to_string (OpamFile.OPAM.with_depends depends t.dev)

let build_switch t =
  Switch_name.of_string_exn
    ("oxcaml-build-" ^ short (Digest.to_hex (Digest.string (build_opam t))))

let description t =
  Printf.sprintf "at %s, built in %s" (short t.commit)
    (Switch_name.to_string (build_switch t))

let compiler_opam t ~build_prefix ~configure_args =
  let configure =
    [
      "./configure";
      "--prefix=%{prefix}%";
      "--docdir=%{doc}%/ocaml";
      "--with-dune=" ^ Filename.concat build_prefix "bin/dune";
      "--disable-warn-error";
    ]
    @ configure_args
  in
  Printf.sprintf
    {|opam-version: "2.0"
name: "ocaml-variants"
version: %S
synopsis: "OxCaml"
maintainer: "opam-compiler"
depends: [
  "ocaml" {= %S & post}
  "base-unix" {post}
  "base-bigarray" {post}
  "base-threads" {post}
  "base-domains" {post}
  "base-nnp" {post}
  "base-effects" {post}
  "conf-autoconf" {build}
]
conflict-class: "ocaml-core-compiler"
flags: compiler
build-env: [PATH += %S]
build: [
  ["autoconf"]
  [%s]
  [make "-j%%{jobs}%%"]
]
install: [make "install"]
url { src: %S }
|}
    t.version t.ocaml_version
    (Filename.concat build_prefix "bin")
    (String.concat " " (List.map (Printf.sprintf "%S") configure))
    (url t)
