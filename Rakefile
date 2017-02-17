require 'bundler'
Bundler.setup

gemspec_filename = 'dominosjp.gemspec'
gemspec = eval(File.read(gemspec_filename))
gem_filename = "#{gemspec.full_name}.gem"

system "rm -rf #{gem_filename} 2>/dev/null"
system "gem uninstall -ax #{gemspec.name}"

task default: gem_filename

file gem_filename => gemspec.files + [gemspec_filename] do
  system "gem build #{gemspec_filename}"
  system "gem install #{gemspec.full_name}.gem"
end
