open! Import

type spec = A of string | L of spec list | Set_env of string * string

let add_env env kv = Some (kv :: Option.value env ~default:[])

let rec add_spec (cmd, env) = function
  | A s -> (Bos.Cmd.(cmd % s), env)
  | L l -> add_spec_list (cmd, env) l
  | Set_env (k, v) -> (cmd, add_env env (k, v))

and add_spec_list cmd l = List.fold_left add_spec cmd l

let opam_cmd l = add_spec_list (Bos.Cmd.v "opam", Some [ ("OPAMCLI", "2.0") ]) l

let run_opam runner args =
  let cmd, extra_env = opam_cmd args in
  Runner.run ?extra_env runner cmd

let run_out_opam runner args =
  let cmd, extra_env = opam_cmd args in
  Runner.run_out ?extra_env runner cmd

let ocaml_variants = "ocaml-variants"

let create ?(repositories = []) runner name ~description =
  let repositories =
    match repositories with
    | [] -> []
    | repos -> [ A ("--repositories=" ^ String.concat "," repos) ]
  in
  run_opam runner
    ([
       A "switch";
       A "create";
       A (Switch_name.to_string name);
       A "--empty";
       A "--description";
       A description;
     ]
    @ repositories)

let switch name = L [ A "--switch"; A (Switch_name.to_string name) ]

let configure_editor configure_command =
  let opam_quote s = Printf.sprintf {|"%s"|} s in
  let configure_in_opam_format =
    configure_command |> Bos.Cmd.to_list |> List.map opam_quote
    |> String.concat " "
  in
  Printf.sprintf {|sed -i -e 's#"./configure"#%s#g'|} configure_in_opam_format

let pin_add runner name url ~package ~editor =
  let cmd_base =
    [ A "pin"; A "add"; switch name; A "--yes"; A package; A url ]
  in
  let cmd_rest =
    match editor with
    | None -> []
    | Some editor -> [ A "--edit"; Set_env ("OPAMEDITOR", editor) ]
  in
  run_opam runner (cmd_base @ cmd_rest)

let set_base runner name ~package =
  run_opam runner [ A "switch"; A "set-base"; switch name; A package ]

let update runner name =
  run_opam runner [ A "update"; switch name; A ocaml_variants ]

let reinstall_configure runner ~configure_command =
  let open Let_syntax.Result in
  let* prefix = run_out_opam runner [ A "config"; A "var"; A "prefix" ] in
  let base_command =
    Option.value configure_command ~default:Bos.Cmd.(v "./configure")
  in
  let command = Bos.Cmd.(base_command % "--prefix" % prefix) in
  Runner.run runner command

let reinstall_compiler runner ~configure_command =
  let open Let_syntax.Result in
  let make = Bos.Cmd.(v "make") in
  let make_install = Bos.Cmd.(v "make" % "install") in
  let* () = reinstall_configure runner ~configure_command in
  let* () = Runner.run runner make in
  Runner.run runner make_install

let reinstall_packages runner =
  run_opam runner
    [ A "reinstall"; A "--assume-built"; A "--working-dir"; A ocaml_variants ]

let remove_switch runner name =
  run_opam runner
    [ A "switch"; A "remove"; A "--yes"; A (Switch_name.to_string name) ]
