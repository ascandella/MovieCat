#!/usr/bin/env ruby

require 'rubygems'
require 'ruby-tmdb'
require 'sqlite3'
require 'yaml'
require 'date'
require 'fileutils'

require './lib/movie'
require './lib/categorizer'


# If set to false, limit to 1 (daemon mode)
MULTIPLE_MATCH_ASK = false


# really create sub-dirs in each type of action, false to disable
opts = {:create_dirs => true, :first_match => true}
mcat = Categorizer.new(File.join(File.dirname(__FILE__), 'config.yml'), opts)

mcat.scan_all()
