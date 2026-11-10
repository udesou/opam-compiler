open Opam_compiler

let github_client_fail_all =
  {
    Github_client.pr_info = (fun _ -> assert false);
    resolve_ref = (fun _ -> assert false);
    get_file = (fun _ _ -> assert false);
  }
