(** OxCaml has no compiler opam file in its source tree, so a switch borrows a
    build recipe ([oxcaml-compiler.<release>]) from oxcaml/opam-repository. *)

val package : string

type plan

val plan : Github_client.t -> Branch.t -> (plan, [> Rresult.R.msg ]) result
(** Picks the recipe for [source] from the current main of
    oxcaml/opam-repository: among the recipes installing the source's [VERSION],
    the one whose release commit is nearest in history. Fails early when the
    source's [oxcaml-dev.opam] needs build tools the recipe does not bootstrap.
*)

val package_version : plan -> string
val repository : plan -> string * string
val description : plan -> string

val pinned_opam : plan -> url:string -> string
(** The recipe, fetching [url] and recording the source commit it builds. *)
