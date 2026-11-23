# Webapp in Ruby/Sinatra/Puma/Nginx for preview.biohackrxiv.org

For testing:

```
$ git clone https://github.com/biohackrxiv/preview.biohackrxiv.org
$ cd preview.biohackrxiv.org
$ docker-compose up --build
```

To run on background:

```
$ docker-compose up -d --build
```

Stop and remove containers:

```
$ docker-compose down
```

# Build and run with GNU Guix

`guix.scm` builds the service together with the PDF generator it calls, so one
environment has pandoc, LaTeX and `gen-pdf`:

```
$ guix shell -f guix.scm -- preview-web      # serve on 0.0.0.0:9292
$ PORT=8080 PREVIEW_HOST=127.0.0.1 preview-web
$ PREVIEW_WORKDIR=/srv/preview preview-web   # where generated PDFs and logs go
```

`PREVIEW_WORKDIR` defaults to `$XDG_STATE_HOME/preview.biohackrxiv.org`; that is
the directory nginx should serve `public/papers` from.  Where `/var/guix` is not
writable (so `guix shell` cannot create a profile), use a profile instead:

```
$ guix package -p ~/.local/share/preview/profile -f guix.scm
$ . ~/.local/share/preview/profile/etc/profile
$ preview-web
```

The comments at the top of `guix.scm` explain the two pins (pandoc 2.16.1 and a
curated texlive set) and why the service package propagates them.

# Run with GNU Guix (older shell setup)

```
source .guix-deploy
puma

Puma starting in single mode...

* Puma version: 5.3.2 (ruby 2.6.5-p114) ("Sweetnighter")
*  Min threads: 0
*  Max threads: 16
*  Environment: production
* Listening on http://0.0.0.0:9292

```

To run the development version:

```
puma -t 1 -e development
```

or for more info

```
puma -t 1 -e development --redirect-stderr /dev/stdout \
  --redirect-stdout /dev/stdout -w 0 -v
```
