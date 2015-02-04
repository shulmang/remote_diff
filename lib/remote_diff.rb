#!/usr/bin/env ruby

require "net/ssh"
require 'map'

DEFAULT_PATHS = %w(
  /bin
  /sbin
  /usr/bin
  /usr/sbin
  /usr/local/bin
  /usr/local/sbin
  /usr/local/mongo/bin
  /usr/local/apache2/bin
  /etc
)

class RemoteDiff
  attr_reader :host1_connect_string
  attr_reader :host2_connect_string
  attr_reader :host1_user
  attr_reader :host2_user
  attr_reader :host1_address
  attr_reader :host2_address
  attr_reader :host1_ssh
  attr_reader :host2_ssh
  attr_reader :paths
  attr_reader :host1_file_set
  attr_reader :host2_file_set
  attr_reader :deltas

  def initialize(host1_connect_string, host2_connect_string, paths=DEFAULT_PATHS)
    @host1_connect_string = host1_connect_string
    @host2_connect_string = host2_connect_string
    @host1_user = @host1_connect_string.split("@")[0]
    @host2_user = @host2_connect_string.split("@")[0]
    @host1_address = @host1_connect_string.split("@")[1]
    @host2_address = @host2_connect_string.split("@")[1]
    @host1_ssh = Net::SSH.start(@host1_address, @host1_user)
    @host2_ssh = Net::SSH.start(@host2_address, @host2_user)
    @paths = paths
    @paths = @paths.split(":") if @paths.is_a?(String)

    @deltas = Map.new(additions: [], ommisions: [], differences: [])
    build_file_sets
  end

  def get_path_contents(host_ssh, path)
    path_contents = host_ssh.exec! "ls -R #{path}"
    path_contents = path_contents.split("\n\n")
    return [] if path_contents.empty?
    to_return = path_contents.shift.split("\n").map{|sub_path| path + "/" + sub_path}
    path_contents.each do |sub_path_pair|
      unless sub_path_pair.empty?
        base_path, sub_paths = sub_path_pair.split(":\n")
        unless sub_paths.nil?
          sub_paths.split("\n").each do |sub_path|
            to_return.push(base_path + "/" + sub_path)
          end
        end
      end
    end
    to_return
  end

  def build_file_sets
    @host1_file_set = []
    @host2_file_set = []

    @paths.each do |path|
      @host1_file_set += get_path_contents(@host1_ssh, path)
      @host2_file_set += get_path_contents(@host2_ssh, path)
    end
  end

  def get_md5(host_ssh, file_path)
    host_ssh.exec! "md5sum #{file_path}"
  end

  def files_differ?(file_path)
    get_md5(@host1_ssh, file_path) != get_md5(@host2_ssh, file_path)
  end

  def do_comparison
    @deltas.additions = @host1_file_set - @host2_file_set
    @deltas.ommisions = @host2_file_set - @host1_file_set
    potential_changes = @host1_file_set & @host2_file_set
    potential_changes.each do |potential_change|
      @deltas.differences.push(potential_change) if files_differ?(potential_change)
    end
  end

  def comparison_report
    puts @deltas.to_yaml
  end
end

if __FILE__ == $0
  host1_connect_string = ARGV[0]
  host2_connect_string = ARGV[1]
  paths = ARGV[2] || DEFAULT_PATHS

  if host1_connect_string.include?("help")
    puts "Usage: remote_file_comparator.rb host1_connect_string host2_connect_string [/path/1:/path/n]"
    exit
  end

  rfc = RemoteDiff.new(host1_connect_string, host2_connect_string, paths)
  rfc.do_comparison
  puts rfc.comparison_report
end
