open Opam_compiler

let github_client_fail_all =
  {
    Github_client.pr_info = (fun _ -> assert false);
    resolve_ref = (fun _ -> assert false);
    distance = (fun ~user:_ ~repo:_ ~base:_ ~head:_ -> assert false);
    list_dir = (fun _ _ -> assert false);
    get_file = (fun _ _ -> assert false);
  }
