class Categorizer
  def initialize(config_file, opts = {})
    @config       = File.open(config_file) { |yf| YAML::load(yf) }
    @db           = SQLite3::Database.new(File.join(File.dirname($0), @config['database']))
    @table        = @config['db_table']
    Tmdb.api_key  = @config['api_key']
    @create_dirs  = opts[:create_dirs] || true
    @first_match  = opts[:first_match] || true
  end

  def log(msg)
    puts msg
  end

  def create_link(source_dir, dest_dir, filename, dest_filename = nil)
    # Default to the original filename
    dest_filename ||= filename
    if @create_dirs && !File.exists?(dest_dir)
      FileUtils.mkdir_p(dest_dir)
    end

    exec_str = "ln -s \"#{File.join(source_dir, filename)}\" \"" +
      File.join(dest_dir, dest_filename) + "\""
    if (!system(exec_str))
      log(">> ERROR: Could not execute command: #{exec_str}")
    end

  end

  def ignore(filename)
    stmt = @db.prepare("insert into ignore (filename) values (?)")
    stmt.bind_params(filename)
    stmt.execute
  end

  def add_match(m, filename, base_filename)
    log("Adding match: #{base_filename}")

    @config['categories'].each do |category, options|
      # Grab the info from the movie object
      folders = m[category]
      next if folders.nil?

      if !folders.is_a?(Array)
        folders = [folders]
      end
      folders.each do |folder|
        full_folder = File.join(@config['destination_dir'],
           options['directory'], folder.to_s)
        create_link(@config['base_dir'], full_folder,
            base_filename, base_filename)
        # TODO: Intelligent rename? Could get us into trouble
      end
    end

    stmt = @db.prepare("insert into #{@table} (filename,name,genres,year,rating,director,imdb_id,certification) " +
        "values (?, ?, ?, ?, ?, ?, ?, ?)")
    stmt.bind_params(
        filename,
        m[:name],
        m.genre.join(","),
        m.year,
        m.rating,
        m.director,
        m[:imdb_id],
        m[:certification])

    stmt.execute
  end

  def scan_all
    Dir.glob(File.join(@config['base_dir'], "*.*")) do |filename|
      base_filename = File.basename(filename)
      base_parts = base_filename.split('.')
      if base_parts.length > 1
        base_parts = base_parts[(0..(base_parts.length-2))]
      end
      base_name = base_parts.join(" ")
      puts "Filename: #{filename}"

      # Check to see if it's a bad title so we don't hammer TMDB
      ignore_movie = @db.get_first_value("select count(*) from ignore where filename = ?",
          filename)
      if ignore_movie != 0
        next
      end

      existing_movie = @db.get_first_value("select * from #{@table} where filename = ?",
          filename)

      next unless existing_movie.nil?

      log "Looking up '#{base_name}'"
      opts = {:title => base_name, :limit => (@first_match ? 1 : 10)}
      movie = find_in_tmdb(opts)
      add_match(movie, filename, base_filename) unless movie.nil?
    end
  end

  def find_in_tmdb(opts)
    matches = TmdbMovie.find(opts)
    if (matches.nil?)
      logger.log "ERROR: Could not find TMDB info for '#{base_name}'"
      ignore(filename)
      return
    end

    if (matches.is_a? Array)
      matches.select! {|m| m.name.downcase.gsub(/^(the)|(a) /, '') == base_name.downcase}
      if @first_match || matches.length == 0
        log("Got #{matches.length} results, ignoring")
        ignore(filename)
        return
      else
        if (!matches.nil? && matches.length == 1)
          log("Found exact title match")
          matches = matches.first
        else
          puts("Need clarification for #{base_name}")
          matches.each_with_index do |m, i|
            puts "#{i}) #{m.name} #{m.released}"
          end
          index = -1
          while (index == -1 || index > matches.length) do
            puts "?"
            index = gets().chomp.to_i
            if (index == -2)
              ignore(filename)
              return
            end
          end
          matches = matches[index]
        end
        log "Using #{matches.name} #{matches.released}"
      end
    end

    return Movie.new(matches)
  end
end
