#!/usr/bin/env ruby

#     Copyright (C) 2009  Iñaki Baz Castillo <ibc@aliax.net>
# 
#     This program is free software; you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation; either version 2 of the License, or
#     (at your option) any later version.
# 
#     This program is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
# 
#     You should have received a copy of the GNU General Public License
#     along with this program; if not, write to the Free Software
#     Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


require "socket"
require "timeout"
require "base64"
LIB_DIR = File.expand_path(File.dirname(__FILE__)) + '/lib'  # Absolute path.
require "#{LIB_DIR}/diff"
begin
	require "readline"
	has_readline = true
rescue LoadError
	puts "WARING: 'ruby-readline' is required for interactive mode => dissabling it"
	has_readline = false
	sleep 1
end


module SipAlgDetectorClient
	
	
	class Utils
		
		def self.random_string(length=6, chars="abcdefghjkmnpqrstuvwxyz0123456789")
			string = ''
			length.downto(1) { |i| string << chars[rand(chars.length - 1)] }
			string
		end
		
		def self.generate_tag()
			random_string(8)
		end
		
		def self.generate_branch()
			'z9hG4bK' + random_string(8)
		end
		
		def self.generate_callid()
			random_string(10)
		end
		
		def self.generate_cseq()
			rand(999)
		end
		
	end  # class Utils
	
	
	class InvalidServer < StandardError ; end
	
	
	class Request
		
		TIMEOUT = 5
		
		
		def initialize(options = {})
			
			@server_ip = options[:server_ip]
			@server_port = options[:server_port]
			@transport = options[:transport]
			@local_ip = options[:local_ip] || get_local_ip()
			@local_port = options[:local_port]
			@request = get_request()
			
		end
		
		
		def get_local_ip
		
			orig, Socket.do_not_reverse_lookup = Socket.do_not_reverse_lookup, true
			UDPSocket.open do |s|
				begin
					s.connect @server_ip, @server_port
				rescue SocketError
					log_error "Couldn't get the server address (#{@server_ip}): #{$!}"
					exit 1
				rescue
					log_error "Couldn't get local IP: #{$!}"
					exit 1
				end
				s.addr.last
			end
			
		end
		private :get_local_ip
		
		
		def connect
		
			puts "\nDEBUG: Connecting to the server (#{@transport.upcase}:#{@server_ip}:#{@server_port}) ..."
			begin
				case @transport
				when "udp"
					@io = UDPSocket.new
					Timeout::timeout(TIMEOUT) {
						@io.bind(@local_ip, @local_port)
						@io.connect(@server_ip, @server_port)
					}
				when "tcp"
					Timeout::timeout(TIMEOUT) {
						@io = TCPSocket.new(@server_ip, @server_port, @local_ip)
					}
				end
			rescue Timeout::Error
				log_error "Timeout when connecting the server via #{@transport.upcase}: #{$!}"
				return false
			rescue
				log_error "Couldn't create the #{@transport.upcase} socket: #{$!}"
				return false
			end
			
		end  # def connect
		private :connect
		
		
		def send
			
			if ! connect
				return false
			end
			
			puts "\nDEBUG: Sending the SIP request to the server ..."
			puts "\nDEBUG: Sent from #{@io.addr[3]}:#{@io.addr[1]} to #{@io.peeraddr[3]}:#{@io.peeraddr[1]}:"
			puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
			puts "#{@request}"
			puts "----------------------------------------------------------"
			begin
				Timeout::timeout(TIMEOUT) {
					@io.send(@request,0)
				}
			rescue Timeout::Error
				log_error "Timeout sending the request via #{@transport.upcase}: #{$!}"
				return false
			rescue
				log_error "Couldn't send the request via #{@transport.upcase}: #{$!}"
				return false
			end
			
		end  # def send
		
		
	end  # class Request
	
	
	class InviteRequest < Request
		
		attr_reader :request, :mirror_request
		
		
		def get_request
			
			body = <<-END_BODY
				v=#{Utils.random_string(1, "0123456789")}
				o=#{Utils.random_string(8)} #{Utils.random_string(8, "0123456789")} #{Utils.random_string(7, "0123456789")} IN IP4 #{@local_ip}
				s=-
				c=IN IP4 #{@local_ip}
				t=0 0
				m=audio #{Utils.random_string(4, "123456789")} RTP/AVP 8 0 3 101
				a=rtpmap:8 PCMA/8000
				a=rtpmap:0 PCMU/8000
				a=rtpmap:3 GSM/8000
				a=rtpmap:101 telephone-event/8000
				a=fmtp:101 0-15
				a=ptime:20
			END_BODY
			body.gsub!(/^[\s\t]*/,"")
			body.gsub!(/\n/,"\r\n")
			
			headers = <<-END_HEADERS
				INVITE sip:sip-alg-detector-daemon@#{@server_ip}:#{@server_port} SIP/2.0
				Via: SIP/2.0/#{@transport.upcase} #{@local_ip}:#{@local_port};rport;branch=#{Utils.generate_branch}
				Max-Forwards: 5
				To: <sip:sip-alg-detector-daemon@#{@server_ip}:#{@server_port}>
				From: "SIP ALG Detector" <sip:sip-alg-detector@killing-alg-routers.war>;tag=#{Utils.generate_tag}
				Call-ID: #{Utils.generate_callid}@#{@local_ip}
				CSeq: #{Utils.generate_cseq} INVITE
				Contact: <sip:0123@#{@local_ip}:#{@local_port};transport=#{@transport}>
				Allow: INVITE
				Content-Type: application/sdp
				Content-Length: #{body.length}
			END_HEADERS
			headers.gsub!(/^[\s\t]*/,"")
			headers.gsub!(/\n/,"\r\n")
			
			return headers + "\r\n" + body
			
		end
		private :get_request
		
		
		def receive
			
			puts "\nDEBUG: Waiting for the responses from the server ..."
			begin
				Timeout::timeout(TIMEOUT) {
					
					# 100: Request first line and headers
					response_first_line = @io.readline("\r\n")
					response_headers = @io.readline("\r\n\r\n")
					# Check if the response comes from a sip-alg-detector-daemon.
					if ! response_headers[/Server: SipAlgDetectorDaemon/i]
						raise InvalidServer
					end
					content_length = response_headers[/Content-Length:\s*(\d+)/i, 1].to_i
					response_body = @io.read(content_length)
					@mirror_request_first_line_and_headers = Base64.decode64(response_body)
					puts "\nDEBUG: 1/2 responses received"
						
					# 500: Request body
					response_first_line = @io.readline("\r\n")
					response_headers = @io.readline("\r\n\r\n")
					content_length = response_headers[/Content-Length:\s*(\d+)/i, 1].to_i
					response_body = @io.read(content_length)
					@mirror_request_body = Base64.decode64(response_body)
					puts "\nDEBUG: 2/2 responses received"
					
					@mirror_request = @mirror_request_first_line_and_headers + @mirror_request_body
				}
			rescue Timeout::Error
				log_error "Timeout receiving the responses via #{@transport.upcase}: #{$!}"
				return false
			rescue InvalidServer
				log_error "The server is not a SIP-ALG-Detector daemon"
				return false
			rescue
				log_error "Couldn't receive the responses via #{@transport.upcase}: #{$!}"
				return false
			end
			
			puts "\nDEBUG: Mirrored request sent in the response from the server:"
			puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
			puts "#{@mirror_request}"
			puts "----------------------------------------------------------"
			
			return true
			
		end  # def receive
		
		
	end  # class InviteRequest
	
	
	def self.compare_request_and_mirror(request, mirror_request)
		
		# Some stuff to make Diff working.
		request = request.split("\r\n")
		0.upto(request.size-1) {|i| request[i] += "\n"}
		mirror_request = mirror_request.split("\r\n")
		0.upto(mirror_request.size-1) {|i| mirror_request[i] += "\n"}
		
		diff = Diff.new(request, mirror_request)
		diff.to_diff
		if diff.diff_out != ""
			puts "\nINFO: There are differences between sent request and received mirrored request:"
			puts "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
			print diff.diff_out
			puts "----------------------------------------------------------"
			return true
		else
			puts "\nINFO: No differences between sent request and received mirrored request"
			return false
		end
	
	end  # compare_request_and_mirror
	
	
end  # module SipAlgDetectorClient


def show_help
	puts <<-END_HELP

Usage mode:    ruby sip-alg-detector.rb [OPTIONS]

  OPTIONS:
    -n               :    Non interactive mode (don't ask for parameters during
                          script execution). Required for other parameters to be
                          used.
    -t (tcp|udp|all) :    Tests to perform (TCP, UDP or both). Default "all".
    -si IP           :    IP of the server where 'sip-alg-detecter-daemon.rb'
                          runs. Default "none" (REQUIRED).
    -sp PORT         :    Port of the server when the daemon runs. Default "5060".
    -lp PORT         :    Local port from which UDP request will be sent. Default
                          "5060".

  Script return code: XY
    X    :    UDP ALG test result
    Y    :    TCP ALG test result

    Values of X/Y:
      1    :    ALG test result => FALSE
      2    :    ALG test result => TRUE
      3    :    ALG test dissabled
      4    :    ALG test failed

    In case of error ("couldn't get local ip/port") the script returns other
    codes (as 1).

  Homepage:
    http://dev.sipdoc.net/wiki/sip-stuff/SIP-ALG-Detector

END_HELP
end


def suggest_help
	puts "\nGet help by running:    ruby sip-alg-detector.rb -h\n"
end


def log_error(text)
	$stderr.print "\nERROR: #{text}\n"
end



### Run the script.

include SipAlgDetectorClient

# Asking for help?
if (ARGV[0] == "-h" || ARGV[0] == "--help")
	show_help
	exit
end

args = ARGV.join(" ")

( interactive = args[/-n/] ? false : true ) if has_readline
if ! interactive
	test = args[/-t ([^\s]*)/,1] || "all"
	server_ip = args[/-si ([^\s]*)/,1] || nil
	server_port = args[/-sp ([^\s]*)/,1] || 5060
	server_port = server_port.to_i
	local_port = args[/-lp ([^\s]*)/,1] || 5060
	local_port = local_port.to_i
end

# Interactive mode.
if interactive
	test_udp = ( Readline.readline("Perform the SIP UDP ALG test? [Y/n]: ") =~ /^(Y|y|)$/ ) ? true : false
	test_tcp = ( Readline.readline("Perform the SIP TCP ALG test? [Y/n]: ") =~ /^(Y|y|)$/ ) ? true : false
	puts "Server where SIP-ALG-Detector daemon is running:"
	server_ip = ( ( reply = Readline.readline("- IP: ") ) =~ /[^\s\t]+.*$/ ) ? reply.strip : nil
	server_port = ( ( reply = Readline.readline("- Port [5060]: ") ) =~ /[^\s\t]+.*$/ ) ? reply.strip : 5060
	local_port = ( ( reply = Readline.readline("Local port [5060]: ") ) =~ /[^\s\t]+.*$/ ) ? reply.strip : 5060
	sleep 0.2
# Non-interactive mode.
else
	test_udp = ( test == "udp" || test == "all" ) ? true : false
	test_tcp = ( test == "tcp" || test == "all" ) ? true : false
end

# Check parameters.
if ( ! test_udp && ! test_tcp )
	log_error "Invalid test selected"
	suggest_help
	exit 1
end
if server_ip !~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/ && server_ip !~ /[a-zA-Z0-9\.-_]+/
	log_error "Invalid server IP: <#{server_ip}>"
	suggest_help
	exit 1
end
if server_port.to_s !~ /^\d{1,6}$/
	log_error "Invalid server port: <#{server_port}>"
	suggest_help
	exit 1
end	
if local_port.to_s !~ /^\d{1,6}$/
	log_error "Invalid local port: <#{local_port}>"
	suggest_help
	exit 1
end	

# Show settings.
puts "\n\nSettings:"
puts "- Test UDP: #{test_udp}"
puts "- Test TCP: #{test_tcp}"
puts "- Server IP: #{server_ip}"
puts "- Server port: #{server_port}"
puts "- Local port: #{local_port}"

test_udp_result = nil
test_tcp_result = nil

# UDP test.
if test_udp

	Readline.readline("\n\nPress any key to start the SIP UDP ALG test...") if interactive
	puts "\nINFO: Starting the SIP UDP ALG test..."
	udp_invite = InviteRequest.new({:server_ip => server_ip, :server_port => server_port, :local_port => local_port, :transport => "udp"})
	udp_status = udp_invite.send && udp_invite.receive
	if ! udp_status
		log_error "Couldn't perform the SIP UDP test"
		test_udp_result = 4
	else
		udp_alg_test = SipAlgDetectorClient.compare_request_and_mirror(udp_invite.request, udp_invite.mirror_request)
		if udp_alg_test
			puts "\n__________________________________________________________________"
			puts "INFO: SIP UDP ALG test result: TRUE"
			puts "INFO: It seems that your router is performing ALG for SIP UDP"
			puts "__________________________________________________________________"
			test_udp_result = 2
		else
			puts "\n__________________________________________________________________"
			puts "INFO: SIP UDP ALG test result: FALSE"
			puts "INFO: It seems that your router is not performing ALG for SIP UDP"
			puts "__________________________________________________________________"
			test_udp_result = 1
		end
	end

else
	test_udp_result = 3
end

# TCP test.
if test_tcp

	Readline.readline("\n\nPress any key to start the SIP TCP ALG test...") if interactive
	puts "\nINFO: Starting the SIP TCP ALG test..."
	tcp_invite = InviteRequest.new({:server_ip => server_ip, :server_port => server_port, :local_port => local_port, :transport => "tcp"})
	tcp_status = tcp_invite.send && tcp_invite.receive
	if ! tcp_status
		log_error "Couldn't perform the SIP TCP test"
		test_tcp_result = 4
	else
		tcp_alg_test = SipAlgDetectorClient.compare_request_and_mirror(tcp_invite.request, tcp_invite.mirror_request)
		if tcp_alg_test
			puts "\n__________________________________________________________________"
			puts "INFO: SIP TCP ALG test result: TRUE"
			puts "INFO: It seems that your router is performing ALG for SIP TCP"
			puts "__________________________________________________________________"
			test_tcp_result = 2
		else
			puts "\n__________________________________________________________________"
			puts "INFO: SIP TCP ALG test result: FALSE"
			puts "INFO: It seems that your router is not performing ALG for SIP TCP"
			puts "__________________________________________________________________"
			test_tcp_result = 1
		end
	end
else
	test_tcp_result = 3
end

result_codes = { 1 => "FALSE", 2 => "TRUE", 3 => "test dissabled", 4 => "test failed" }

puts "\n\n"
puts "##################################################################"
puts "#     Test Results:"
puts "##    - SIP UDP ALG: #{result_codes.fetch(test_udp_result)}"
puts "###   - SIP TCP ALG: #{result_codes.fetch(test_tcp_result)}"
puts "##################################################################"

return_code = ( test_udp_result * 10 ) + test_tcp_result
puts "\n\nReturn code: #{return_code}"

Readline.readline("\n\nTest ended, press any key to exit...") if interactive

exit return_code
