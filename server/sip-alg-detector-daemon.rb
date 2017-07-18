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
require "gserver"
require "base64"
require "rubygems"
require "daemons"


module SipAlgDetectorServer
	
	
	def log_time
		Time.now.ctime
	end
	
	
	def log_ruri(request_first_line)
		request_first_line.gsub(/ SIP\/2\.0/,"").gsub(/[\r\n]*/,"")
	end
	
	module ListenerCommon
		
		
		def close_connection(io)
			io.close
			Thread.exit
		end
		
		
		def process_request(io)
			
			begin
				
				if io.class == TCPSocket
				
					sender_ip = io.peeraddr[3]
					sender_port = io.peeraddr[1]
					# DOC: 'readline("\r\n")' doesn't drop "\r\n" from the readed data.
					request_first_line = io.readline("\r\n")
					request_headers = io.readline("\r\n\r\n")
					content_length = request_headers[/Content-Length:\s*(\d+)/i, 1].to_i
					request_body = io.read(content_length)
					
					if request_first_line =~ /^INVITE sip:sip-alg-detector-daemon@/
						puts "#{log_time} TCP DEBUG: '#{log_ruri(request_first_line)}' from #{sender_ip}:#{sender_port}"
						generate_responses(request_first_line, request_headers, request_body, io, sender_ip, sender_port)
					else
						puts "#{log_time} TCP DEBUG: Invalid Request-URI: '#{log_ruri(request_first_line)}' from #{sender_ip}:#{sender_port}"
						generate_error_response(request_first_line, request_headers, io, sender_ip, sender_port)
						close_connection(io)
					end
					
				elsif io.class == UDPSocket
					
					request, sender_addr = io.recvfrom(1024)
					sender_ip = sender_addr[3]
					sender_port = sender_addr[1]
					request_first_line = request[/(.*\r\n)/, 1]
					request_headers = request[/\r\n((.|\r\n)*\r\n\r\n)/, 1]
					request_body = request[/\r\n\r\n((.|\r\n)*\r\n)/, 1]
					
					if request_first_line =~ /^INVITE sip:sip-alg-detector-daemon@/
						puts "#{log_time} UDP DEBUG: '#{log_ruri(request_first_line)}' from #{sender_ip}:#{sender_port}"
						generate_responses(request_first_line, request_headers, request_body, io, sender_ip, sender_port)
					else
						puts "#{log_time} UDP DEBUG: Invalid Request-URI: '#{log_ruri(request_first_line)}'"
						generate_error_response(request_first_line, request_headers, io, sender_ip, sender_port)
					end
					
				end
					
			rescue EOFError
				close_connection(io) if io.class == TCPSocket
					
			end  # begin
		
		end  # process_request
		
		
		def generate_responses(request_first_line, request_headers, request_body, io, sender_ip, sender_port)
		
			# Generate a 180 reply containing the mirrored request first line and headers.
			
			response_first_line = "SIP/2.0 180 Body contains mirrored request first line and headers\r\n"
			
			response_body = Base64.encode64(request_first_line + request_headers)
			
			response_headers = request_headers.clone
			response_headers = "Server: SipAlgDetectorDaemon\r\n" + response_headers
			response_headers.gsub!(/;rport($|[^=])/i, ";received=#{sender_ip};rport=#{sender_port}\\1")
			response_headers.gsub!(/(^To:[^\r]*)/i,"\\1;tag=#{to_tag=rand(999999)}")
			response_headers.gsub!(/^Content-Type:.*\r\n/i,"Content-Type: text/plain\r\n")
			response_headers.gsub!(/^Content-Length:.*\r\n/i,"Content-Length: #{response_body.size}\r\n")
			
			response = response_first_line + response_headers + response_body
			if io.class == TCPSocket
				io.print response
			elsif io.class == UDPSocket
				io.send(response, 0, sender_ip, sender_port)
			end
			
			# Generate a 500 reply containing the mirrored request body.
			
			response_first_line = "SIP/2.0 500 Body contains mirrored request body\r\n"
			
			response_body = Base64.encode64(request_body)
			
			response_headers = request_headers.clone
			response_headers = "Server: SipAlgDetectorDaemon\r\n" + response_headers
			response_headers.gsub!(/;rport($|[^=])/i, ";received=#{sender_ip};rport=#{sender_port}\\1")
			response_headers.gsub!(/(^To:[^\r]*)/i,"\\1;tag=#{to_tag}")
			response_headers.gsub!(/^Content-Type:.*\r\n/i,"Content-Type: text/plain\r\n")
			response_headers.gsub!(/^Content-Length:.*\r\n/i,"Content-Length: #{response_body.size}\r\n")
			
			response = response_first_line + response_headers + response_body
			
			if io.class == TCPSocket
				io.print response
			elsif io.class == UDPSocket
				io.send(response, 0, sender_ip, sender_port)
			end
			
		end
		
		
		def generate_error_response(request_first_line, request_headers, io, sender_ip, sender_port)
		
			# Generate a 403 error response
			
			# IF an ACK ignore it.
			return false if request_first_line =~ /^ACK /
			
			response_first_line = "SIP/2.0 403 You seem a real phone, get out\r\n"
			
			response_headers = request_headers.clone
			response_headers = "Server: SipAlgDetectorDaemon\r\n" + response_headers
			response_headers.gsub!(/;rport($|[^=])/i, ";received=#{sender_ip};rport=#{sender_port}\\1")
			response_headers.gsub!(/(^To:[^\r]*)/i,"\\1;tag=#{to_tag=rand(999999)}")
			response_headers.gsub!(/^Content-Type:.*\r\n/i,"")
			response_headers.gsub!(/^Content-Length:.*\r\n/i,"")
			
			response = response_first_line + response_headers
			if io.class == TCPSocket
				io.print response
			elsif io.class == UDPSocket
				io.send(response, 0, sender_ip, sender_port)
			end
			
		end
		
		
	end
	
	
	class TcpListener < GServer
		
		include ListenerCommon
		
		def initialize(*args)
			super(*args)  # args = server_port, server_host, max_connections, stdlog, audit, debug
		end
		
		# A fork for each incoming TCP connection. "io" is a TCPSocket.
		def serve(io)
			loop do
				process_request(io)
			end
		end
		
	end  # class TcpListener
	
	
	class UdpListener
		
		include ListenerCommon
		
		attr_reader :thread
		
		def initialize(port, address)
			@io = UDPSocket.open
			@io.bind(address, port)
			@thread = nil
		end
		
		def start
			@thread = Thread.new {
				loop do
					process_request(@io)
				end
			}
		end
		
	end
	
	
end  # module SipAlgDetectorDaemon



include SipAlgDetectorServer
include Daemonize

args = ARGV.join(" ")
server_ip = args[/-i ([^\s]*)/,1] || "0.0.0.0"
server_port = args[/-p ([^\s]*)/,1] || 5060

puts "#{log_time} INFO: Starting SIP ALG Detector daemon..."
puts "#{log_time} INFO: Use '-i IP' to set the listening IP"
puts "#{log_time} INFO: Use '-p PORT' to set the listening port"
puts "#{log_time} INFO: Bind address: #{server_ip}:#{server_port}"

daemonize

begin
	
	# Run the TCP server.
	tcp_server = TcpListener.new(server_port, server_ip)
	tcp_server.start
	puts "#{log_time} INFO: TCP Listener started"

	# Run the UDP server.
	udp_server = UdpListener.new(server_port, server_ip)
	udp_server.start
	puts "#{log_time} INFO: UDP Listener started"

	tcp_server.join
	udp_server.thread.join
	
rescue
	$stderr.print "\nERROR: Couldn't start the daemon: \n#{$!}\n"
	exit 1
end
