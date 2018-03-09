#!/usr/bin/env ruby

# It is just a dummy file to make GitHub recognize the repo as Ruby-related

require 'bundler/setup'
require 'tty-markdown'

puts TTY::Markdown.parse(File.read('README.md'))