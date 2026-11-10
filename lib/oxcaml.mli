(** OxCaml has no compiler opam file in its source tree. It is built with the
    tools its [oxcaml-dev.opam] requires, installed in a switch of their own,
    and pinned as [ocaml-variants] in the target switch. *)

type t

val fetch : Github_client.t -> Branch.t -> (t, [> Rresult.R.msg ]) result
(** Reads [VERSION] and [oxcaml-dev.opam] at the commit the branch points to. *)

val url : t -> string
val package : t -> string
val description : t -> string

val build_switch : t -> Switch_name.t
(** Named after the tools it holds, so sources requiring the same tools share
    it. *)

val build_opam : t -> string
(** [oxcaml-dev.opam] restricted to the compiler, dune and menhir. *)

val compiler_opam :
  t -> build_prefix:string -> configure_args:string list -> string
