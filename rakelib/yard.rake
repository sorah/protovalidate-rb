# frozen_string_literal: true

desc "Generate API documentation with YARD"
task :yard do
  sh "bundle exec yard doc"
end

namespace :yard do
  desc "Fail unless every public object is documented"
  task :check do
    stats = `bundle exec yard stats --list-undoc`
    puts stats
    abort "yard: undocumented objects found" unless stats.include?("100.00% documented")
  end
end
