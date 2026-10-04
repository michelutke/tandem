#!/usr/bin/env ruby
# frozen_string_literal: true

# ruby ui_tap_point.rb <label> < uiautomator-dump.xml
#
# Prints "<x> <y>", the centre of the first node whose `text` or `content-desc` equals <label>
# (case-insensitive), or exits 1 when there is none. Used by the E62-08 device scenarios to press the
# on-phone "Start mirroring" prompt and the system consent button the way a user would.
module UiTapPoint
  NODE = /<node\b[^>]*>/.freeze
  BOUNDS = /bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"/.freeze

  def self.find(xml, label)
    xml.scan(NODE).each do |node|
      next unless attribute(node, 'text').casecmp?(label) || attribute(node, 'content-desc').casecmp?(label)

      match = node.match(BOUNDS)
      next unless match

      left, top, right, bottom = match.captures.map(&:to_i)
      return [(left + right) / 2, (top + bottom) / 2]
    end
    nil
  end

  def self.attribute(node, name)
    node[/\s#{Regexp.escape(name)}="([^"]*)"/, 1].to_s
  end
end

if $PROGRAM_NAME == __FILE__
  point = UiTapPoint.find($stdin.read, ARGV.fetch(0))
  exit 1 unless point
  puts point.join(' ')
end
