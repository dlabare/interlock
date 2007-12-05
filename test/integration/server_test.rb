
require "#{File.dirname(__FILE__)}/../test_helper"
require 'open-uri'
require 'cgi'
require 'fileutils'

# Start the server

class ServerTest < Test::Unit::TestCase

  PORT = 43041
  URL = "http://localhost:#{PORT}/"
  LOG = "#{RAILS_ROOT}/log/development.log"     

  Dir.chdir RAILS_ROOT do
    COVERAGE = "coverage"    
    RCOV = "#{COVERAGE}/cache-#{PORT}" # The port number must appear in `ps awx`
    FileUtils.rm_rf(COVERAGE) if File.exist? COVERAGE
    Dir.mkdir COVERAGE
  end
  
  ### Tests
  
  def test_render
    assert_match(/Welcome/, browse)
    assert_match(/Artichoke/, browse("items"))
  end
  
  def test_caching
    browse("items")
    assert_match(/running the controller block/, log)
    assert_match(/all:untagged. is rendering/, log)
    truncate
    browse("items")
    assert_no_match(/running the controller block/, log)
    assert_match(/all:untagged. is rendering/, log)
    assert_match(/Fragment read/, log)
  end
  
  def test_broad_invalidation
    browse("items")
    assert_match(/running the controller block/, log)
    assert_match(/all:untagged. is rendering/, log)
    
    truncate
    assert_equal "true", remote_eval("Item.find(:first).save!")
    assert_match(/invalidated by rule Item \-\> .all/, log)
    browse("items")
    assert_match(/running the controller block/, log)
    assert_match(/all:untagged. is rendering/, log)      
  end

  def test_narrow_invalidation
    browse("items/show/1")
    assert_match(/running the controller block/, log)
    assert_match(/show.1.untagged. is rendering/, log)
    
    truncate
    assert_equal "true", remote_eval("Item.find(2).save!")
    assert_no_match(/show.1.untagged. invalidated/, log)
    browse("items/show/1")
    assert_no_match(/running the controller block/, log)
    assert_match(/show.1.untagged. is rendering/, log)
    
    truncate
    assert_equal "true", remote_eval("Item.find(1).save!")
    assert_match(/show.1.untagged. invalidated/, log)
    browse("items/show/1")
    assert_match(/running the controller block/, log)
    assert_match(/show.1.untagged. is rendering/, log)
  end

  
  def test_caching_with_tag
    sleep(3)
    assert_no_match(/Artichoke/, browse("items/recent?seconds=3"))
    assert_match(/recent.all.3. is running the controller block/, log)

    truncate
    assert_no_match(/Artichoke/, browse("items/recent?seconds=2"))
    assert_match(/recent.all.2. is running the controller block/, log)
    assert_no_match(/recent.all.3. is running the controller block/, log)
    
    truncate
    assert_no_match(/Artichoke/, browse("items/recent?seconds=3"))
    assert_no_match(/recent.all.3. is running the controller block/, log)
    
    truncate
    remote_eval("Item.find(1).save!")
    assert_match(/Artichoke/, browse("items/recent?seconds=3"))
    assert_match(/recent.all.3. is running the controller block/, log)
  end  
  
  
  ### Support methods
  
  def truncate
    system("> #{LOG}")
  end
  
  def log
    File.open(LOG, 'r') do |f|
      f.read
    end
  end
  
  def browse(url = "")
    begin
      open(URL + url).read
    rescue OpenURI::HTTPError => e
      raise "#{e.to_s}: #{URL + url}"
    end
  end
  
  def remote_eval(string) 
    # Server doesn't run in our process, so invalidations here don't affect it    
    browse("eval?string=#{CGI.escape(string)}")
  end

  def setup
    @pid = Process.fork do
       Dir.chdir RAILS_ROOT do
         if $rcov
           exec("rcov --aggregate #{RCOV} --exclude config\/.*,app\/.*,boot\/.*,script\/server --include-file vendor\/plugins\/interlock\/lib\/.*\.rb script/server -- -p #{PORT} &> #{LOG}")
         else
           exec("script/server -p #{PORT} &> #{LOG}")
         end
       end
     end
     sleep(0.2) while log !~ /available at 0.0.0.0.#{PORT}/
     truncate
  end
  
  def teardown
    # Process.kill(9, @pid) doesn't work because Mongrel has double-forked itself away    
    while (pids = `ps awx | grep #{PORT} | grep -v grep | awk '{print $1}'`.split("\n")).any?
      pids.each {|pid| system("kill #{pid}")}
      sleep(0.2)
    end
    # print "K"
    @pid = nil
  end  
  
end