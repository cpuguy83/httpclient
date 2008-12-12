require 'test/unit'
require 'httpclient'
require 'webrick'
require 'webrick/httpproxy.rb'
require 'logger'
require 'stringio'
require 'cgi'
require 'webrick/httputils'


class TestHTTPClient < Test::Unit::TestCase
  Port = 17171
  ProxyPort = 17172

  def setup
    @logger = Logger.new(STDERR)
    @logger.level = Logger::Severity::FATAL
    @proxyio = StringIO.new
    @proxylogger = Logger.new(@proxyio)
    @proxylogger.level = Logger::Severity::DEBUG
    @url = "http://localhost:#{Port}/"
    @proxyurl = "http://localhost:#{ProxyPort}/"
    @server = @proxyserver = @client = nil
    @server_thread = @proxyserver_thread = nil
    setup_server
    setup_client
  end

  def teardown
    teardown_client
    teardown_proxyserver if @proxyserver
    teardown_server
  end

  def test_initialize
    setup_proxyserver
    escape_noproxy do
      @proxyio.string = ""
      @client = HTTPClient.new(@proxyurl)
      assert_equal(URI.parse(@proxyurl), @client.proxy)
      assert_equal(200, @client.head(@url).status)
      assert(!@proxyio.string.empty?)
    end
  end

  def test_agent_name
    @client = HTTPClient.new(nil, "agent_name_foo")
    str = ""
    @client.debug_dev = str
    @client.get(@url)
    lines = str.split(/(?:\r?\n)+/)
    assert_equal("= Request", lines[0])
    assert_match(/^User-Agent: agent_name_foo/, lines[4])
  end

  def test_from
    @client = HTTPClient.new(nil, nil, "from_bar")
    str = ""
    @client.debug_dev = str
    @client.get(@url)
    lines = str.split(/(?:\r?\n)+/)
    assert_equal("= Request", lines[0])
    assert_match(/^From: from_bar/, lines[4])
  end

  def test_debug_dev
    str = ""
    @client.debug_dev = str
    assert_equal(str.object_id, @client.debug_dev.object_id)
    assert(str.empty?)
    @client.get(@url)
    assert(!str.empty?)
  end

  def test_debug_dev_stream
    str = ""
    @client.debug_dev = str
    conn = @client.get_async(@url)
    Thread.pass while !conn.finished?
    assert(!str.empty?)
  end

  def test_protocol_version_http09
    @client.protocol_version = 'HTTP/0.9'
    @client.debug_dev = str = ''
    @client.test_loopback_http_response << 'hello world'
    res = @client.get(@url + 'hello')
    lines = str.split(/(?:\r?\n)+/)
    assert_equal("= Request", lines[0])
    assert_equal("! CONNECTION ESTABLISHED", lines[2])
    assert_equal("GET /hello HTTP/0.9", lines[3])
    assert_equal("Connection: close", lines[5])
    assert_equal("= Response", lines[6])
    assert_match(/^hello world/, lines[7])
    assert_equal('0.9', res.version)
    assert_equal(nil, res.status)
    assert_equal(nil, res.reason)
  end

  def test_protocol_version_http10
    assert_equal(nil, @client.protocol_version)
    @client.protocol_version = 'HTTP/1.0'
    assert_equal('HTTP/1.0', @client.protocol_version)
    str = ""
    @client.debug_dev = str
    @client.get(@url + 'hello')
    lines = str.split(/(?:\r?\n)+/)
    assert_equal("= Request", lines[0])
    assert_equal("! CONNECTION ESTABLISHED", lines[2])
    assert_equal("GET /hello HTTP/1.0", lines[3])
    assert_equal("Connection: close", lines[5])
    assert_equal("= Response", lines[6])
  end

  def test_protocol_version_http11
    assert_equal(nil, @client.protocol_version)
    str = ""
    @client.debug_dev = str
    @client.get(@url)
    lines = str.split(/(?:\r?\n)+/)
    assert_equal("= Request", lines[0])
    assert_equal("! CONNECTION ESTABLISHED", lines[2])
    assert_equal("GET / HTTP/1.1", lines[3])
    assert_equal("Host: localhost:#{Port}", lines[6])
    @client.protocol_version = 'HTTP/1.1'
    assert_equal('HTTP/1.1', @client.protocol_version)
    str = ""
    @client.debug_dev = str
    @client.get(@url)
    lines = str.split(/(?:\r?\n)+/)
    assert_equal("= Request", lines[0])
    assert_equal("! CONNECTION ESTABLISHED", lines[2])
    assert_equal("GET / HTTP/1.1", lines[3])
    @client.protocol_version = 'HTTP/1.0'
    str = ""
    @client.debug_dev = str
    @client.get(@url)
    lines = str.split(/(?:\r?\n)+/)
    assert_equal("= Request", lines[0])
    assert_equal("! CONNECTION ESTABLISHED", lines[2])
    assert_equal("GET / HTTP/1.0", lines[3])
  end

  def test_proxy
    setup_proxyserver
    escape_noproxy do
      assert_raises(URI::InvalidURIError) do
       	@client.proxy = "http://"
      end
      assert_raises(ArgumentError) do
	@client.proxy = ""
      end
      @client.proxy = "http://admin:admin@foo:1234"
      assert_equal(URI.parse("http://admin:admin@foo:1234"), @client.proxy)
      uri = URI.parse("http://bar:2345")
      @client.proxy = uri
      assert_equal(uri, @client.proxy)
      #
      @proxyio.string = ""
      @client.proxy = nil
      assert_equal(200, @client.head(@url).status)
      assert(@proxyio.string.empty?)
      #
      @proxyio.string = ""
      @client.proxy = @proxyurl
      assert_equal(200, @client.head(@url).status)
      assert(!@proxyio.string.empty?)
    end
  end

  def test_noproxy_for_localhost
    @proxyio.string = ""
    @client.proxy = @proxyurl
    assert_equal(200, @client.head(@url).status)
    assert(@proxyio.string.empty?)
  end

  def test_no_proxy
    setup_proxyserver
    escape_noproxy do
      # proxy is not set.
      assert_equal(nil, @client.no_proxy)
      @client.no_proxy = 'localhost'
      assert_equal('localhost', @client.no_proxy)
      @proxyio.string = ""
      @client.proxy = nil
      assert_equal(200, @client.head(@url).status)
      assert(@proxyio.string.empty?)
      #
      @proxyio.string = ""
      @client.proxy = @proxyurl
      assert_equal(200, @client.head(@url).status)
      assert(@proxyio.string.empty?)
      #
      @client.no_proxy = 'foobar'
      @proxyio.string = ""
      @client.proxy = @proxyurl
      assert_equal(200, @client.head(@url).status)
      assert(!@proxyio.string.empty?)
      #
      @client.no_proxy = 'foobar,localhost:baz'
      @proxyio.string = ""
      @client.proxy = @proxyurl
      assert_equal(200, @client.head(@url).status)
      assert(@proxyio.string.empty?)
      #
      @client.no_proxy = 'foobar,localhost:443'
      @proxyio.string = ""
      @client.proxy = @proxyurl
      assert_equal(200, @client.head(@url).status)
      assert(!@proxyio.string.empty?)
      #
      @client.no_proxy = 'foobar,localhost:443:localhost:17171,baz'
      @proxyio.string = ""
      @client.proxy = @proxyurl
      assert_equal(200, @client.head(@url).status)
      assert(@proxyio.string.empty?)
    end
  end

  def test_loopback_response
    @client.test_loopback_response << 'message body 1'
    @client.test_loopback_response << 'message body 2'
    assert_equal('message body 1', @client.get_content('http://somewhere'))
    assert_equal('message body 2', @client.get_content('http://somewhere'))
    #
    @client.debug_dev = str = ''
    @client.test_loopback_response << 'message body 3'
    assert_equal('message body 3', @client.get_content('http://somewhere'))
    assert_match(/message body 3/, str)
  end

  def test_loopback_response_stream
    @client.test_loopback_response << 'message body 1'
    @client.test_loopback_response << 'message body 2'
    conn = @client.get_async('http://somewhere')
    Thread.pass while !conn.finished?
    assert_equal('message body 1', conn.pop.content.read)
    conn = @client.get_async('http://somewhere')
    Thread.pass while !conn.finished?
    assert_equal('message body 2', conn.pop.content.read)
  end

  def test_loopback_http_response
    @client.test_loopback_http_response << "HTTP/1.0 200 OK\ncontent-length: 100\n\nmessage body 1"
    @client.test_loopback_http_response << "HTTP/1.0 200 OK\ncontent-length: 100\n\nmessage body 2"
    assert_equal('message body 1', @client.get_content('http://somewhere'))
    assert_equal('message body 2', @client.get_content('http://somewhere'))
  end

  def test_broken_header
    @client.test_loopback_http_response << "HTTP/1.0 200 OK\nXXXXX\ncontent-length: 100\n\nmessage body 1"
    assert_equal('message body 1', @client.get_content('http://somewhere'))
  end

  def test_redirect_relative
    @client.test_loopback_http_response << "HTTP/1.0 302 OK\nLocation: hello\n\n"
    assert_equal('hello', @client.get_content(@url + 'redirect1'))
    #
    @client.reset_all
    @client.redirect_uri_callback = @client.method(:strict_redirect_uri_callback)
    assert_equal('hello', @client.get_content(@url + 'redirect1'))
    @client.reset_all
    @client.test_loopback_http_response << "HTTP/1.0 302 OK\nLocation: hello\n\n"
    begin
      @client.get_content(@url + 'redirect1')
      assert(false)
    rescue HTTPClient::BadResponse => e
      assert_equal(302, e.res.status)
    end
  end

  def test_get_content
    assert_equal('hello', @client.get_content(@url + 'hello'))
    assert_equal('hello', @client.get_content(@url + 'redirect1'))
    assert_equal('hello', @client.get_content(@url + 'redirect2'))
    url = @url.sub(/localhost/, '127.0.0.1')
    assert_equal('hello', @client.get_content(url + 'hello'))
    assert_equal('hello', @client.get_content(url + 'redirect1'))
    assert_equal('hello', @client.get_content(url + 'redirect2'))
    @client.reset(@url)
    @client.reset(url)
    @client.reset(@url)
    @client.reset(url)
    assert_raises(HTTPClient::BadResponse) do
      @client.get_content(@url + 'notfound')
    end
    assert_raises(HTTPClient::BadResponse) do
      @client.get_content(@url + 'redirect_self')
    end
    called = false
    @client.redirect_uri_callback = lambda { |uri, res|
      newuri = res.header['location'][0]
      called = true
      newuri
    }
    assert_equal('hello', @client.get_content(@url + 'relative_redirect'))
    assert(called)
  end

  def test_get_content_with_block
    @client.get_content(@url + 'hello') do |str|
      assert_equal('hello', str)
    end
    @client.get_content(@url + 'redirect1') do |str|
      assert_equal('hello', str)
    end
    @client.get_content(@url + 'redirect2') do |str|
      assert_equal('hello', str)
    end
  end

  def test_post_content
    assert_equal('hello', @client.post_content(@url + 'hello'))
    assert_equal('hello', @client.post_content(@url + 'redirect1'))
    assert_equal('hello', @client.post_content(@url + 'redirect2'))
    assert_raises(HTTPClient::BadResponse) do
      @client.post_content(@url + 'notfound')
    end
    assert_raises(HTTPClient::BadResponse) do
      @client.post_content(@url + 'redirect_self')
    end
    called = false
    @client.redirect_uri_callback = lambda { |uri, res|
      newuri = res.header['location'][0]
      called = true
      newuri
    }
    assert_equal('hello', @client.post_content(@url + 'relative_redirect'))
    assert(called)
  end

  def test_post_content_io
    post_body = StringIO.new("1234567890")
    assert_equal('post,1234567890', @client.post_content(@url + 'servlet', post_body))
    post_body = StringIO.new("1234567890")
    assert_equal('post,1234567890', @client.post_content(@url + 'servlet_redirect', post_body))
    #
    post_body = StringIO.new("1234567890")
    post_body.read(5)
    assert_equal('post,67890', @client.post_content(@url + 'servlet_redirect', post_body))
  end

  def test_head
    assert_equal("head", @client.head(@url + 'servlet').header["x-head"][0])
    res = @client.head(@url + 'servlet', {1=>2, 3=>4})
    assert_equal('1=2&3=4', res.header["x-query"][0])
  end

  def test_head_async
    conn = @client.head_async(@url + 'servlet', {1=>2, 3=>4})
    Thread.pass while !conn.finished?
    res = conn.pop
    assert_equal('1=2&3=4', res.header["x-query"][0])
  end

  def test_get
    assert_equal("get", @client.get(@url + 'servlet').content)
    res = @client.get(@url + 'servlet', {1=>2, 3=>4})
    assert_equal('1=2&3=4', res.header["x-query"][0])
  end

  def test_get_async
    conn = @client.get_async(@url + 'servlet', {1=>2, 3=>4})
    Thread.pass while !conn.finished?
    res = conn.pop
    assert_equal('1=2&3=4', res.header["x-query"][0])
  end

  def test_get_with_block
    called = false
    res = @client.get(@url + 'servlet') { |str|
      assert_equal('get', str)
      called = true
    }
    assert(called)
    # res does not have a content
    assert_nil(res.content)
  end

  def test_post
    assert_equal("post", @client.post(@url + 'servlet').content[0, 4])
    res = @client.post(@url + 'servlet', {1=>2, 3=>4})
    assert_equal('1=2&3=4', res.header["x-query"][0])
  end

  def test_post_async
    conn = @client.post_async(@url + 'servlet', {1=>2, 3=>4})
    Thread.pass while !conn.finished?
    res = conn.pop
    assert_equal('1=2&3=4', res.header["x-query"][0])
  end

  def test_post_with_block
    called = false
    res = @client.post(@url + 'servlet') { |str|
      assert_equal('post,', str)
      called = true
    }
    assert(called)
    assert_nil(res.content)
    #
    called = false
    res = @client.post(@url + 'servlet', {1=>2, 3=>4}) { |str|
      assert_equal('post,1=2&3=4', str)
      called = true
    }
    assert(called)
    assert_equal('1=2&3=4', res.header["x-query"][0])
    assert_nil(res.content)
  end

  def test_put
    assert_equal("put", @client.put(@url + 'servlet').content)
    res = @client.put(@url + 'servlet', {1=>2, 3=>4})
    assert_equal('1=2&3=4', res.header["x-query"][0])
  end

  def test_put_async
    conn = @client.put_async(@url + 'servlet', {1=>2, 3=>4})
    Thread.pass while !conn.finished?
    res = conn.pop
    assert_equal('1=2&3=4', res.header["x-query"][0])
  end

  def test_delete
    assert_equal("delete", @client.delete(@url + 'servlet').content)
  end

  def test_delete_async
    conn = @client.delete_async(@url + 'servlet')
    Thread.pass while !conn.finished?
    res = conn.pop
    assert_equal('delete', res.content.read)
  end

  def test_options
    assert_equal("options", @client.options(@url + 'servlet').content)
  end

  def test_options_async
    conn = @client.options_async(@url + 'servlet')
    Thread.pass while !conn.finished?
    res = conn.pop
    assert_equal('options', res.content.read)
  end

  def test_propfind
    assert_equal("propfind", @client.propfind(@url + 'servlet').content)
  end

  def test_propfind_async
    conn = @client.propfind_async(@url + 'servlet')
    Thread.pass while !conn.finished?
    res = conn.pop
    assert_equal('propfind', res.content.read)
  end

  def test_proppatch
    assert_equal("proppatch", @client.proppatch(@url + 'servlet').content)
    res = @client.proppatch(@url + 'servlet', {1=>2, 3=>4})
    assert_equal('proppatch', res.content)
    assert_equal('1=2&3=4', res.header["x-query"][0])
  end

  def test_proppatch_async
    conn = @client.proppatch_async(@url + 'servlet', {1=>2, 3=>4})
    Thread.pass while !conn.finished?
    res = conn.pop
    assert_equal('proppatch', res.content.read)
    assert_equal('1=2&3=4', res.header["x-query"][0])
  end

  def test_trace
    assert_equal("trace", @client.trace(@url + 'servlet').content)
    res = @client.trace(@url + 'servlet', {1=>2, 3=>4})
    assert_equal('1=2&3=4', res.header["x-query"][0])
  end

  def test_trace_async
    conn = @client.trace_async(@url + 'servlet', {1=>2, 3=>4})
    Thread.pass while !conn.finished?
    res = conn.pop
    assert_equal('1=2&3=4', res.header["x-query"][0])
  end

  def test_chunked
    assert_equal('chunked', @client.get_content(@url + 'chunked', { 'msg' => 'chunked' }))
  end

  def test_chunked_empty
    assert_equal('', @client.get_content(@url + 'chunked', { 'msg' => '' }))
  end

  def test_get_query
    assert_equal({'1'=>'2'}, check_query_get({1=>2}))
    assert_equal({'a'=>'A', 'B'=>'b'}, check_query_get({"a"=>"A", "B"=>"b"}))
    assert_equal({'&'=>'&'}, check_query_get({"&"=>"&"}))
    assert_equal({'= '=>' =+'}, check_query_get({"= "=>" =+"}))
    assert_equal(
      ['=', '&'].sort,
      check_query_get([["=", "="], ["=", "&"]])['='].to_ary.sort
    )
    assert_equal({'123'=>'45'}, check_query_get('123=45'))
    assert_equal({'12 3'=>'45', ' '=>' '}, check_query_get('12+3=45&+=+'))
    assert_equal({}, check_query_get(''))
  end

  def test_post_body
    assert_equal({'1'=>'2'}, check_query_post({1=>2}))
    assert_equal({'a'=>'A', 'B'=>'b'}, check_query_post({"a"=>"A", "B"=>"b"}))
    assert_equal({'&'=>'&'}, check_query_post({"&"=>"&"}))
    assert_equal({'= '=>' =+'}, check_query_post({"= "=>" =+"}))
    assert_equal(
      ['=', '&'].sort,
      check_query_post([["=", "="], ["=", "&"]])['='].to_ary.sort
    )
    assert_equal({'123'=>'45'}, check_query_post('123=45'))
    assert_equal({'12 3'=>'45', ' '=>' '}, check_query_post('12+3=45&+=+'))
    assert_equal({}, check_query_post(''))
    #
    post_body = StringIO.new("foo=bar&foo=baz")
    assert_equal(
      ["bar", "baz"],
      check_query_post(post_body)["foo"].to_ary.sort
    )
  end

  def test_extra_headers
    str = ""
    @client.debug_dev = str
    @client.head(@url, nil, {"ABC" => "DEF"})
    lines = str.split(/(?:\r?\n)+/)
    assert_equal("= Request", lines[0])
    assert_match("ABC: DEF", lines[4])
    #
    str = ""
    @client.debug_dev = str
    @client.get(@url, nil, [["ABC", "DEF"], ["ABC", "DEF"]])
    lines = str.split(/(?:\r?\n)+/)
    assert_equal("= Request", lines[0])
    assert_match("ABC: DEF", lines[4])
    assert_match("ABC: DEF", lines[5])
  end

  def test_timeout
    assert_equal(60, @client.connect_timeout)
    assert_equal(120, @client.send_timeout)
    assert_equal(60, @client.receive_timeout)
    #
    @client.connect_timeout = 1
    @client.send_timeout = 2
    @client.receive_timeout = 3
    assert_equal(1, @client.connect_timeout)
    assert_equal(2, @client.send_timeout)
    assert_equal(3, @client.receive_timeout)
  end

  def test_connect_timeout
    # ToDo
  end

  def test_send_timeout
    # ToDo
  end

  def test_receive_timeout
    # this test takes 2 sec
    assert_equal('hello', @client.get_content(@url + 'sleep?sec=2'))
    @client.receive_timeout = 1
    assert_equal('hello', @client.get_content(@url + 'sleep?sec=0'))
    assert_raise(Timeout::Error) do
      @client.get_content(@url + 'sleep?sec=2')
    end
    @client.receive_timeout = 3
    assert_equal('hello', @client.get_content(@url + 'sleep?sec=2'))
  end

  def test_reset
    url = @url + 'servlet'
    assert_nothing_raised do
      5.times do
        @client.get(url)
        @client.reset(url)
      end
    end
  end

  def test_reset_all
    assert_nothing_raised do
      5.times do
        @client.get(@url + 'servlet')
        @client.reset_all
      end
    end
  end

  def test_cookies
    cookiefile = File.join(File.dirname(File.expand_path(__FILE__)), 'test_cookies_file')
    File.open(cookiefile, "wb") do |f|
      f << "http://rubyforge.org/account/login.php	session_ser	LjEwMy45Ni40Ni0q%2A-fa0537de8cc31	2000000000	.rubyforge.org	/	13\n"
    end
    @client.set_cookie_store(cookiefile)
    cookie = @client.cookie_manager.cookies.first
    url = cookie.url
    assert(cookie.domain_match(url.host, cookie.domain))
    #
    @client.reset_all
    @client.test_loopback_http_response << "HTTP/1.0 200 OK\nSet-Cookie: foo=bar; expires=#{Time.mktime(2030, 12, 31).httpdate}\n\nOK"
    @client.get_content('http://rubyforge.org/account/login.php')
    @client.save_cookie_store
    str = File.read(cookiefile)
    assert_match(%r(http://rubyforge.org/account/login.php	foo	bar	1924873200	rubyforge.org	/login.php	1), str)
  end

  def test_urify
    extend HTTPClient::Util
    assert_nil(urify(nil))
    uri = 'http://foo'
    assert_equal(URI.parse(uri), urify(uri))
    assert_equal(URI.parse(uri), urify(URI.parse(uri)))
  end

  def test_connection
    c = HTTPClient::Connection.new
    assert(c.finished?)
    assert_nil(c.join)
  end

  def test_site
    site = HTTPClient::Site.new
    assert_equal('tcp', site.scheme)
    assert_equal('0.0.0.0', site.host)
    assert_equal(0, site.port)
    assert_equal('tcp://0.0.0.0:0', site.addr)
    assert_equal('tcp://0.0.0.0:0', site.to_s)
    assert_nothing_raised do
      site.inspect
    end
    #
    site = HTTPClient::Site.new(URI.parse('http://localhost:12345/foo'))
    assert_equal('http', site.scheme)
    assert_equal('localhost', site.host)
    assert_equal(12345, site.port)
    assert_equal('http://localhost:12345', site.addr)
    assert_equal('http://localhost:12345', site.to_s)
    assert_nothing_raised do
      site.inspect
    end
    #
    site1 = HTTPClient::Site.new(URI.parse('http://localhost:12341/'))
    site2 = HTTPClient::Site.new(URI.parse('http://localhost:12342/'))
    site3 = HTTPClient::Site.new(URI.parse('http://localhost:12342/'))
    assert(!(site1 == site2))
    h = { site1 => 'site1', site2 => 'site2' }
    h[site3] = 'site3'
    assert_equal('site1', h[site1])
    assert_equal('site3', h[site2])
  end

private

  def check_query_get(query)
    WEBrick::HTTPUtils.parse_query(
      @client.get(@url + 'servlet', query).header["x-query"][0]
    )
  end

  def check_query_post(query)
    WEBrick::HTTPUtils.parse_query(
      @client.post(@url + 'servlet', query).header["x-query"][0]
    )
  end

  def setup_server
    @server = WEBrick::HTTPServer.new(
      :BindAddress => "localhost",
      :Logger => @logger,
      :Port => Port,
      :AccessLog => [],
      :DocumentRoot => File.dirname(File.expand_path(__FILE__))
    )
    [:hello, :sleep, :servlet_redirect, :redirect1, :redirect2, :redirect3, :redirect_self, :relative_redirect, :chunked].each do |sym|
      @server.mount(
	"/#{sym}",
	WEBrick::HTTPServlet::ProcHandler.new(method("do_#{sym}").to_proc)
      )
    end
    @server.mount('/servlet', TestServlet.new(@server))
    @server_thread = start_server_thread(@server)
  end

  def setup_proxyserver
    @proxyserver = WEBrick::HTTPProxyServer.new(
      :BindAddress => "localhost",
      :Logger => @proxylogger,
      :Port => ProxyPort,
      :AccessLog => []
    )
    @proxyserver_thread = start_server_thread(@proxyserver)
  end

  def setup_client
    @client = HTTPClient.new
    @client.debug_dev = STDOUT if $DEBUG
  end

  def teardown_server
    @server.shutdown
    @server_thread.kill
    @server_thread.join
  end

  def teardown_proxyserver
    @proxyserver.shutdown
    @proxyserver_thread.kill
    @proxyserver_thread.join
  end

  def teardown_client
    @client.reset_all
  end

  def start_server_thread(server)
    t = Thread.new {
      Thread.current.abort_on_exception = true
      server.start
    }
    while server.status != :Running
      sleep 0.1
      unless t.alive?
	t.join
	raise
      end
    end
    t
  end

  def escape_noproxy
    backup = HTTPClient::NO_PROXY_HOSTS.dup
    HTTPClient::NO_PROXY_HOSTS.clear
    yield
  ensure
    HTTPClient::NO_PROXY_HOSTS.replace(backup)
  end

  def do_hello(req, res)
    res['content-type'] = 'text/html'
    res.body = "hello"
  end

  def do_sleep(req, res)
    sec = req.query['sec'].to_i
    sleep sec
    res['content-type'] = 'text/html'
    res.body = "hello"
  end

  def do_servlet_redirect(req, res)
    res.set_redirect(WEBrick::HTTPStatus::Found, @url + "servlet") 
  end

  def do_redirect1(req, res)
    res.set_redirect(WEBrick::HTTPStatus::MovedPermanently, @url + "hello") 
  end

  def do_redirect2(req, res)
    res.set_redirect(WEBrick::HTTPStatus::TemporaryRedirect, @url + "redirect3")
  end

  def do_redirect3(req, res)
    res.set_redirect(WEBrick::HTTPStatus::Found, @url + "hello") 
  end

  def do_redirect_self(req, res)
    res.set_redirect(WEBrick::HTTPStatus::Found, @url + "redirect_self") 
  end

  def do_relative_redirect(req, res)
    res.set_redirect(WEBrick::HTTPStatus::Found, "hello") 
  end

  def do_chunked(req, res)
    res.chunked = true
    piper, pipew = IO.pipe
    res.body = piper
    pipew << req.query['msg']
    pipew.close
  end

  class TestServlet < WEBrick::HTTPServlet::AbstractServlet
    def get_instance(*arg)
      self
    end

    def do_HEAD(req, res)
      res["x-head"] = 'head'	# use this for test purpose only.
      res["x-query"] = query_response(req)
    end

    def do_GET(req, res)
      res.body = 'get'
      res["x-query"] = query_response(req)
    end

    def do_POST(req, res)
      res.body = 'post,' + req.body.to_s
      res["x-query"] = body_response(req)
    end

    def do_PUT(req, res)
      res.body = 'put'
      res["x-query"] = body_response(req)
    end

    def do_DELETE(req, res)
      res.body = 'delete'
    end

    def do_OPTIONS(req, res)
      # check RFC for legal response.
      res.body = 'options'
    end

    def do_PROPFIND(req, res)
      res.body = 'propfind'
    end

    def do_PROPPATCH(req, res)
      res.body = 'proppatch'
      res["x-query"] = body_response(req)
    end

    def do_TRACE(req, res)
      # client SHOULD reflect the message received back to the client as the
      # entity-body of a 200 (OK) response. [RFC2616]
      res.body = 'trace'
      res["x-query"] = query_response(req)
    end

  private

    def query_response(req)
      query_escape(WEBrick::HTTPUtils.parse_query(req.query_string))
    end

    def body_response(req)
      query_escape(WEBrick::HTTPUtils.parse_query(req.body))
    end

    def query_escape(query)
      escaped = []
      query.collect do |k, v|
	v.to_ary.each do |ve|
	  escaped << CGI.escape(k) + '=' + CGI.escape(ve)
	end
      end
      escaped.join('&')
    end
  end
end
