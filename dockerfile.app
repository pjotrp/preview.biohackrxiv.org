FROM ruby:2.7.0
RUN apt-get update -y && \
    apt-get install -y \
      pandoc=2.2.1-3+b2 \
      pandoc-citeproc=0.14.3.1-4+b3 \
      texlive-latex-base=2018.20190227-2 \
      texlive-fonts-recommended=2018.20190227-2 \
      texlive-fonts-extra=2018.20190227-2 \
      texlive-latex-extra=2018.20190227-2 \
      texlive-bibtex-extra=2018.20190227-2
WORKDIR /
RUN git clone "https://github.com/biohackrxiv/bhxiv-gen-pdf" --depth 1 && chmod +x /bhxiv-gen-pdf/bin/gen-pdf
ENV PATH $PATH:/bhxiv-gen-pdf/bin
COPY . /app/
WORKDIR /app
RUN bundle install
EXPOSE 9292
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
