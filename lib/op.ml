open! Import

let try_ r ~if_command_failed =
  match r with
  | Ok x -> Ok x
  | Error (`Command_failed _) as e ->
      let open Let_syntax.Result in
      let* () = if_command_failed () in
      e
  | Error _ as e -> e

let create_ocaml runner github_client source switch_name ~configure_command =
  let description = Source.switch_description source github_client in
  let open Let_syntax.Result in
  (let* () = Opam.create runner switch_name ~description in
   let* url = Source.switch_target source github_client in
   let* () =
     try_ (Opam.pin_add runner switch_name url ~configure_command)
       ~if_command_failed:(fun () -> Opam.remove_switch runner switch_name)
   in
   Opam.set_base runner switch_name)
  |> translate_error "Cannot create switch"

let write_opam_file switch_name contents =
  let open Let_syntax.Result in
  let name = Switch_name.to_string switch_name in
  let file =
    Fpath.(
      v (Filename.get_temp_dir_name ())
      / ("opam-compiler-" ^ name) / (name ^ ".opam"))
  in
  let* _ = Bos.OS.Dir.create (Fpath.parent file) in
  let+ () = Bos.OS.File.write file contents in
  file

(* Installing into an existing build switch is a no-op, or repairs it if an
   earlier install was interrupted. *)
let build_switch runner oxcaml =
  let open Let_syntax.Result in
  let name = Oxcaml.build_switch oxcaml in
  let* file = write_opam_file name (Oxcaml.build_opam oxcaml) in
  (let* exists = Opam.switch_exists runner name in
   let* () =
     if exists then Ok ()
     else
       Opam.create runner name ~no_switch:true
         ~description:"[opam-compiler] tools to build OxCaml"
   in
   let* () = Opam.install_deps runner name file in
   Opam.prefix runner name)
  |> translate_error "Cannot create the switch to build OxCaml"

let create_oxcaml runner github_client source switch_name ~configure_command =
  let open Let_syntax.Result in
  let* configure_args =
    match Option.map Bos.Cmd.to_list configure_command with
    | None -> Ok []
    | Some ("./configure" :: args) -> Ok args
    | Some _ ->
        Rresult.R.error_msg
          "For OxCaml sources, --configure-command must start with ./configure"
  in
  let* branch =
    Source.target_branch source github_client
    |> translate_error "Cannot resolve the source"
  in
  let* oxcaml = Oxcaml.fetch github_client branch in
  let* build_prefix = build_switch runner oxcaml in
  let* opam_file =
    write_opam_file switch_name
      (Oxcaml.compiler_opam oxcaml ~build_prefix ~configure_args)
  in
  let description =
    Source.switch_description source github_client
    ^ " " ^ Oxcaml.description oxcaml
  in
  (let* () = Opam.create runner switch_name ~description in
   let* () =
     try_
       (Opam.pin_add_opam_file runner switch_name (Oxcaml.url oxcaml)
          ~package:(Oxcaml.package oxcaml) ~opam_file)
       ~if_command_failed:(fun () -> Opam.remove_switch runner switch_name)
   in
   Opam.set_base runner switch_name)
  |> translate_error "Cannot create switch"

let create runner github_client source switch_name ~configure_command =
  let switch_name =
    match switch_name with
    | Some s -> s
    | None -> Source.global_switch_name source
  in
  if Source.is_oxcaml source then
    create_oxcaml runner github_client source switch_name ~configure_command
  else create_ocaml runner github_client source switch_name ~configure_command

type reinstall_mode = Quick | Full

let reinstall_packages_if_needed runner = function
  | Quick -> Ok ()
  | Full -> Opam.reinstall_packages runner

let reinstall runner mode ~configure_command =
  let open Let_syntax.Result in
  (let* () = Opam.reinstall_compiler runner ~configure_command in
   reinstall_packages_if_needed runner mode)
  |> translate_error "Could not reinstall"
