# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../../app'
require 'yaml'

# Drift guard: public/openapi.yaml is read by humans and agents, not
# generated from routes/*.rb, so nothing stops it from silently describing
# a path this app no longer serves (or never did) - which is exactly how
# TAIR10, `{id, backend}`, and `feature_status` booleans went stale (see
# docs/review-2026-09-23's API-46). This test does not check that request/
# response *shapes* match the implementation - only that every path the
# spec documents, for every HTTP method it documents there, is a route
# ChipAtlasApp actually has registered. That is cheap, deterministic, and
# catches the most common drift: a route renamed or removed without the
# spec being updated to match.
class OpenapiTest < Minitest::Test
  OPENAPI_PATH = File.join(__dir__, '..', '..', 'public', 'openapi.yaml')
  SPEC = YAML.safe_load(File.read(OPENAPI_PATH))
  HTTP_METHODS = %w[get post put patch delete].freeze

  def test_every_documented_path_and_method_is_a_real_route
    routes_by_verb = ChipAtlasApp.routes.transform_values { |tuples| tuples.map { |tuple| tuple[0].to_s } }

    SPEC.fetch('paths').each do |openapi_path, path_item|
      # Sinatra/Mustermann names path parameters `:id`; OpenAPI names them
      # `{id}` - translate before comparing.
      sinatra_path = openapi_path.gsub(/\{(\w+)\}/, ':\1')

      path_item.each_key do |verb|
        next unless HTTP_METHODS.include?(verb)

        patterns = routes_by_verb[verb.upcase] || []
        assert_includes patterns, sinatra_path,
                         "public/openapi.yaml documents #{verb.upcase} #{openapi_path}, " \
                         "but ChipAtlasApp has no matching route (looked for #{sinatra_path.inspect} " \
                         "among #{patterns.inspect})"
      end
    end
  end
end
