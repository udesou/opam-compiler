open Opam_compiler

let recipe ~variants ~commit ~dune =
  Printf.sprintf
    {|opam-version: "2.0"
depends: [ "ocaml-variants" {= "%s" & post} "oxcaml" {post} ]
build: [
  ["sh" "-exc" "make"]
  ["sh" "./write-config.sh" name "-v" "commit:string" "%s"]
]
url { src: "https://example.com/oxcaml.tar.gz" }
extra-source "init-compiler.tar.gz" { src: "https://github.com/ocaml/ocaml/archive/5.4.0.tar.gz" }
extra-source "init-dune.tbz" { src: "https://github.com/ocaml/dune/releases/download/%s/dune-%s.tbz" }
extra-source "init-menhir.tar.gz" { src: "https://gitlab.inria.fr/fpottier/menhir/-/archive/20231231/archive.tar.gz" }
|}
    variants commit dune dune

let dev_opam ~dune =
  Printf.sprintf
    {|opam-version: "2.0"
depends: [
  "ocaml" {>= "5.4.0~~" & < "5.5.0~~"}
  "dune" {>= "%s"}
  "menhir" {= "20231231"}
  "merlin"
]
|}
    dune

let recipes =
  [
    ("5.2.0minus40", recipe ~variants:"5.2.0+ox" ~commit:"C52" ~dune:"3.20.2");
    ("5.4.0-ox1", recipe ~variants:"5.4.0+ox" ~commit:"C1" ~dune:"3.20.2");
    ("5.4.0-ox7", recipe ~variants:"5.4.0+ox" ~commit:"C7" ~dune:"3.23.1");
  ]

let source = { Branch.user = "oxcaml"; repo = "oxcaml"; branch = "main" }

let client ?(version = "5.4.0+ox\n") ?(dev = Some (dev_opam ~dune:"3.23.0"))
    ~distances () =
  let resolve_ref = function
    | { Branch.repo = "opam-repository"; branch = "main"; _ } -> Ok "REPOSHA"
    | { Branch.repo = "oxcaml"; branch = "main"; _ } -> Ok "SRCSHA"
    | _ -> Error `Unknown
  in
  let distance ~user:_ ~repo:_ ~base ~head:_ =
    match List.assoc_opt base distances with
    | Some (ahead_by, behind_by) -> Ok { Github_client.ahead_by; behind_by }
    | None -> Error `Unknown
  in
  let list_dir _ _ =
    Ok ("README.md" :: List.map (fun (v, _) -> "oxcaml-compiler." ^ v) recipes)
  in
  let get_file (b : Branch.t) path =
    match (b.branch, path) with
    | "SRCSHA", "VERSION" -> Ok version
    | "SRCSHA", "oxcaml-dev.opam" -> Option.to_result ~none:`Unknown dev
    | "REPOSHA", path -> (
        match String.split_on_char '/' path with
        | [ "packages"; "oxcaml-compiler"; entry; "opam" ] ->
            let prefix = String.length "oxcaml-compiler." in
            let v = String.sub entry prefix (String.length entry - prefix) in
            Option.to_result ~none:`Unknown (List.assoc_opt v recipes)
        | _ -> Error `Unknown)
    | _ -> Error `Unknown
  in
  {
    Helpers.github_client_fail_all with
    resolve_ref;
    distance;
    list_dir;
    get_file;
  }

let chosen = Alcotest.(result string (testable Rresult.R.pp_msg ( = )))

let plan_tests =
  let test name ?version ?dev ~distances expected =
    ( name,
      `Quick,
      fun () ->
        let got =
          Oxcaml.plan (client ?version ?dev ~distances ()) source
          |> Result.map Oxcaml.package_version
        in
        Alcotest.check chosen __LOC__ expected got )
  in
  [
    test "picks the nearest recipe"
      ~distances:[ ("C1", (100, 0)); ("C7", (5, 0)) ]
      (Ok "oxcaml-compiler.5.4.0-ox7");
    test "a diverged release can be the nearest"
      ~dev:(Some (dev_opam ~dune:"3.13.0"))
      ~distances:[ ("C1", (10, 2)); ("C7", (20, 0)) ]
      (Ok "oxcaml-compiler.5.4.0-ox1");
    test "skips a nearer recipe that cannot build the source"
      ~distances:[ ("C1", (10, 2)); ("C7", (20, 0)) ]
      (Ok "oxcaml-compiler.5.4.0-ox7");
    test "falls back to the newest when distances are unknown" ~distances:[]
      (Ok "oxcaml-compiler.5.4.0-ox7");
    test "only recipes installing the source's VERSION" ~version:"5.2.0+ox"
      ~dev:None
      ~distances:[ ("C1", (0, 0)) ]
      (Ok "oxcaml-compiler.5.2.0minus40");
    test "no recipe installs the source's VERSION" ~version:"5.6.0+ox"
      ~distances:[]
      (Error
         (`Msg
            "No oxcaml-compiler recipe in oxcaml/opam-repository@REPOSHA \
             installs 5.6.0+ox (the VERSION of oxcaml/oxcaml:main)"));
    test "build tools the recipe does not bootstrap"
      ~dev:(Some (dev_opam ~dune:"3.24.0"))
      ~distances:[ ("C7", (0, 0)) ]
      (Error
         (`Msg
            "No oxcaml-compiler recipe can build oxcaml/oxcaml:main: the \
             nearest, oxcaml-compiler.5.4.0-ox7, bootstraps dune 3.23.1 (needs \
             >= 3.24.0). A newer recipe is needed in oxcaml/opam-repository."));
    test "no oxcaml-dev.opam skips the tool check" ~dev:None
      ~distances:[ ("C7", (0, 0)) ]
      (Ok "oxcaml-compiler.5.4.0-ox7");
  ]

let pinned_tests =
  [
    ( "pinned recipe",
      `Quick,
      fun () ->
        let plan =
          Oxcaml.plan (client ~distances:[ ("C7", (0, 0)) ] ()) source
          |> Rresult.R.failwith_error_msg
        in
        let opam =
          OpamFile.OPAM.read_from_string
            (Oxcaml.pinned_opam plan
               ~url:"git+https://github.com/oxcaml/oxcaml#main")
        in
        let check what = Alcotest.(check string) what in
        check "name" "oxcaml-compiler"
          (OpamPackage.Name.to_string (OpamFile.OPAM.name opam));
        check "version" "5.4.0-ox7"
          (OpamPackage.Version.to_string (OpamFile.OPAM.version opam));
        check "url" "git+https://github.com/oxcaml/oxcaml#main"
          (OpamFile.OPAM.url opam |> Option.get |> OpamFile.URL.url
         |> OpamUrl.to_string);
        let stamped =
          List.exists
            (fun (args, _) -> List.mem (OpamTypes.CString "SRCSHA", None) args)
            (OpamFile.OPAM.build opam)
        in
        Alcotest.(check bool) "commit stamp" true stamped;
        check "repository"
          "oxcaml-REPOSHA=git+https://github.com/oxcaml/opam-repository.git#REPOSHA"
          (let name, url = Oxcaml.repository plan in
           name ^ "=" ^ url) );
  ]

let tests = [ ("Oxcaml plan", plan_tests); ("Oxcaml pinned", pinned_tests) ]
