# Run with `brew ruby packaging/verify_homebrew.rb FORMULA SOURCE NEW_WORK_DIRECTORY`.
# Exercise the actual formula with an isolated prefix; do not register a keg or modify the installed tap.
require "formula"
require "formula_assertions"

raise "Expected FORMULA SOURCE NEW_WORK_DIRECTORY" unless ARGV.length == 3

formula_path = Pathname(ARGV.fetch(0)).realpath
source = Pathname(ARGV.fetch(1)).realpath
work = Pathname(ARGV.fetch(2)).expand_path
raise "The work directory already exists" if work.exist?

work.mkpath
install_prefix = work/"install"
formula = Formulary.from_contents("ilibrary", formula_path, formula_path.read)
formula.define_singleton_method(:prefix) { |*_args| install_prefix }
formula.define_singleton_method(:logs) { work/"logs" }
formula.buildpath = source
formula.extend(Homebrew::Assertions)
Dir.chdir(source) { formula.install }
formula.test
puts "PASS: Homebrew formula source build, isolated installation, and formula tests"
