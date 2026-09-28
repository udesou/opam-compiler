open! Import

val ocaml_variants : string

val create :
  ?repositories:string list ->
  Runner.t ->
  Switch_name.t ->
  description:string ->
  (unit, error) result

val configure_editor : Bos.Cmd.t -> string
(** An [OPAMEDITOR] replacing ["./configure"] in the pinned opam file. *)

val pin_add :
  Runner.t ->
  Switch_name.t ->
  string ->
  package:string ->
  editor:string option ->
  (unit, error) result

val set_base :
  Runner.t -> Switch_name.t -> package:string -> (unit, error) result

val update : Runner.t -> Switch_name.t -> (unit, error) result

val reinstall_compiler :
  Runner.t -> configure_command:Bos.Cmd.t option -> (unit, error) result

val reinstall_packages : Runner.t -> (unit, error) result
val remove_switch : Runner.t -> Switch_name.t -> (unit, error) result
