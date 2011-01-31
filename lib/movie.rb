class Movie
  def initialize(data)
    @data = data
  end

  def decade
    year - (year % 10)
  end

  def director
    directors = @data.cast.select { |c| c.job == 'Director' }
    directors.first.name if directors && directors.first
  end

  def genre
    @data.genres.map { |g| g.name } if @data.genres
  end

  def rating
    @data.rating.to_s
  end

  def year
    Date.parse(@data.released).year if @data.released
  end

  # Pass any other calls to the OpenStruct
  def [] (name)
    if @data.respond_to?(name.to_s)
      return @data.send(name.to_s)
    elsif self.respond_to?(name.to_sym)
      return self.send(name.to_sym)
    end
  end
end
