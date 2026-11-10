open! Import

val create :
  ?no_switch:bool ->
  Runner.t ->
  Switch_name.t ->
  description:string ->
  (unit, error) result

val pin_add :
  Runner.t ->
  Switch_name.t ->
  string ->
  configure_command:Bos.Cmd.t option ->
  (unit, error) result

val pin_add_opam_file :
  Runner.t ->
  Switch_name.t ->
  string ->
  package:string ->
  opam_file:Fpath.t ->
  (unit, error) result

val install_deps : Runner.t -> Switch_name.t -> Fpath.t -> (unit, error) result
val switch_exists : Runner.t -> Switch_name.t -> (bool, error) result
val prefix : Runner.t -> Switch_name.t -> (string, error) result
val set_base : Runner.t -> Switch_name.t -> (unit, error) result
val update : Runner.t -> Switch_name.t -> (unit, error) result

val reinstall_compiler :
  Runner.t -> configure_command:Bos.Cmd.t option -> (unit, error) result

val reinstall_packages : Runner.t -> (unit, error) result
val remove_switch : Runner.t -> Switch_name.t -> (unit, error) result
