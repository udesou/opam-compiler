type pr_info = { source_branch : Branch.t; title : string }
type distance = { ahead_by : int; behind_by : int }

type t = {
  pr_info : Pull_request.t -> (pr_info, [ `Unknown ]) result;
  resolve_ref : Branch.t -> (string, [ `Unknown ]) result;
      (** Commit SHA that the [branch] field (any git ref) points to. *)
  distance :
    user:string ->
    repo:string ->
    base:string ->
    head:string ->
    (distance, [ `Unknown ]) result;
      (** Commits from the merge base of [base] and [head] to each of them. *)
  list_dir : Branch.t -> string -> (string list, [ `Unknown ]) result;
  get_file : Branch.t -> string -> (string, [ `Unknown ]) result;
}

val pr_info : t -> Pull_request.t -> (pr_info, [> `Unknown ]) result
val resolve_ref : t -> Branch.t -> (string, [> `Unknown ]) result

val distance :
  t ->
  user:string ->
  repo:string ->
  base:string ->
  head:string ->
  (distance, [> `Unknown ]) result

val list_dir : t -> Branch.t -> string -> (string list, [> `Unknown ]) result
val get_file : t -> Branch.t -> string -> (string, [> `Unknown ]) result
val real : t
val dry_run : t
val cached : t -> t
