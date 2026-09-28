open! Import

let opam_repository =
  { Branch.user = "oxcaml"; repo = "opam-repository"; branch = "main" }

let package = "oxcaml-compiler"

type recipe = { version : string; opam : OpamFile.OPAM.t }
type plan = { repo_commit : string; recipe : recipe; source_commit : string }

let warn fmt = Format.eprintf ("opam-compiler: warning: " ^^ fmt ^^ "@.")
let short sha = if String.length sha > 12 then String.sub sha 0 12 else sha

let parse_opam contents =
  match OpamFile.OPAM.read_from_string contents with
  | opam -> Some opam
  | exception _ -> None

(* The recipe stamps the compiler it builds through
   ["sh" "./write-config.sh" ... "commit:string" "<sha>"]. *)
let rec stamped_commit_in_args = function
  | (OpamTypes.CString "commit:string", _) :: (OpamTypes.CString sha, _) :: _ ->
      Some sha
  | _ :: rest -> stamped_commit_in_args rest
  | [] -> None

let stamped_commit opam =
  List.find_map
    (fun (args, _) -> stamped_commit_in_args args)
    (OpamFile.OPAM.build opam)

let with_stamped_commit sha opam =
  let rec stamp = function
    | ((OpamTypes.CString "commit:string", _) as key)
      :: (OpamTypes.CString _, filter)
      :: rest ->
        key :: (OpamTypes.CString sha, filter) :: rest
    | arg :: rest -> arg :: stamp rest
    | [] -> []
  in
  let build = OpamFile.OPAM.build opam in
  OpamFile.OPAM.with_build
    (List.map (fun (args, f) -> (stamp args, f)) build)
    opam

let version_formulas name opam =
  let deps =
    OpamFilter.filter_deps ~build:true ~post:true (OpamFile.OPAM.depends opam)
  in
  let name = OpamPackage.Name.of_string name in
  OpamFormula.fold_left
    (fun acc (n, vf) ->
      if OpamPackage.Name.equal n name then vf :: acc else acc)
    [] deps

let satisfies version vfs =
  let v = OpamPackage.Version.of_string version in
  List.for_all (fun vf -> OpamFormula.check_version_formula vf v) vfs

let string_of_version_formulas vfs =
  let atom (relop, v) =
    OpamFormula.string_of_relop relop ^ " " ^ OpamPackage.Version.to_string v
  in
  String.concat " & " (List.map (OpamFormula.string_of_formula atom) vfs)

let version_chars = Re.rep1 (Re.alt [ Re.digit; Re.char '.' ])

(* The recipe does not declare the tools it bootstraps as dependencies; their
   versions are only visible in its extra-source URLs. *)
let bootstrap_tools opam =
  let find re url =
    Option.map (fun g -> Re.Group.get g 1) (Re.exec_opt (Re.compile re) url)
  in
  let tool_of_source (base, url) =
    let url = OpamUrl.to_string (OpamFile.URL.url url) in
    let tool name re = Option.map (fun v -> (name, v)) (find re url) in
    match OpamFilename.Base.to_string base with
    | "init-compiler.tar.gz" ->
        tool "ocaml"
          (Re.seq
             [ Re.char '/'; Re.group version_chars; Re.str ".tar.gz"; Re.eos ])
    | "init-dune.tbz" ->
        tool "dune"
          (Re.seq
             [ Re.str "dune-"; Re.group version_chars; Re.str ".tbz"; Re.eos ])
    | "init-menhir.tar.gz" ->
        tool "menhir"
          (Re.seq
             [ Re.str "/archive/"; Re.group (Re.rep1 Re.digit); Re.char '/' ])
    | _ -> None
  in
  List.filter_map tool_of_source (OpamFile.OPAM.extra_sources opam)

(* Tools the source's oxcaml-dev.opam requires that [recipe] does not
   bootstrap, and tools whose bootstrapped version cannot be read. *)
let tool_problems dev recipe =
  let provided = bootstrap_tools recipe.opam in
  List.fold_left
    (fun (problems, unknown) tool ->
      match version_formulas tool dev with
      | [] -> (problems, unknown)
      | vfs -> (
          match List.assoc_opt tool provided with
          | None -> (problems, tool :: unknown)
          | Some v when satisfies v vfs -> (problems, unknown)
          | Some v ->
              ( Printf.sprintf "%s %s (needs %s)" tool v
                  (string_of_version_formulas vfs)
                :: problems,
                unknown )))
    ([], [])
    [ "menhir"; "dune"; "ocaml" ]

(* Release commits are not always ancestors of main (a release branch can carry
   its own commits), so the nearest recipe is the one with the fewest commits
   between it and the source, counted both ways through their merge base. *)
let by_nearest client (source : Branch.t) ~source_commit candidates =
  let distance recipe =
    match stamped_commit recipe.opam with
    | None -> None
    | Some base -> (
        match
          Github_client.distance client ~user:source.user ~repo:source.repo
            ~base ~head:source_commit
        with
        | Ok { ahead_by; behind_by } -> Some (ahead_by + behind_by)
        | Error `Unknown -> None)
  in
  let newest_first a b =
    OpamPackage.Version.compare
      (OpamPackage.Version.of_string b.version)
      (OpamPackage.Version.of_string a.version)
  in
  let candidates = List.sort newest_first candidates in
  let measured =
    List.filter_map
      (fun r -> Option.map (fun d -> (d, r)) (distance r))
      candidates
  in
  if measured = [] then (
    warn "cannot compare %s with the recipes' commits; preferring the newest"
      (short source_commit);
    candidates)
  else
    let nearest =
      List.map snd
        (List.stable_sort (fun (a, _) (b, _) -> compare a b) measured)
    in
    nearest @ List.filter (fun r -> not (List.memq r nearest)) candidates

let plan client (source : Branch.t) =
  let open Let_syntax.Result in
  let fail fmt = Format.kasprintf (fun m -> Error (`Msg m)) fmt in
  let or_fail what = function
    | Ok x -> Ok x
    | Error `Unknown -> fail "%s" what
  in
  let* repo_commit =
    Github_client.resolve_ref client opam_repository
    |> or_fail "Cannot resolve the main branch of oxcaml/opam-repository"
  in
  let repo_at = { opam_repository with branch = repo_commit } in
  let dir = "packages/" ^ package in
  let* entries =
    Github_client.list_dir client repo_at dir
    |> or_fail ("Cannot list " ^ dir ^ " in oxcaml/opam-repository")
  in
  let recipe_of_entry entry =
    let prefix = package ^ "." in
    if not (Astring.String.is_prefix ~affix:prefix entry) then None
    else
      let version =
        Astring.String.with_range ~first:(String.length prefix) entry
      in
      match
        Github_client.get_file client repo_at (dir ^ "/" ^ entry ^ "/opam")
      with
      | Error `Unknown ->
          warn "cannot fetch the %s recipe; skipping it" entry;
          None
      | Ok contents -> (
          match parse_opam contents with
          | None ->
              warn "cannot parse the %s recipe; skipping it" entry;
              None
          | Some opam -> Some { version; opam })
  in
  let recipes = List.filter_map recipe_of_entry entries in
  let source_name =
    Printf.sprintf "%s/%s:%s" source.user source.repo source.branch
  in
  let* source_commit =
    Github_client.resolve_ref client source
    |> or_fail ("Cannot resolve " ^ source_name)
  in
  let source_at = { source with branch = source_commit } in
  let first_line s = String.trim (List.hd (String.split_on_char '\n' s)) in
  let* candidates =
    match Github_client.get_file client source_at "VERSION" with
    | Error `Unknown ->
        warn "%s has no readable VERSION; considering every recipe" source_name;
        Ok recipes
    | Ok contents -> (
        let version = first_line contents in
        let installs r =
          match version_formulas "ocaml-variants" r.opam with
          | [] -> false
          | vfs -> satisfies version vfs
        in
        match List.filter installs recipes with
        | [] ->
            fail
              "No %s recipe in oxcaml/opam-repository@%s installs %s (the \
               VERSION of %s)"
              package (short repo_commit) version source_name
        | candidates -> Ok candidates)
  in
  let* () =
    if candidates = [] then
      fail "No %s recipe found in oxcaml/opam-repository@%s" package
        (short repo_commit)
    else Ok ()
  in
  let ranked = by_nearest client source ~source_commit candidates in
  let dev_opam =
    Result.to_option (Github_client.get_file client source_at "oxcaml-dev.opam")
    |> Fun.flip Option.bind parse_opam
  in
  let* recipe =
    match dev_opam with
    | None ->
        warn "%s has no readable oxcaml-dev.opam; not checking build tools"
          source_name;
        Ok (List.hd ranked)
    | Some dev -> (
        match
          List.find_opt (fun r -> fst (tool_problems dev r) = []) ranked
        with
        | Some r ->
            List.iter
              (fun tool ->
                warn "cannot tell which %s %s.%s bootstraps; not checking it"
                  tool package r.version)
              (snd (tool_problems dev r));
            Ok r
        | None ->
            let nearest = List.hd ranked in
            fail
              "No %s recipe can build %s: the nearest, %s.%s, bootstraps %s. A \
               newer recipe is needed in oxcaml/opam-repository."
              package source_name package nearest.version
              (String.concat ", " (fst (tool_problems dev nearest))))
  in
  if stamped_commit recipe.opam = None then
    warn "%s.%s does not record a commit; the compiler will not report %s"
      package recipe.version (short source_commit);
  Ok { repo_commit; recipe; source_commit }

let package_version plan = package ^ "." ^ plan.recipe.version

(* Named after the commit so it never clashes with a differently configured
   repository of the same name in the opam root. *)
let repository plan =
  ( "oxcaml-" ^ short plan.repo_commit,
    Printf.sprintf "git+https://github.com/oxcaml/opam-repository.git#%s"
      plan.repo_commit )

let description plan =
  Printf.sprintf "at %s, built with %s from oxcaml/opam-repository@%s"
    (short plan.source_commit) (package_version plan) (short plan.repo_commit)

(* Repository recipes take their name and version from their directory; a
   pinned definition has to carry them. *)
let pinned_opam plan ~url =
  plan.recipe.opam
  |> OpamFile.OPAM.with_name (OpamPackage.Name.of_string package)
  |> OpamFile.OPAM.with_version
       (OpamPackage.Version.of_string plan.recipe.version)
  |> with_stamped_commit plan.source_commit
  |> OpamFile.OPAM.with_url (OpamFile.URL.create (OpamUrl.parse url))
  |> OpamFile.OPAM.write_to_string
