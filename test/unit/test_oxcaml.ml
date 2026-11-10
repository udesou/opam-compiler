open Opam_compiler

let msg = Alcotest.testable Rresult.R.pp_msg ( = )

let dev_opam =
  {|opam-version: "2.0"
synopsis: "OxCaml Development Tools"
depends: [
  "ocaml" {>= "5.4.0~~" & < "5.5.0~~"}
  "dune" {>= "3.23.0"}
  "menhir" {= "20231231"}
  "ocamlformat" {= "0.29.0"}
  "merlin"
]
conflicts: [ "ocaml-option-32bit" ]
|}

let source = { Branch.user = "oxcaml"; repo = "oxcaml"; branch = "main" }

let client ?(version = "5.4.0+ox\n") ?(dev = Some dev_opam) () =
  let resolve_ref = function
    | { Branch.branch = "main"; _ } -> Ok "SRCSHA"
    | _ -> Error `Unknown
  in
  let get_file (b : Branch.t) path =
    match (b.branch, path) with
    | "SRCSHA", "VERSION" -> Ok version
    | "SRCSHA", "oxcaml-dev.opam" -> Option.to_result ~none:`Unknown dev
    | _ -> Error `Unknown
  in
  { Helpers.github_client_fail_all with resolve_ref; get_file }

let fetch_exn ?version ?dev () =
  match Oxcaml.fetch (client ?version ?dev ()) source with
  | Ok t -> t
  | Error (`Msg m) -> Alcotest.fail m

let opam_of_string s = OpamFile.OPAM.read_from_string s

let depends_names opam =
  OpamFormula.fold_left
    (fun acc (name, _) -> OpamPackage.Name.to_string name :: acc)
    []
    (OpamFile.OPAM.depends opam)
  |> List.rev

let fetch_tests =
  [
    ( "reads the source at its commit",
      `Quick,
      fun () ->
        let t = fetch_exn () in
        Alcotest.(check string)
          __LOC__ "git+https://github.com/oxcaml/oxcaml#SRCSHA" (Oxcaml.url t);
        Alcotest.(check string)
          __LOC__ "ocaml-variants.5.4.0+ox" (Oxcaml.package t) );
    ( "needs oxcaml-dev.opam",
      `Quick,
      fun () ->
        let got = Oxcaml.fetch (client ~dev:None ()) source in
        Alcotest.(check (result reject msg))
          __LOC__
          (Error
             (`Msg
                "oxcaml/oxcaml:main has no oxcaml-dev.opam, which is needed to \
                 build it"))
          got );
    ( "needs a version number",
      `Quick,
      fun () ->
        let got = Oxcaml.fetch (client ~version:"trunk\n" ()) source in
        Alcotest.(check (result reject msg))
          __LOC__
          (Error
             (`Msg {|Cannot read the VERSION of oxcaml/oxcaml:main: "trunk"|}))
          got );
  ]

let build_tests =
  [
    ( "build switch gets the compiler, dune and menhir only",
      `Quick,
      fun () ->
        let opam = opam_of_string (Oxcaml.build_opam (fetch_exn ())) in
        Alcotest.(check (list string))
          __LOC__
          [ "ocaml-base-compiler"; "ocaml"; "dune"; "menhir" ]
          (depends_names opam);
        Alcotest.(check bool)
          __LOC__ true
          (OpamFile.OPAM.conflicts opam <> OpamFormula.Empty) );
    ( "build switch is shared when the tools are the same",
      `Quick,
      fun () ->
        let replace ~sub ~by s =
          Astring.String.cuts ~sep:sub s |> String.concat by
        in
        let dev =
          replace ~sub:{|"merlin"|} ~by:{|"merlin" "ocaml-lsp-server"|} dev_opam
        in
        let newer_dune = replace ~sub:"3.23.0" ~by:"3.24.0" dev_opam in
        let name ?dev () =
          Switch_name.to_string
            (Oxcaml.build_switch
               (fetch_exn ?dev:(Option.map Option.some dev) ()))
        in
        Alcotest.(check string) __LOC__ (name ()) (name ~dev ());
        Alcotest.(check bool) __LOC__ false (name () = name ~dev:newer_dune ())
    );
  ]

let compiler_tests =
  [
    ( "compiler is ocaml-variants built with the build switch",
      `Quick,
      fun () ->
        let opam =
          Oxcaml.compiler_opam (fetch_exn ()) ~build_prefix:"/b"
            ~configure_args:[ "--enable-multidomain" ]
          |> opam_of_string
        in
        Alcotest.(check string)
          __LOC__ "ocaml-variants"
          (OpamPackage.Name.to_string (OpamFile.OPAM.name opam));
        Alcotest.(check string)
          __LOC__ "5.4.0+ox"
          (OpamPackage.Version.to_string (OpamFile.OPAM.version opam));
        let configure =
          List.find_map
            (fun (args, _) ->
              match args with
              | (OpamTypes.CString "./configure", _) :: rest ->
                  Some
                    (List.map
                       (function OpamTypes.CString s, _ | CIdent s, _ -> s)
                       rest)
              | _ -> None)
            (OpamFile.OPAM.build opam)
        in
        Alcotest.(check (option (list string)))
          __LOC__
          (Some
             [
               "--prefix=%{prefix}%";
               "--docdir=%{doc}%/ocaml";
               "--with-dune=/b/bin/dune";
               "--disable-warn-error";
               "--enable-multidomain";
             ])
          configure );
  ]

let tests =
  [
    ("Oxcaml fetch", fetch_tests);
    ("Oxcaml build switch", build_tests);
    ("Oxcaml compiler", compiler_tests);
  ]
