#!/usr/bin/env ruby
# frozen_string_literal: true

# E71-14 (AC-18, AC-02): network egress audit -- the apps talk only to each other. Turns a per-app
# capture or socket-table dump into a pass/fail report; exits non-zero on any flow to anything other
# than the paired peer on the Tandem port.
#
#   ruby tools/release-audit/egress-audit.rb flows --side mac|phone --peer ADDR --port N FILE...
#   ruby tools/release-audit/egress-audit.rb proc-net --uid UID --peer ADDR --port N FILE...
#
# `flows` reads `tshark -T fields -e ip.src -e ip.dst -e ipv6.src -e ipv6.dst -e tcp.srcport
# -e tcp.dstport -e udp.srcport -e udp.dstport` output (tab separated, one packet per line) of a
# per-app capture. `--side mac` is a Mac capture (peer = the phone address, Tandem port is the Mac's
# own); `--side phone` is a phone capture (peer = the Mac address, Tandem port is the peer's). UDP is never allowed (mDNS is done by mDNSResponder / system_server, not the app UID).
# `proc-net` reads `/proc/net/{tcp,tcp6,udp,udp6}` dumps: every socket owned by UID, listening
# sockets included, must have exactly PEER:PORT as its remote endpoint.

require 'optparse'
require 'ipaddr'

module EgressAudit
  Packet = Struct.new(:source, :source_port, :destination, :destination_port, :protocol)
  Socket = Struct.new(:uid, :remote_address, :remote_port)

  module_function

  def parse_flows(text)
    text.each_line.filter_map do |line|
      ip_src, ip_dst, ip6_src, ip6_dst, tcp_src, tcp_dst, udp_src, udp_dst = line.chomp.split("\t", -1)
      next if line.strip.empty?

      tcp = !tcp_src.to_s.empty?
      Packet.new(first_present(ip_src, ip6_src), Integer(first_present(tcp_src, udp_src)),
                 first_present(ip_dst, ip6_dst), Integer(first_present(tcp_dst, udp_dst)), tcp ? :tcp : :udp)
    end
  end

  def first_present(*values)
    values.find { |v| !v.to_s.empty? }
  end

  def check_flows(packets, side:, peer:, port:)
    packets.filter_map do |packet|
      next if packet.protocol == :tcp && allowed_packet?(packet, side, peer, port)

      "#{packet.protocol} #{packet.source}:#{packet.source_port} -> #{packet.destination}:#{packet.destination_port}"
    end.uniq
  end

  def allowed_packet?(packet, side, peer, port)
    if side == :mac
      (packet.source_port == port && packet.destination == peer) ||
        (packet.destination_port == port && packet.source == peer)
    else
      (packet.destination == peer && packet.destination_port == port) ||
        (packet.source == peer && packet.source_port == port)
    end
  end

  def parse_proc_net(text)
    text.each_line.filter_map do |line|
      columns = line.split
      next unless columns.size > 7 && columns[0].end_with?(':') && columns[0] != 'sl'

      address, port = columns[2].split(':')
      Socket.new(Integer(columns[7]), decode_address(address), port.to_i(16))
    end
  end

  def decode_address(hex)
    bytes = hex.scan(/.{8}/).flat_map { |word| word.scan(/../).reverse }.map { |b| b.to_i(16) }
    address = IPAddr.new_ntoh(bytes.pack('C*'))
    address.ipv4_mapped? ? address.native.to_s : address.to_s
  end

  def check_proc_net(sockets, uid:, peer:, port:)
    sockets.select { |s| s.uid == uid && !(s.remote_address == IPAddr.new(peer).to_s && s.remote_port == port) }
           .map { |s| "uid #{s.uid} socket remote #{s.remote_address}:#{s.remote_port}" }
           .uniq
  end

  def run(argv)
    mode = argv.shift
    options = {}
    OptionParser.new do |opts|
      opts.on('--side SIDE') { |v| options[:side] = v.to_sym }
      opts.on('--peer ADDR') { |v| options[:peer] = v }
      opts.on('--port N', Integer) { |v| options[:port] = v }
      opts.on('--uid UID', Integer) { |v| options[:uid] = v }
    end.parse!(argv)
    return usage if options[:peer].nil? || options[:port].nil? || argv.empty?

    text = argv.map { |file| File.read(file) }.join("\n")
    violations =
      case mode
      when 'flows'
        return usage unless %i[mac phone].include?(options[:side])

        check_flows(parse_flows(text), side: options[:side], peer: options[:peer], port: options[:port])
      when 'proc-net'
        return usage if options[:uid].nil?

        check_proc_net(parse_proc_net(text), uid: options[:uid], peer: options[:peer], port: options[:port])
      else
        return usage
      end
    report(violations)
  end

  def report(violations)
    if violations.empty?
      puts 'egress audit passed'
      return 0
    end
    warn "egress audit FAILED: #{violations.size} flow(s) outside peer:port"
    violations.each { |v| warn "  #{v}" }
    1
  end

  def usage
    warn 'usage: egress-audit.rb flows --side mac|phone --peer ADDR --port N FILE... | ' \
         'proc-net --uid UID --peer ADDR --port N FILE...'
    2
  end
end

exit EgressAudit.run(ARGV) if $PROGRAM_NAME == __FILE__
