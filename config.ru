require "bundler"
require "rack/protection"
Bundler.require

$stderr.print("Firing up with Bundler\n")

require File.dirname(__FILE__) + "/app"
run BHXIV
