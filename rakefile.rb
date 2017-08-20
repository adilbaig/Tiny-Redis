desc 'extract d code snippets'
task :extract_d do
  sh "rm -f snippet_*.d"
  content = File.read('index.html')
  r = Regexp.new("<code language=\"dlang\">(.*?)</code>", Regexp::MULTILINE)
  matches = content.scan(r)
  matches.each_with_index do |m, i|
    file_name = "snippet_#{i}.d"
    puts "-------------------- Working on #{file_name}"
    File.write(file_name, m[0])
    sh "dmd -I~/.dub/packages/tinyredis-2.1.1/tinyredis/source #{file_name} ~/.dub/packages/tinyredis-2.1.1/tinyredis/libtinyredis.a"
    sh "./#{file_name.gsub('.d', '')}"
  end
end

task :default => [:extract_d]
