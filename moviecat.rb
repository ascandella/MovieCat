#!/usr/bin/env ruby

require 'rubygems'
require 'ruby-tmdb'
require 'sqlite3'
require 'yaml'
require 'date'

config = File.open(File.join(File.dirname(__FILE__), 'config.yml')) { |yf| YAML::load(yf) }
db = SQLite3::Database.new(File.join(File.dirname(__FILE__), config['database']))
table = config['db_table']
Tmdb.api_key = config['api_key']

# really create sub-dirs in each type of action, false to disable
CREATE_DIRS = true
# If set to false, limit to 1 (daemon mode)
MULTIPLE_MATCH_ASK = false

# mappings from yaml to a directory name, to be concatted onto
# the config's 'directory' key
ACTIONS = {
  'director' => Proc.new do |movie, options|
    directors = movie.cast.select {|c| c.job = "Director"}
    directors[0].name if directors && directors[0]
  end,
  'decade' => Proc.new do |movie, options|
    begin
      year = Date.parse(movie.released).year
      (year - (year % 10)).to_s + (options['suffix'] || '')
    rescue
      nil
    end
  end,
  'genre' => Proc.new { |movie, options| movie.genres.map { |m| m.name } },
  'rating' => Proc.new { |movie, options| movie.rating.to_i.to_s },
  'year' => Proc.new do |movie, options|
    begin
      Date.parse(movie.released).year.to_s
    rescue
      nil
    end
  end
}

def log(msg)
  puts msg
end

def create_link(source_dir, dest_dir, filename, dest_filename = nil)
  # Default to the original filename
  dest_filename ||= filename
  if CREATE_DIRS && !File.exists?(dest_dir)
    Dir.mkdir(dest_dir)
  end

  exec_str = "ln -s \"#{File.join(source_dir, filename)}\" \"" +
    File.join(dest_dir, dest_filename) + "\""
  if (!system(exec_str))
    log(">> ERROR: Could not execute command: #{exec_str}")
  end

end

def ignore(filename, db)
  stmt = db.prepare("INSERT INTO ignore (filename) VALUES (?)")
  stmt.bind_params(filename)
  stmt.execute
end

Dir.glob(File.join(config['base_dir'], "*.*")) do |filename|
  base_filename = File.basename(filename)
  base_parts = base_filename.split('.')
  if base_parts.length > 1
    base_parts = base_parts[(0..(base_parts.length-2))]
  end
  base_name = base_parts.join(" ")

  # Check to see if it's a bad title so we don't hammer TMDB
  ignore_movie = db.get_first_value("select count(*) from ignore WHERE filename = ?",
      filename)
  if ignore_movie != '0'
    next
  end

  existing_movie = db.get_first_value("select * from #{table} where filename = ?",
      filename)
  if existing_movie.nil?
    log "Looking up '#{base_name}'"
    opts = {:title => base_name}
    opts[:limit] = (MULTIPLE_MATCH_ASK ? 10 : 1)
    movie = TmdbMovie.find(opts)
    if (movie.nil?)
      log "ERROR: Could not find TMDB info for '#{base_name}'"
      ignore(filename, db)
      next
    end

    if (movie.is_a? Array)
      if !MULTIPLE_MATCH_ASK || movie.length == 0
        log("Got #{movie.length} results, ignoring")
        ignore(filename, db)
        next
      else
        matches = movie.select {|m| m.name.downcase.gsub(/^(the)|(a) /, '') == base_name.downcase}
        if (!matches.nil? && matches.length == 1)
          log("Found exact title match")
          movie = matches[0]
        else
          puts("Need clarification for #{base_name}")
          movie.each_with_index do |m, i|
            puts "#{i}) #{m.name} #{m.released}"
          end
          index = -1
          while (index == -1 || index > movie.length) do
            puts "?"
            index = gets().chomp.to_i
            if (index == -2)
              ignore(filename, db)
              next
            end
          end
          movie = movie[index]
        end
        puts "Using #{movie.name} #{movie.released}"
      end
    end

    # pre-parse some info
    genres = (movie.genres || []).map { |m| m.name }
    begin
      released = Date.parse(movie.released).year
    rescue
      released = nil
    end
    directors = movie.cast.select { |c| c.job = "Director" }

    stmt = db.prepare("INSERT INTO #{table} (filename,name,genres,year,rating,director,imdb_id,certification) " +
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)")
    stmt.bind_params(
        filename,
        movie.name,
        genres.join(","),
        released,
        movie.rating,
        (directors.map { |d| d.name }).join(","),
        movie.imdb_id,
        movie.certification)

    config['categories'].each do |categorizer, options|
      action = ACTIONS[categorizer]
      if action.nil?
        log("ERROR: Unknown category type '#{category}'")
      else
        folders = action.call(movie, options)
        if folders.nil?
          next
        end
        if folders.is_a? String
          folders = [folders]
        end
        folders.each do |folder|
         full_folder = File.join(config['destination_dir'],
             options['directory'], folder)
#           log("Linking '#{movie.name}' into '#{full_folder}'")
          create_link(config['base_dir'], full_folder,
              base_filename, base_filename)
          # TODO: Intelligent rename? Could get us into trouble
        end
      end
    end

    stmt.execute
  end
end

