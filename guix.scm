;;; guix.scm -- GNU Guix package definitions for preview.biohackrxiv.org
;;;
;;; This file builds the preview web service together with the BioHackrXiv PDF
;;; generator it shells out to, so that one environment has everything the
;;; service needs at run time:
;;;
;;;   guix shell -f guix.scm -- preview-web      start the service on :9292
;;;   guix build -f guix.scm                     build it
;;;   guix shell -D -f guix.scm                  development environment
;;;
;;; What runs where.  app.rb stages a submission (zip upload or git clone) under
;;; /tmp/<uuid>, finds paper.md, and calls `gen-pdf' from PATH.  gen-pdf is a
;;; Ruby program in the sibling bhxiv-gen-pdf repository that renders the paper
;;; with pandoc and LaTeX.  So the service needs three things beyond Ruby and
;;; its gems: the gen-pdf command, pandoc, and a TeX installation carrying the
;;; packages this publication template uses.
;;;
;;; pandoc is Guix's own (3.7.0.2).  It has to be: resources/biohackrxiv/
;;; latex.template was written for pandoc 2, and until bhxiv-gen-pdf learned to
;;; branch on the pandoc version this file had to pin the pandoc 2.16.1 release
;;; binary to get a PDF at all.  That branch is why nothing here pins pandoc any
;;; more; the SVG images that pandoc 3 would hand to the LaTeX svg package (and
;;; Inkscape) are converted with rsvg-convert by bhxiv-gen-pdf's own filter, so
;;; no texlive-svg either.
;;;
;;; texlive is still a curated list, not texlive-scheme-full (several GB).  The
;;; list is what latex.template loads, and the check phase of bhxiv-gen-pdf
;;; renders example/logic to prove it is enough.
;;;
;;; Both sources are git-fetches, from the fork that carries the pandoc 3 work
;;; until it lands upstream; see the comments on %preview-commit and
;;; %gen-pdf-commit.
;;;
;;; `guix shell' needs a writable /var/guix.  On a box where that is not
;;; available (read-only root), the equivalent is
;;;
;;;   guix package -p ~/.local/share/preview/profile -f guix.scm
;;;   . ~/.local/share/preview/profile/etc/profile
;;;   preview-web

(use-modules (gnu packages)
             (gnu packages base)
             (gnu packages bash)
             (gnu packages compression)
             (gnu packages gnome)
             (gnu packages haskell-xyz)     ;pandoc
             (gnu packages python)          ;xiv-publish
             (gnu packages python-xyz)      ;python-pyyaml
             (gnu packages nss)
             (gnu packages ruby)
             (gnu packages ruby-xyz)
             (gnu packages tex)
             (gnu packages version-control)
             (guix build-system copy)
             (guix gexp)
             (guix git-download)
             (guix packages)
             ((guix licenses) #:prefix license:)
             (srfi srfi-13))

;;; ---------------------------------------------------------------------------
;;; Ruby.
;;; ---------------------------------------------------------------------------

;; The gem packages in (gnu packages ruby-xyz) are built for one Ruby ABI --
;; puma and nio4r install their native extensions under
;; lib/ruby/vendor_ruby/extensions/x86_64-linux/3.3.0 -- and putting two Ruby
;; versions in one profile is a profile collision.  So the whole file uses the
;; Ruby those gems were built against rather than the newest one in Guix.
(define %ruby ruby-3.3)

;;; ---------------------------------------------------------------------------
;;; The TeX packages resources/biohackrxiv/latex.template loads.
;;; ---------------------------------------------------------------------------

(define %texlive-packages
  (list texlive-scheme-basic      ;latex-base, latex-recommended
        texlive-amsfonts          ;amssymb
        texlive-amsmath           ;amsmath
        texlive-biblatex          ;the template loads it unconditionally
        texlive-booktabs          ;booktabs
        texlive-caption           ;caption
        texlive-cjk               ;CJKutf8, for CJK runs in a paper
        texlive-colortbl          ;colortbl
        texlive-etoolbox          ;etoolbox
        texlive-fancyhdr          ;fancyhdr
        texlive-fancyvrb          ;fancyvrb
        texlive-float             ;float
        texlive-fontawesome5      ;fontawesome5
        texlive-geometry          ;geometry (pandoc -V geometry:margin=1in)
        texlive-graphics          ;graphicx
        texlive-grffile           ;grffile
        texlive-hyperref          ;hyperref
        texlive-iftex             ;iftex, ifxetex, ifluatex
        texlive-ipaex-type1       ;ipxm, the Japanese font CJK runs use
        texlive-listings          ;listings
        texlive-lm                ;lmodern
        texlive-marginnote        ;marginnote
        texlive-microtype         ;microtype
        texlive-natbib            ;natbib
        texlive-parskip           ;parskip
        texlive-pgf               ;tikz
        texlive-preprint          ;authblk
        texlive-seqsplit          ;seqsplit
        texlive-tcolorbox         ;tcolorbox
        texlive-titlesec          ;titlesec
        texlive-tools             ;array, calc, longtable, tabularx
        texlive-ulem              ;ulem
        texlive-xcolor            ;xcolor
        texlive-xstring))         ;xstring

;; What rendering needs at run time: the TeX trees, pandoc, and the
;; few command-line tools gen-pdf calls.  bhxiv-gen-pdf has these as inputs; the
;; service propagates them so that the profile it is installed into contains
;; them, because that is where Guix's texlive profile hook writes fmtutil.cnf.
(define %renderer-runtime
  (append %texlive-packages
          (list pandoc                   ;Guix's pandoc 3, see the header
                librsvg                  ;rsvg-convert, for SVG images
                coreutils-minimal
                bash-minimal)))

;;; ---------------------------------------------------------------------------
;;; bhxiv-gen-pdf -- the renderer, from its own repository.
;;; ---------------------------------------------------------------------------

;; Pinned to the commit that teaches the LaTeX template about pandoc 3 and adds
;; the SVG filter; anything older renders with pandoc 2 only and fails against
;; Guix's pandoc.  The fork is the URL because the commit is not in the
;; biohackrxiv organisation's repository yet -- switch both this URL and
;; %preview-source's when it is.
(define %gen-pdf-commit
  "cebc898935f57558e08580f9beeadf640fc08702")

(define bhxiv-gen-pdf
  (package
    (name "bhxiv-gen-pdf")
    (version (git-version "0.1.0" "0" %gen-pdf-commit))
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/pjotrp/bhxiv-gen-pdf")
             (commit %gen-pdf-commit)))
       (file-name (git-file-name name version))
       (sha256
        (base32
         "169yimzjqncj7cgcf0d6asx1fy1v71iyz93sh8mxswl6lnrdk0fp"))))
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan
      #~'(;; bin/gen-pdf works out its own root by going up two directories
         ;; from __FILE__, then loads lib/ from there and the LaTeX template,
         ;; CSL styles and CiTO Lua filters from resources/.
         ("bin/gen-pdf" "bin/gen-pdf")
         ("lib" "lib")
         ("resources" "resources")
         ;; Kept for the preview service, which renders this example once at
         ;; start-up to prove the toolchain works.
         ("example" "share/bhxiv-gen-pdf/example"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'install 'wrap
            (lambda* (#:key inputs outputs #:allow-other-keys)
              (let ((out (assoc-ref outputs "out")))
                ;; pandoc, rsvg-convert (pandoc turns the SVGs of a paper into
                ;; PDF through it) and the coreutils gen-pdf calls come from
                ;; the inputs, not from whatever PATH the caller has.  A value
                ;; the caller already has is kept behind ours.
                ;;
                ;; LaTeX is deliberately not handled here.  pdflatex finds the
                ;; TeX trees through GUIX_TEXMF, and that variable has to name
                ;; one directory holding every tree: fmtutil.cnf and ls-R are
                ;; generated by a Guix *profile hook*, so a list of store
                ;; directories has no pdflatex.fmt and fails with "I can't find
                ;; the format file".  GUIX_TEXMF therefore comes from the
                ;; profile `guix shell -f guix.scm' builds, which is why this
                ;; package propagates its texlive inputs.
                (wrap-program (string-append out "/bin/gen-pdf")
                  #:sh #$(file-append bash-minimal "/bin/bash")
                  `("PATH" ":" prefix
                    (,(string-append (assoc-ref inputs "pandoc") "/bin")
                     ,(string-append (assoc-ref inputs "librsvg") "/bin")
                     ,(string-append (assoc-ref inputs "coreutils") "/bin")))))))
          (add-after 'wrap 'check-render
            (lambda* (#:key outputs #:allow-other-keys)
              ;; Render the example with --debug and a .tex output: that runs
              ;; the whole pandoc pipeline -- YAML header checks, the LaTeX
              ;; template, the CSL style and the two CiTO filters -- without
              ;; needing a TeX installation, which only a profile can provide
              ;; (see the comment in the wrap phase).  With --citeproc the
              ;; citations are formatted inline, so there is no \\cite or
              ;; \\bibitem to look for; \\bibliography comes from the Lua
              ;; filter that turns cito-bibliography into pandoc's
              ;; bibliography variable, and its presence is what proves the
              ;; filter ran.
              (let* ((out (assoc-ref outputs "out"))
                     (example (string-append out
                                             "/share/bhxiv-gen-pdf/example"))
                     (tex (string-append (getcwd) "/example.tex")))
                (invoke (string-append out "/bin/gen-pdf")
                        "--debug"
                        (string-append example "/logic")
                        tex)
                (call-with-input-file tex
                  (lambda (port)
                    (use-modules (ice-9 textual-ports))
                    (let ((text (get-string-all port)))
                      (unless (string-contains text "\\documentclass")
                        (error "the LaTeX template was not applied" tex))
                      (unless (string-contains text "\\bibliography{paper.bib}")
                        (error "the CiTO filter did not set the bibliography"
                               tex)))))))))))
    (native-inputs (list %ruby))    ;for the #!/usr/bin/env ruby shebang
    (inputs %renderer-runtime)
    (home-page "https://github.com/biohackrxiv/bhxiv-gen-pdf")
    (synopsis "Render a BioHackrXiv publication from a paper.md directory")
    (description
     "bhxiv-gen-pdf turns a directory holding paper.md, paper.bib and images
into the PDF that BioHackrXiv publishes: it checks the YAML header, then runs
pandoc with the BioHackrXiv LaTeX template, CSL style and CiTO citation
filters.")
    (license license:gpl3)))

;;; ---------------------------------------------------------------------------
;;; xiv-publish -- the transport the service calls, like gen-pdf.
;;; ---------------------------------------------------------------------------

;; A local-file for the same reason as nothing else here: the repository is not
;; published yet, so there is no commit to fetch.  When it is, replace this with
;; a git-fetch of the same shape as bhxiv-gen-pdf's above.
(define %xiv-publish-source
  (local-file (in-vicinity (dirname (dirname (current-filename))) "xiv-publish")
              "xiv-publish-checkout"
              #:recursive? #t
              #:select? (lambda (file stat)
                          (let ((rel (string-drop file (string-length
                                                        (in-vicinity
                                                         (dirname (dirname (current-filename)))
                                                         "xiv-publish")))))
                            (not (or (string-prefix? "/.git/" rel)
                                     (string=? "/.git" rel)
                                     (string-suffix? ".sqlite" rel)
                                     (string-suffix? ".sqlite-db" rel)
                                     (string-prefix? "/__pycache__/" rel)))))))

(define xiv-publish
  (package
    (name "xiv-publish")
    (version "0.0.1")
    (source %xiv-publish-source)
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan
      #~'(("xiv_publish" "lib/python3.12/site-packages/xiv_publish")
         ("bin/xiv-publish" "bin/xiv-publish"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'install 'wrap
            (lambda* (#:key inputs outputs #:allow-other-keys)
              (let* ((out (assoc-ref outputs "out"))
                     (site (string-append out "/lib/python3.12/site-packages"))
                     (python (assoc-ref inputs "python"))
                     (yaml (assoc-ref inputs "python-pyyaml")))
                ;; Both the package and pyyaml come from the store, so the tool
                ;; works in an environment that has nothing else on PYTHONPATH.
                (wrap-program (string-append out "/bin/xiv-publish")
                  #:sh (search-input-file inputs "bin/bash")
                  `("PYTHONPATH" ":" prefix
                    (,site ,(string-append yaml "/lib/python3.12/site-packages")))
                  `("PATH" ":" prefix (,(string-append python "/bin"))))))))))
    (inputs (list python python-pyyaml bash-minimal))
    (home-page "https://github.com/pjotrp/xiv-publish")
    (synopsis "Deposit a BioHackrXiv paper in Zenodo")
    (description
     "The publishing transport: it reads a paper's YAML header, creates a Zenodo
record or a new version of the one the paper already has, renders the paper with
its concept DOI, uploads the PDF and its sources, and publishes.")
    (license license:agpl3+)))

;;; ---------------------------------------------------------------------------
;;; The preview service itself.
;;; ---------------------------------------------------------------------------

;; Fetched rather than taken from the checkout this file lives in, so that
;; `guix build -f guix.scm' needs nothing but this file and the network.
;;
;; The pin is the commit *before* the one carrying this change, which costs
;; nothing: guix.scm is not installed, and the files that are (app.rb,
;; config.ru, views/, lib/, config/, scripts/preview-web, the logo, nginx.conf)
;; are identical in both.  Bump %preview-commit when any of those change; a
;; build of the working tree is what you want while editing them:
;;
;;   guix build -f guix.scm --with-source=preview-biohackrxiv-org=$PWD
;;
;; ($PWD and not ".": --with-source rejects a source that begins with a dot.)
(define %preview-commit
  "26c83e629572152db9b0fd300db7bf56ac2e031a")

(define %source
  (origin
    (method git-fetch)
    (uri (git-reference
          (url "https://github.com/pjotrp/preview.biohackrxiv.org")
          (commit %preview-commit)))
    (file-name (git-file-name "preview-biohackrxiv-org" "0.1.0"))
    (sha256
     (base32
      "1ya7aasihanizihs9g49fszxz52qwj6k8ykv4m52w11ymd0za4zp"))))

(define preview-biohackrxiv-org
  (package
    (name "preview-biohackrxiv-org")
    (version "0.1.0")
    (source %source)
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan
      #~'(("app.rb" "share/preview-biohackrxiv-org/app/")
         ("config.ru" "share/preview-biohackrxiv-org/app/")
         ("lib" "share/preview-biohackrxiv-org/app/lib")
         ("views" "share/preview-biohackrxiv-org/app/views")
         ("config" "share/preview-biohackrxiv-org/app/config")
         ;; public/papers is generated at run time; only the logo is source.
         ("public/BioHackrXiv-logo-transparent-340x140.png"
          "share/preview-biohackrxiv-org/app/public/")
         ("scripts/preview-web" "bin/preview-web")
         ("README.md" "share/preview-biohackrxiv-org/")
         ("nginx.conf" "share/preview-biohackrxiv-org/"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'guix-runtime
            (lambda* (#:key inputs #:allow-other-keys)
              ;; config.ru starts from Bundler, which would try to resolve three
              ;; gems over the network.  The same three are in this package's
              ;; inputs, so require them directly.
              ;; substitute* works line by line, so these are three
              ;; single-line patterns and not one block.
              (substitute* "config.ru"
                (("require \"bundler\"") "require \"sinatra\"")
                (("Bundler.require") "require \"slim\""))
              ;; app.rb renders bhxiv-gen-pdf/example once at start-up to prove
              ;; that pandoc and LaTeX are wired up, through the absolute path
              ;; the Docker image happens to use.  Point that at the installed
              ;; example and at the gen-pdf command instead.
              ;; The self-test copies bhxiv-gen-pdf/example to /tmp and renders
              ;; it there, which needs write access to the example.  Here the
              ;; example is an installed store path, so drop the copy (the
              ;; "true") and render it in place with an output path under /tmp:
              ;; gen-pdf changes into the paper directory and takes the output
              ;; file as an absolute path.
              (substitute* "app.rb"
                (("cp -vau /bhxiv-gen-pdf/example /tmp/") "true")
                (("cd /bhxiv-gen-pdf && ruby ./bin/gen-pdf --debug /tmp/example/logic")
                 (string-append "gen-pdf "
                                #$(this-package-input "bhxiv-gen-pdf")
                                "/share/bhxiv-gen-pdf/example/logic "
                                "/tmp/preview-selftest.pdf")))))
          (add-before 'install 'check-substitutions
            (lambda _
              ;; Two things break the service without breaking the build: a
              ;; syntax error, and a substitution above that missed.  Loading
              ;; app.rb would test more, but it can only resolve its gems inside
              ;; the profile the service runs in -- sinatra's dependencies
              ;; (mustermann and friends) are other packages' outputs, so
              ;; GEM_PATH cannot be assembled here.  The gem closure is what
              ;; `guix shell -f guix.scm -- preview-web' exercises.
              (invoke "ruby" "-c" "app.rb")
              (invoke "ruby" "-c" "config.ru")
              (for-each (lambda (file)
                          (call-with-input-file file
                            (lambda (port)
                              (use-modules (ice-9 textual-ports))
                              (let ((text (get-string-all port)))
                                (when (string-contains text "Bundler.require")
                                  (error "config.ru still starts from Bundler"
                                         file))
                                ;; Not "/bhxiv-gen-pdf": the installed
                                ;; store path contains that string too.
                                (when (string-contains text "cd /bhxiv-gen-pdf")
                                  (error "app.rb still shells out to the Docker path"
                                         file))))))
                        '("config.ru" "app.rb"))))
          (add-after 'install 'patch-runner
            (lambda* (#:key outputs #:allow-other-keys)
              (let* ((out (assoc-ref outputs "out"))
                     (runner (string-append out "/bin/preview-web")))
                (substitute* runner
                  (("@APP@")
                   (string-append out "/share/preview-biohackrxiv-org/app")))
                (chmod runner #o555))))
          (replace 'install-license-files
            ;; The repository has no LICENSE file yet; nothing to install.
            (lambda _ #t)))))
    ;; Propagated, not ordinary inputs: `guix shell -f guix.scm' builds a
    ;; profile from this package and its propagated inputs, and only packages
    ;; in a profile get their search paths set -- GEM_PATH for the gems, PATH
    ;; for gen-pdf.  pandoc and TeX arrive through gen-pdf's own wrapper.
    (propagated-inputs
     (append
      %renderer-runtime
      (list bhxiv-gen-pdf
           xiv-publish
           %ruby
           ruby-sinatra
           ruby-slim
           ruby-puma
           ruby-nio4r                 ;puma's reactor, not propagated by puma
           ruby-rack-protection
           git                        ;app.rb clones the submitted repository
           unzip                      ;or unpacks the uploaded zip
           coreutils-minimal          ;cp, touch
           nss-certs)))               ;so that the clone can verify TLS
    (native-inputs (list %ruby))       ;for the runner's #!/usr/bin/env ruby
    (inputs (list bash-minimal))
    (home-page "https://preview.biohackrxiv.org/")
    (synopsis "Preview service for BioHackrXiv publications")
    (description
     "A small Sinatra application that renders a submitted BioHackrXiv
publication to PDF.  It accepts either a zip file or the URL of a git
repository, finds paper.md inside, calls bhxiv-gen-pdf, and redirects to the
generated PDF.")
    ;; The repository carries no LICENSE file; the project the service belongs
    ;; to (xiv-publish) is AGPL-3.0-or-later, so declare that and revisit when
    ;; this repository gets a license of its own.
    (license license:agpl3+)))

;; `guix build -f guix.scm' and `guix shell -f guix.scm' both use the last
;; expression of this file.
preview-biohackrxiv-org
