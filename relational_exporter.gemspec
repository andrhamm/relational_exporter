# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'relational_exporter/version'

Gem::Specification.new do |spec|
  spec.name          = 'relational_exporter'
  spec.version       = RelationalExporter::VERSION
  spec.authors       = ['Andrew Hammond']
  spec.email         = ['andrew@tremorlab.com']
  spec.description   = %q{Export relational databases as flat files}
  spec.summary       = %q{Export relational databases as flat files}
  spec.homepage      = 'http://github.com/andrhamm'
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_dependency 'hashie'
  spec.add_dependency 'activesupport'
  spec.add_dependency 'celluloid'

  spec.add_development_dependency 'bundler', '~> 1.3'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'byebug'
end
