let all_tests =
  Test_op.tests @ Test_source.tests @ Test_github_client.tests
  @ Test_oxcaml.tests

let () = Alcotest.run "opam-compiler" all_tests
