require File.dirname(__FILE__) + "/app"
use Rack::RewindableInput::Middleware
run PeakJohn
