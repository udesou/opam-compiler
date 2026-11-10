open! Import

type pr_info = { source_branch : Branch.t; title : string }

type t = {
  pr_info : Pull_request.t -> (pr_info, [ `Unknown ]) result;
  resolve_ref : Branch.t -> (string, [ `Unknown ]) result;
  get_file : Branch.t -> string -> (string, [ `Unknown ]) result;
}

let widen r = (r : (_, [ `Unknown ]) result :> (_, [> `Unknown ]) result)
let pr_info t pr = widen (t.pr_info pr)
let resolve_ref t branch = widen (t.resolve_ref branch)
let get_file t branch path = widen (t.get_file branch path)

module Curly = struct
  let pull_source_user branch =
    match branch.Github_t.branch_user with
    | Some user -> Ok user.user_login
    | None -> Error `Unknown

  let pull_source_repo branch =
    match branch.Github_t.branch_repo with
    | Some repo -> Ok repo.repository_name
    | None -> Error `Unknown

  let info_of_pull pull =
    let open Let_syntax.Result in
    let { Github_t.pull_head; pull_title = title; _ } = pull in
    let* user = pull_source_user pull_head in
    let+ repo = pull_source_repo pull_head in
    let branch = pull_head.branch_ref in
    let source_branch = { Branch.user; repo; branch } in
    { source_branch; title }

  let check_code code = if code = 200 then Ok () else Error `Unknown

  let parse_pull body =
    match Github_j.pull_of_string body with
    | pull -> Ok pull
    | exception Yojson.Json_error _ -> Error `Unknown

  let api_root = "https://api.github.com"

  let pull_url { Pull_request.user; repo; number } =
    Printf.sprintf "%s/repos/%s/%s/pulls/%d" api_root user repo number

  (* Unauthenticated API calls are limited to 60 per hour. *)
  let headers () =
    match Sys.getenv_opt "GITHUB_TOKEN" with
    | Some token when token <> "" -> [ ("Authorization", "Bearer " ^ token) ]
    | _ -> []

  let get url =
    Curly.get ~headers:(headers ()) url
    |> Rresult.R.reword_error (fun (_ : Curly.Error.t) -> `Unknown)

  let get_ok url =
    let open Let_syntax.Result in
    let* response = get url in
    let+ () = check_code response.code in
    response.body

  let resolve_ref { Branch.user; repo; branch } =
    let open Let_syntax.Result in
    let* body =
      get_ok
        (Printf.sprintf "%s/repos/%s/%s/commits/%s" api_root user repo branch)
    in
    match Yojson.Safe.(Util.member "sha" (from_string body)) with
    | `String sha -> Ok sha
    | _ | (exception Yojson.Json_error _) -> Error `Unknown

  let get_file { Branch.user; repo; branch } path =
    get_ok
      (Printf.sprintf "https://raw.githubusercontent.com/%s/%s/%s/%s" user repo
         branch path)

  let pr_info pr =
    let open Let_syntax.Result in
    let url = pull_url pr in
    let* response = get url in
    let* () = check_code response.code in
    let* pull = parse_pull response.body in
    info_of_pull pull
end

let curly =
  let open Curly in
  { pr_info; resolve_ref; get_file }

module Dry_run = struct
  let pr_info { Pull_request.user; repo; number } =
    let slug = Printf.sprintf "%s-%s-%d" user repo number in
    let source_branch =
      {
        Branch.user = Printf.sprintf "user-%s" slug;
        repo = Printf.sprintf "repo-%s" slug;
        branch = Printf.sprintf "branch-%s" slug;
      }
    in
    let title = Printf.sprintf "Title of %s" slug in
    Ok { source_branch; title }

  let resolve_ref { Branch.user; repo; branch } =
    let digest = Digest.(to_hex (string (user ^ "/" ^ repo ^ ":" ^ branch))) in
    Ok (digest ^ String.sub digest 0 8)

  let get_file _ path =
    match Filename.basename path with
    | "VERSION" -> Ok "5.4.0+ox\n"
    | "oxcaml-dev.opam" ->
        Ok
          {|opam-version: "2.0"
synopsis: "OxCaml Development Tools"
depends: [
  "ocaml" {>= "5.4.0~~" & < "5.5.0~~"}
  "dune" {>= "3.23.0"}
  "menhir" {= "20231231"}
  "ocamlformat" {= "0.29.0"}
]
|}
    | _ -> Error `Unknown
end

let dry_run =
  let open Dry_run in
  { pr_info; resolve_ref; get_file }

let cached c =
  let table = Hashtbl.create 0 in
  let pr_info pr =
    match Hashtbl.find_opt table pr with
    | Some hit -> Ok hit
    | None ->
        let result = c.pr_info pr in
        Result.iter (fun info -> Hashtbl.add table pr info) result;
        result
  in
  { c with pr_info }

let real = cached curly
