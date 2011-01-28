MovieCat - A dumb movie categorizer
===================================

## What It Does
* Scans a directory of files and gathers information from TheMovieDatabase (TMDB)
* Builds a SQLite database of information, including rating, genre, year, and director
* Creates symlinks to ease browsing your movie collection

## Configuration
* You'll need a TMDB api key, available from http://www.themoviedb.org
* Edit config.yml to include your api key, as well as your directory layout
* Optional: modify moviecat.rb's ACTIONS hash to match your desired link structure

## Running
* There are two major modes: unattended, and attended.
  Right now, they're configured via
    MULTIPLE_MATCH_ASK = true # (or false if you're running via cron)
  This configures whether you want the script to ask you when it finds multiple
  matches for the same movie title. If false, it'll choose the first one TMDB returns

