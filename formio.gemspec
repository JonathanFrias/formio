Gem::Specification.new do |s|
  s.name        = 'formio'
  s.version     = '0.0.4'
  s.date        = '2019-03-04'
  s.summary     = "A Ruby adapter for the form.io platform"
  s.description = "A Ruby adapter for the form.io platform"
  s.authors     = ["Jonathan Frias"]
  s.email       = 'jonathan@gofrias.com'
  s.files       = Dir["{lib}/**/*", "MIT-LICENSE", "README.md"]
  s.homepage    =
    'http://rubygems.org/gems/formio'
  s.license       = 'MIT'
  s.add_dependency("faraday")
  s.add_dependency("faraday-cookie_jar")
  s.add_dependency("faraday_curl")
  s.add_dependency("faraday-detailed_logger")
end
