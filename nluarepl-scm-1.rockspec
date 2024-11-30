rockspec_format = '3.0'
package = "nluarepl"
version = "scm-1"
source = {
  url = "git+https://github.com/mfussenegger/nluarepl"
}
dependencies = {
  "nvim-dap",
}
test_dependencies = {
  "nlua"
}
build = {
  type = "builtin",
  copy_directories = {
  },
}
