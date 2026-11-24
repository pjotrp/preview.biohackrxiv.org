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

Only a **repository URL** is accepted.  A zip upload used to be the other way
in, and it was dropped: a paper is deposited from a repository, so that the
record can name the repository it came from and a later submission of the same
paper can be recognised as a new version of the same record rather than as a
different paper.  The URL is passed to the transport (`xiv-publish submit …
--repo-url …`), which records it with the version as the authoritative address
of the submission — the `git_url` in the paper's own header is a claim the
author can leave stale.

After a successful render the PDF is shown in a page with a **Submit to Zenodo**
link, which leads to a screen asking for **your own Zenodo personal access
token** — the record is created in your account, so the token has to be yours.
That screen explains how to make one (Zenodo → Settings → Applications →
Personal access tokens → New token, with the scopes `deposit:write` and
`deposit:actions`), and the deposit runs when its button is pressed.  The token
is handed to the transport in the child process's environment for that one
request: not written to a file, not kept in a cookie or the database, not
logged, and it can be revoked on the same Zenodo page afterwards.  The service
itself therefore needs **no token of its own**, and there is no way to deposit by
pressing a button twice in a row without one.

The deposit creates a record the first time and a new version of the same concept
record afterwards, then deletes the staged copy.

One thing this does not solve yet: with per-author tokens, papers deposited by
different people land in different Zenodo accounts, and the submissions database
records the record id and DOI without recording *whose* account holds it.  The
paper's identity (repository URL plus title) is still right; ownership is not
recorded, so "this paper has a record" means "a record exists somewhere", not
"our record".

`PREVIEW_WORKDIR` defaults to `$XDG_STATE_HOME/preview.biohackrxiv.org`; that is
the directory nginx should serve `public/papers` from.  Where `/var/guix` is not
writable (so `guix shell` cannot create a profile), use a profile instead:

```
$ mkdir -p ~/.local/share/preview          # guix will not create the directory
$ guix package -p ~/.local/share/preview/profile -f guix.scm
$ . ~/.local/share/preview/profile/etc/profile
$ preview-web                              # serves 0.0.0.0:9292
```

The comments at the top of `guix.scm` explain how the pieces fit: pandoc is
Guix's own (3.7.0.2 and later - `bhxiv-gen-pdf` branches its LaTeX template on
the pandoc version), texlive is a curated list rather than the full scheme, and
the texlive packages are propagated because only a profile can render.

Both `guix.scm` and the renderer it builds are fetched from GitHub at pinned
commits, so a build needs nothing but the file and the network.  While editing
the service itself, point the source at the working tree:

```
$ guix build -f guix.scm --with-source=preview-biohackrxiv-org=$PWD
```

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
