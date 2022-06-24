require "bundler"
require "rack/protection"
Bundler.require

require File.dirname(__FILE__) + "/app"
run PeakJohn
