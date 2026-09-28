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
   let editor = Option.map Opam.configure_editor configure_command in
   let* () =
     try_
       (Opam.pin_add runner switch_name url ~package:Opam.ocaml_variants ~editor)
       ~if_command_failed:(fun () -> Opam.remove_switch runner switch_name)
   in
   Opam.set_base runner switch_name ~package:Opam.ocaml_variants)
  |> translate_error "Cannot create switch"

(* The pinned recipe is handed to opam through its editor hook, so the edited
   definition is in place before the first build. *)
let recipe_file switch_name =
  let name = Switch_name.(to_string (escape_string (to_string switch_name))) in
  Fpath.(
    v (Filename.get_temp_dir_name ()) / ("opam-compiler-" ^ name ^ ".opam"))

let create_oxcaml runner github_client source switch_name ~configure_command =
  let open Let_syntax.Result in
  let* () =
    match configure_command with
    | None -> Ok ()
    | Some _ ->
        Rresult.R.error_msg
          "--configure-command and --with are not supported for OxCaml \
           sources: the build recipe comes from oxcaml/opam-repository."
  in
  let* branch =
    Source.target_branch source github_client
    |> translate_error "Cannot resolve the source"
  in
  let* plan = Oxcaml.plan github_client branch in
  let url = Branch.git_url branch in
  let file = recipe_file switch_name in
  let* () = Bos.OS.File.write file (Oxcaml.pinned_opam plan ~url) in
  let description =
    Source.switch_description source github_client
    ^ " " ^ Oxcaml.description plan
  in
  let repo_name, repo_url = Oxcaml.repository plan in
  (let* () =
     Opam.create runner switch_name ~description
       ~repositories:[ repo_name ^ "=" ^ repo_url; "default" ]
   in
   let editor = Some ("cp " ^ Filename.quote (Fpath.to_string file)) in
   let installed =
     let* () =
       Opam.pin_add runner switch_name url
         ~package:(Oxcaml.package_version plan)
         ~editor
     in
     Opam.set_base runner switch_name ~package:Oxcaml.package
   in
   match installed with
   | Ok () -> Ok ()
   | Error _ as e ->
       let* () = Opam.remove_switch runner switch_name in
       e)
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
